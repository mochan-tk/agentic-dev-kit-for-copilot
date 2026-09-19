#!/usr/bin/env bash
# Test the shipped event/producer contract; hosted run evidence is separate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "error: python3 with PyYAML is required for workflow contract tests" >&2
  exit 2
fi

python3 - "$ROOT" <<'PY'
import copy
from pathlib import Path
import re
import sys
import unittest

import yaml

ROOT = Path(sys.argv.pop())
CODE = {"quality", "scaffold-self-check", "copilot-surface", "windows-launcher"}
PR = "github.event_name == 'pull_request'"
GUARD = "bash .github/scripts/check-task-ritual.sh"
SENSOR = "bash .github/scripts/check-retarget-freshness.sh"


def load():
    # BaseLoader preserves the Actions key "on" instead of YAML 1.1 boolean True.
    return {
        path.name: yaml.load(path.read_text(), Loader=yaml.BaseLoader)
        for path in (ROOT / ".github/workflows").glob("*.yml")
    }


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def admitted(workflow, event):
    declaration = workflow.get("on", {})
    if event["name"] not in declaration:
        return False
    config = declaration[event["name"]]
    if event["name"] == "pull_request":
        return event["action"] in config.get(
            "types", ["opened", "synchronize", "reopened"]
        )
    return event["ref"] in config.get("branches", [event["ref"]])


def producers(workflows, event):
    return [
        (filename, job.get("name", key))
        for filename, workflow in workflows.items()
        if admitted(workflow, event)
        for key, job in workflow.get("jobs", {}).items()
        if job.get("name", key) in CODE | {"task-ritual"}
    ]


def contract(workflows):
    ci = workflows["ci.yml"]
    require("task-ritual.yml" in workflows, "separate ledger workflow is missing")
    ledger = workflows["task-ritual.yml"]
    require(ci["name"] != ledger["name"], "workflow names must differ")
    for workflow, types, group in (
        (ci, ["opened", "synchronize", "reopened"], "ci-${{ github.ref }}"),
        (ledger, ["opened", "synchronize", "reopened", "edited"],
         "task-ritual-${{ github.ref }}"),
    ):
        require(workflow["on"] == {
            "pull_request": {"types": types}, "push": {"branches": ["main"]}
        }, "exact event contract (no privileged or extra triggers)")
        require(workflow["concurrency"] == {
            "group": group, "cancel-in-progress": "${{ " + PR + " }}"
        }, "separate concurrency domains with PR-only cancellation")
        require(workflow["permissions"] == {"contents": "read"},
                "workflow grants must be read-only")
    require(set(ci["jobs"]) == CODE, "code contexts must have real sole producers")
    require(set(ledger["jobs"]) == {"task-ritual"}, "ledger must not emit code checks")
    for workflow in (ci, ledger):
        for job in workflow.get("jobs", {}).values():
            require("concurrency" not in job,
                    "job-level concurrency must not bypass workflow isolation")
    anchors = {
        "quality": "bash .github/scripts/check-action-pins.sh",
        "scaffold-self-check": "bash .github/scripts/tests/run-tests.sh",
        "copilot-surface": "bash .github/scripts/check-copilot-surface.sh",
        "windows-launcher": "& pwsh .github/scripts/run.ps1 tuning-status.sh --quiet",
    }
    for key, job in ci["jobs"].items():
        require("if" not in job and "needs" not in job
                and "continue-on-error" not in job,
                "code verification cannot be conditional or failure-tolerant")
        require(job.get("name", key) == key, "required code name changed")
        require(job.get("runs-on") == (
            "windows-latest" if key == "windows-launcher" else "ubuntu-latest"
        ), "code runner must be available")
        steps = job.get("steps", [])
        require(any(anchors[key] in step.get("run", "") for step in steps),
                "real code verification missing, not a synthetic success")
        require(all("if" not in step and "continue-on-error" not in step
                    for step in steps), "verification steps must not skip failures")
    job = ledger["jobs"]["task-ritual"]
    require(job.get("name", "task-ritual") == "task-ritual", "ledger name changed")
    require(job.get("if") == PR, "push must retain skipped ledger for issuer discovery")
    require(job.get("runs-on") == "ubuntu-latest", "ledger runner missing")
    require("needs" not in job and "continue-on-error" not in job,
            "ledger must independently fail closed")
    require(job["permissions"] == {
        "contents": "read", "issues": "read", "pull-requests": "read",
        "checks": "read", "actions": "read",
    }, "ledger grants must be exactly contents/issues/pull-requests/checks/actions read")
    steps = job["steps"]
    require(len(steps) == 3, "ledger must check out, run unchanged guard, then sensor")
    require(re.fullmatch(r"actions/checkout@[0-9a-f]{40}", steps[0]["uses"])
            and steps[0].get("with") == {"persist-credentials": "false"},
            "ledger checkout must be pinned with no persisted credentials")
    require(steps[1].get("run") == GUARD and steps[1].get("env") == {
        "GH_TOKEN": "${{ github.token }}",
        "PR_NUMBER": "${{ github.event.pull_request.number }}",
    }, "ledger must read current PR through unchanged guard")
    require(steps[2].get("run") == SENSOR and steps[2].get("env") == {
        "GH_TOKEN": "${{ github.token }}",
        "GH_REPO": "${{ github.repository }}",
        "PR_NUMBER": "${{ github.event.pull_request.number }}",
        "PR_HEAD_SHA": "${{ github.event.pull_request.head.sha }}",
    }, "sensor must bind current repository/PR/head, never the merge SHA")
    require(all("if" not in step and "continue-on-error" not in step for step in steps),
            "ledger guard cannot be skipped or softened")
    for action in ["opened", "synchronize", "reopened", "edited"]:
        event = {"name": "pull_request", "action": action}
        expected = [("task-ritual.yml", "task-ritual")]
        if action != "edited":
            expected += [("ci.yml", key) for key in CODE]
        require(sorted(producers(workflows, event)) == sorted(expected),
                "one intended producer per PR context/event")
    require(sorted(producers(workflows, {"name": "push", "ref": "main"}))
            == sorted([("ci.yml", key) for key in CODE]
                      + [("task-ritual.yml", "task-ritual")]),
            "default branch must retain every issuer-discovery context")


class Isolation(unittest.TestCase):
    def test_shipped_contract(self):
        contract(load())

    def test_repeated_edits_cannot_touch_code_results(self):
        workflows = load()
        code_group = workflows["ci.yml"]["concurrency"]["group"]
        # These are declaration-level assertions, not an Actions scheduler emulator.
        # Even unavailable/failed code results have no metadata producer to replace them.
        for state in ["in_progress", "success", "failure", "cancelled", "missing"]:
            for changes in [{"body": {"from": "old"}},
                            {"body": {"from": "second edit"}},
                            {"base": {"ref": {"from": "old-base"}}}]:
                with self.subTest(code_state=state, changes=changes):
                    event = {"name": "pull_request", "action": "edited",
                             "changes": changes}
                    self.assertEqual(producers(workflows, event),
                                     [("task-ritual.yml", "task-ritual")])
                    for workflow in workflows.values():
                        if admitted(workflow, event):
                            self.assertNotEqual(
                                workflow.get("concurrency", {}).get("group"), code_group
                            )

    def test_retarget_boundary_beside_event_list(self):
        header = (ROOT / ".github/workflows/ci.yml").read_text().split("  push:")[0]
        for text in ["head SHA", "base at run time", "strict: false", "retarget",
                     "ledger only", "new head push", "close/reopen"]:
            with self.subTest(text=text):
                self.assertIn(text, header)

    def test_negative_workflow_fixtures(self):
        original = load()
        contract(original)

        def rejected(name, mutate):
            with self.subTest(mutation=name):
                workflows = copy.deepcopy(original)
                mutate(workflows)
                with self.assertRaises(AssertionError):
                    contract(workflows)

        rejected("missing workflow", lambda w: w.pop("task-ritual.yml"))
        rejected("missing code producer", lambda w: w["ci.yml"]["jobs"].pop("quality"))
        rejected("duplicate producer", lambda w: w.update({"duplicate.yml": w["ci.yml"]}))
        rejected("shared concurrency", lambda w: w["task-ritual.yml"].update(
            concurrency=w["ci.yml"]["concurrency"]))
        rejected("shared job concurrency", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"].update(
                     concurrency=w["ci.yml"]["concurrency"]))
        rejected("edited schedules code", lambda w:
                 w["ci.yml"]["on"]["pull_request"]["types"].append("edited"))
        rejected("skipped synthetic code", lambda w:
                 w["task-ritual.yml"]["jobs"].update(quality={"if": "false", "steps": []}))
        rejected("conditional code", lambda w:
                 w["ci.yml"]["jobs"]["quality"].update({"if": PR}))
        rejected("synthetic green", lambda w:
                 w["ci.yml"]["jobs"]["quality"].update(steps=[{"run": "true"}]))
        rejected("unavailable code runner", lambda w:
                 w["ci.yml"]["jobs"]["quality"].update({"runs-on": "unavailable"}))
        rejected("soft failure", lambda w:
                 w["ci.yml"]["jobs"]["quality"].update({"continue-on-error": "true"}))
        rejected("changed guard", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["steps"][1].update(
                     run=GUARD + " || true"))
        rejected("write token", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["permissions"].update(
                     {"pull-requests": "write"}))
        rejected("no default branch ledger", lambda w:
                 w["task-ritual.yml"]["on"].pop("push"))
        rejected("removed sensor", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["steps"].pop())
        rejected("conditional sensor", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["steps"][2].update(
                     {"if": "false"}))
        rejected("softened sensor", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["steps"][2].update(
                     {"continue-on-error": "true"}))
        rejected("swallowed sensor failure", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["steps"][2].update(
                     run=SENSOR + " || true"))
        rejected("merge SHA instead of head", lambda w:
                 w["task-ritual.yml"]["jobs"]["task-ritual"]["steps"][2]["env"].update(
                     PR_HEAD_SHA="${{ github.sha }}"))
        for grant in ("checks", "actions"):
            rejected("missing " + grant + " read", lambda w, grant=grant:
                     w["task-ritual.yml"]["jobs"]["task-ritual"]["permissions"].pop(grant))
            rejected(grant + " write", lambda w, grant=grant:
                     w["task-ritual.yml"]["jobs"]["task-ritual"]["permissions"].update(
                         {grant: "write"}))


unittest.main(verbosity=2)
PY
