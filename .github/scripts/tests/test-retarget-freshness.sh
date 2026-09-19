#!/usr/bin/env bash
# Offline execution of the shipped ledger and its retarget sensor.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "error: python3 with PyYAML is required for ledger execution tests" >&2
  exit 2
fi

python3 - "$ROOT" <<'PY'
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml

ROOT = Path(sys.argv.pop())
REPO = "fixture/retarget"
PREFIX = "repos/" + REPO
HEAD = "24d6b1c8133002f00f6b5d3f1f218751f051f3de"
CONTEXTS = ("quality", "scaffold-self-check", "copilot-surface")
RUN = 35424930438
SUITE = 95937776650
CHECKS = (105849112489, 105849112508, 105849112492)
T = "2026-09-19T05:50:00Z"
RUN_LIST = PREFIX + "/actions/runs?head_sha=" + HEAD + "&per_page=100"
TIMELINE = PREFIX + "/issues/144/timeline?per_page=100"

# Synthetic retarget, NOT a captured live event: the documented timeline envelope
# needs no changes.base and permits null commit fields. Run/check shapes come from
# PR #144; this synthetic OPEN association uses the shape observed on PR #104.
# Page-2 links below follow the observed PR #126 /repositories/{id}/... shape.
# Reruns, ties, failures and mutations are synthetic; no users or tokens captured.
def fixture(name="retarget_after_success"):
    repo = {"id": 1330507890, "full_name": REPO}
    head = {"sha": HEAD, "repo": repo, "ref": "task/143-fixture"}
    base = {"sha": "b" * 40, "repo": repo, "ref": "main"}
    pr = {"number": 144, "state": "open", "head": head, "base": base,
          "updated_at": T}
    run = {"id": RUN, "workflow_id": 331621618,
           "path": ".github/workflows/ci.yml", "event": "pull_request",
           "head_sha": HEAD, "check_suite_id": SUITE, "run_attempt": 1,
           "created_at": "2026-09-19T05:48:24Z",
           "run_started_at": "2026-09-19T05:48:24Z",
           "status": "completed", "conclusion": "success",
           "pull_requests": [{"number": 144, "head": head, "base": base}]}
    checks = []
    jobs = []
    for context, check_id in zip(CONTEXTS, CHECKS):
        check = {"id": check_id, "name": context, "head_sha": HEAD,
                 "check_suite": {"id": SUITE},
                 "app": {"id": 15368, "slug": "github-actions"},
                 "status": "completed", "conclusion": "success",
                 "started_at": "2026-09-19T05:48:26Z",
                 "completed_at": "2026-09-19T05:49:36Z"}
        job = {key: check[key] for key in
               ("id", "name", "head_sha", "status", "conclusion",
                "started_at", "completed_at")}
        job.update(run_id=RUN, run_attempt=1,
                   check_run_url=f"https://api.github.com/{PREFIX}/check-runs/{check_id}")
        checks.append(check)
        jobs.append(job)
    if name == "retarget_before_fresh_run":
        run.update(created_at="2026-09-19T05:51:00Z",
                   run_started_at="2026-09-19T05:51:00Z")
        for obj in jobs + checks:
            obj.update(started_at="2026-09-19T05:51:02Z",
                       completed_at="2026-09-19T05:52:00Z")
    retarget = {"id": 90000000001, "event": "base_ref_changed",
                "created_at": T, "commit_id": None, "commit_url": None}
    routes = {
        PREFIX + "/pulls/144": pr,
        TIMELINE: [retarget],
        PREFIX + "/actions/workflows/ci.yml":
            {"id": 331621618, "path": ".github/workflows/ci.yml"},
        RUN_LIST: {"total_count": 1, "workflow_runs": [run]},
        f"{PREFIX}/actions/runs/{RUN}": run,
        f"{PREFIX}/actions/runs/{RUN}/attempts/1/jobs?per_page=100":
            {"total_count": 3, "jobs": jobs},
    }
    for check in checks:
        routes[f"{PREFIX}/check-runs/{check['id']}"] = check
    return {"routes": routes, "headers": {}, "responses": {}, "errors": {},
            "event": {"action": "edited", "number": 144,
                      "repository": repo, "pull_request": pr,
                      "changes": {"body": {"from": "synthetic fixture"}}}}


SHIM = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["FIXTURE_DIR"])
args = sys.argv[1:]
with (root / "calls").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
data = json.loads((root / "fixture.json").read_text())
# Only this exact unchanged guard request may use gh's default GET.
if args == ["api", "repos/{owner}/{repo}/pulls/144", "--jq",
            "[.user.login, .user.type] | @tsv"]:
    print("dependabot[bot]\tBot")
    sys.exit(0)
if (len(args) != 7 or args[:6] !=
        ["api", "--method", "GET", "--include", "-H",
         "Accept: application/vnd.github+json"]):
    sys.exit("DENIED: non-GET or unexpected API options")
endpoint = args[6]
if endpoint not in data["routes"]:
    sys.exit("DENIED: unknown endpoint " + endpoint)
counts_path = root / "counts"
counts = json.loads(counts_path.read_text()) if counts_path.exists() else {}
index = counts.get(endpoint, 0)
counts[endpoint] = index + 1
counts_path.write_text(json.dumps(counts))
if endpoint in data["errors"]:
    sys.exit(data["errors"][endpoint])
body = data["routes"][endpoint]
responses = data["responses"].get(endpoint)
if responses is not None:
    body = responses[min(index, len(responses) - 1)]
print("HTTP/2.0 200 OK")
print("Content-Type: application/json")
for key, value in data["headers"].get(endpoint, {}).items():
    print(key + ": " + value)
print()
print(json.dumps(body))
'''


def execute(data, ledger=False, env_changes=None):
    with tempfile.TemporaryDirectory(prefix="retarget-test-") as directory:
        root = Path(directory)
        (root / "fixture.json").write_text(json.dumps(data))
        (root / "event.json").write_text(json.dumps(data["event"]))
        shim = root / "gh"
        shim.write_text(SHIM)
        shim.chmod(0o755)
        # Any accidental actuator/network helper/sleep fails immediately.
        for name in ("curl", "wget", "sleep"):
            denied = root / name
            denied.write_text("#!/bin/sh\nprintf 'DENIED: external command\\n' >&2\nexit 64\n")
            denied.chmod(0o755)
        env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                   FIXTURE_DIR=str(root), GH_TOKEN="offline-fixture",
                   GH_HOST="github.com", GH_REPO=REPO, PR_NUMBER="144",
                   PR_HEAD_SHA=HEAD, GITHUB_SHA="f" * 40,
                   GITHUB_EVENT_NAME="pull_request",
                   GITHUB_EVENT_PATH=str(root / "event.json"),
                   GITHUB_API_URL="https://api.github.com",
                   RITUAL_API_RETRY_DELAY="0")
        env.update(env_changes or {})
        commands = [("bash .github/scripts/check-retarget-freshness.sh", {})]
        if ledger:
            workflow = yaml.load(
                (ROOT / ".github/workflows/task-ritual.yml").read_text(),
                Loader=yaml.BaseLoader)
            commands = [(step["run"], step.get("env", {}))
                        for step in workflow["jobs"]["task-ritual"]["steps"]
                        if "run" in step]
        expressions = {
            "${{ github.token }}": "offline-fixture",
            "${{ github.repository }}": REPO,
            "${{ github.event.pull_request.number }}": "144",
            "${{ github.event.pull_request.head.sha }}": HEAD,
        }
        output = ""
        for command, step_env in commands:
            current = dict(env)
            for key, value in step_env.items():
                current[key] = expressions[value]
            result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", command],
                                    cwd=ROOT, env=current, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=20)
            output += result.stdout
            if result.returncode:
                break
        calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()
                 ] if (root / "calls").exists() else []
        return subprocess.CompletedProcess([], result.returncode, output), calls


class Freshness(unittest.TestCase):
    def check(self, data, code=0, reason="FRESH", **kwargs):
        result, calls = execute(data, **kwargs)
        self.assertEqual(result.returncode, code, result.stdout)
        self.assertIn(reason, result.stdout)
        self.assertNotIn("DENIED", result.stdout)
        if code:
            for field in ("PR=144", "head=" + HEAD, "retarget=", "context=",
                          "run=", "attempt=", "reason="):
                self.assertIn(field, result.stdout)
        return result, calls

    def fresh(self):
        return fixture("retarget_before_fresh_run")

    def run_record(self, data):
        return data["routes"][f"{PREFIX}/actions/runs/{RUN}"]

    def jobs(self, data, attempt=1):
        return data["routes"][
            f"{PREFIX}/actions/runs/{RUN}/attempts/{attempt}/jobs?per_page=100"]["jobs"]

    def attempt(self, data, number):
        self.run_record(data)["run_attempt"] = number
        route = f"{PREFIX}/actions/runs/{RUN}/attempts/"
        value = data["routes"].pop(route + "1/jobs?per_page=100")
        for job in value["jobs"]:
            job["run_attempt"] = number
        data["routes"][route + str(number) + "/jobs?per_page=100"] = value

    def test_stale_retarget_fails_ledger(self):
        result, calls = execute(fixture("retarget_after_success"), ledger=True)
        self.assertIn("PASS: PR #144 is authored by allowlisted bot", result.stdout)
        self.assertTrue(calls)
        self.assertEqual(
            result.returncode, 1,
            "retarget_after_success: shipped ledger returned "
            f"{result.returncode}; expected exit 1 for stale successful code\n{result.stdout}")

    def test_no_retarget_independent_of_failed_or_missing_code(self):
        for code_state in ("missing", "failure", "in_progress"):
            with self.subTest(code_state=code_state):
                data = self.fresh()
                data["routes"][TIMELINE] = [{"event": "committed"},
                                           {"event": "cross-referenced"}]
                self.run_record(data)["conclusion"] = code_state
                result, calls = self.check(data, reason="NO_RETARGET")
                self.assertIn("code verification remains independently required", result.stdout)
                self.assertEqual(len(calls), 4)
                self.assertFalse(any("/actions/" in call[-1] for call in calls))

    def test_all_contexts_fresh_and_ritual_exemption_does_not_skip_sensor(self):
        self.check(self.fresh(), ledger=True)

    def test_multiple_retargets_timestamp_order_and_return_to_original(self):
        data = self.fresh()
        newest = copy.deepcopy(data["routes"][TIMELINE][0])
        older = dict(newest, id=90000000009, created_at="2026-09-19T05:40:00Z")
        same_second = dict(newest, id=90000000002)
        data["routes"][TIMELINE] = [newest, older, same_second]
        self.check(data)
        data["routes"][TIMELINE].append(
            dict(newest, id=90000000010, created_at="2026-09-19T05:53:00Z"))
        self.check(data, 1, "stale")

    def test_full_rerun_fresh_original_passes(self):
        data = self.fresh()
        self.attempt(data, 2)
        self.run_record(data)["run_started_at"] = "2026-09-19T05:51:01Z"
        self.check(data)

    def test_base_advancement_does_not_require_current_base_sha(self):
        data = self.fresh()
        data["routes"][PREFIX + "/pulls/144"] = copy.deepcopy(
            data["routes"][PREFIX + "/pulls/144"])
        data["routes"][PREFIX + "/pulls/144"]["base"]["sha"] = "c" * 40
        self.check(data)

    def test_old_different_base_can_be_superseded(self):
        data = self.fresh()
        old = copy.deepcopy(self.run_record(data))
        old.update(id=RUN - 1, created_at="2026-09-19T05:40:00Z",
                   run_started_at="2026-09-19T05:40:00Z")
        old["pull_requests"][0]["base"]["ref"] = "old-base"
        data["routes"][RUN_LIST]["workflow_runs"].append(old)
        data["routes"][RUN_LIST]["total_count"] = 2
        self.check(data)

    def test_optional_failure_is_not_a_required_context(self):
        data = self.fresh()
        self.run_record(data)["conclusion"] = "failure"
        job = dict(self.jobs(data)[0], id=7, name="windows-launcher", conclusion="failure")
        self.jobs(data).append(job)
        data["routes"][f"{PREFIX}/actions/runs/{RUN}/attempts/1/jobs?per_page=100"
                       ]["total_count"] = 4
        self.check(data)

    def test_one_or_all_stale_contexts(self):
        for count in (1, 3):
            with self.subTest(count=count):
                data = self.fresh()
                for job in self.jobs(data)[:count]:
                    check = data["routes"][f"{PREFIX}/check-runs/{job['id']}"]
                    for value in (job, check):
                        value.update(started_at=T, completed_at=T)
                self.check(data, 1, "stale")

    def test_before_boundary_original_finishes_later_or_reruns(self):
        for rerun in (False, True):
            with self.subTest(rerun=rerun):
                data = self.fresh()
                self.run_record(data)["created_at"] = "2026-09-19T05:49:00Z"
                if rerun:
                    self.attempt(data, 2)
                self.check(data, 1, "stale original")

    def test_original_at_boundary_is_not_strictly_later(self):
        data = self.fresh()
        self.run_record(data)["created_at"] = T
        self.check(data, 1, "stale original")

    def test_latest_original_timestamp_tie_is_ambiguous(self):
        data = self.fresh()
        data["routes"][RUN_LIST]["workflow_runs"].append(
            dict(self.run_record(data), id=RUN + 1))
        data["routes"][RUN_LIST]["total_count"] = 2
        self.check(data, 2, "ambiguous")

    def test_newer_failed_run_cannot_fall_back_to_older_success(self):
        data = self.fresh()
        older = copy.deepcopy(self.run_record(data))
        older.update(id=RUN - 1, created_at="2026-09-19T05:50:30Z",
                     run_started_at="2026-09-19T05:50:30Z")
        data["routes"][RUN_LIST]["workflow_runs"].append(older)
        data["routes"][RUN_LIST]["total_count"] = 2
        self.jobs(data)[0]["conclusion"] = "failure"
        data["routes"][f"{PREFIX}/check-runs/{CHECKS[0]}"]["conclusion"] = "failure"
        self.check(data, 1, "non-success")

    def test_required_context_non_success_matrix(self):
        for state in ("failure", "cancelled", "skipped", "neutral", "timed_out",
                      "action_required", "stale", "startup_failure", "queued", "in_progress"):
            with self.subTest(state=state):
                data = self.fresh()
                for value in (self.jobs(data)[0],
                              data["routes"][f"{PREFIX}/check-runs/{CHECKS[0]}"]):
                    value.update(status=state if state in ("queued", "in_progress")
                                 else "completed",
                                 conclusion=None if state in ("queued", "in_progress") else state)
                    if state in ("queued", "in_progress"):
                        value["completed_at"] = None
                    if state == "queued":
                        value["started_at"] = None
                self.check(data, 1, "non-success")

    def test_missing_duplicate_or_partial_attempt_contexts(self):
        for mode in ("missing", "duplicate", "partial"):
            with self.subTest(mode=mode):
                data = self.fresh()
                if mode == "partial":
                    self.attempt(data, 2)
                jobs = self.jobs(data, 2 if mode == "partial" else 1)
                if mode == "duplicate":
                    jobs.append(dict(jobs[0], id=999))
                else:
                    jobs.pop()
                number = 2 if mode == "partial" else 1
                data["routes"][f"{PREFIX}/actions/runs/{RUN}/attempts/{number}/jobs?per_page=100"
                               ]["total_count"] = len(jobs)
                self.check(data, 1, "required context")

    def test_unrelated_head_pr_workflow_and_push_do_not_substitute(self):
        for mode in ("head", "pr", "workflow", "ledger", "push"):
            with self.subTest(mode=mode):
                data = self.fresh()
                run = self.run_record(data)
                if mode == "head":
                    run["head_sha"] = "f" * 40
                elif mode == "pr":
                    run["pull_requests"][0]["number"] = 99
                elif mode in ("workflow", "ledger"):
                    run.update(workflow_id=55, path=".github/workflows/task-ritual.yml"
                               if mode == "ledger" else ".github/workflows/other.yml")
                else:
                    run["event"] = "push"
                self.check(data, 1, "missing attributable")

    def test_selected_base_ref_and_repo_mismatch(self):
        for field, value in (("ref", "other"), ("repo", {"id": 77})):
            with self.subTest(field=field):
                data = self.fresh()
                run = self.run_record(data)
                run["pull_requests"] = copy.deepcopy(run["pull_requests"])
                run["pull_requests"][0]["base"][field] = value
                self.check(data, 1, "base mismatch")

    def test_empty_malformed_duplicate_or_wrong_head_association(self):
        for mode in ("empty", "malformed", "duplicate", "head", "repo", "base-sha"):
            with self.subTest(mode=mode):
                data = self.fresh()
                run = self.run_record(data)
                association = copy.deepcopy(run["pull_requests"][0])
                run["pull_requests"] = [association]
                if mode == "empty":
                    run["pull_requests"] = []
                elif mode == "malformed":
                    run["pull_requests"] = {}
                elif mode == "duplicate":
                    run["pull_requests"].append(copy.deepcopy(association))
                elif mode == "head":
                    association["head"]["sha"] = "f" * 40
                elif mode == "repo":
                    association["head"]["repo"]["id"] = 99
                else:
                    association["base"]["sha"] = ""
                self.check(data, 2, "identity")

    def test_workflow_descriptor_and_run_identity(self):
        for field, value in (("workflow_id", 2), ("path", "ci.yml"),
                             ("check_suite_id", 0), ("run_attempt", 0)):
            with self.subTest(field=field):
                data = self.fresh()
                self.run_record(data)[field] = value
                self.check(data, 2, "identity")
        data = self.fresh()
        data["routes"][PREFIX + "/actions/workflows/ci.yml"]["path"] = "ci.yml"
        self.check(data, 2, "identity")

    def test_job_check_binding_matrix(self):
        mutations = (
            ("job", "run_id", 1), ("job", "run_attempt", 2),
            ("job", "head_sha", "f" * 40),
            ("job", "check_run_url", "https://evil.invalid/check-runs/1"),
            ("job", "check_run_url", f"https://api.github.com/repos/other/repo/check-runs/1"),
            ("job", "check_run_url", f"https://api.github.com/{PREFIX}/check-runs/0"),
            ("check", "id", 1), ("check", "name", "windows-launcher"),
            ("check", "head_sha", "f" * 40),
            ("check", "check_suite", {"id": 2}),
            ("check", "app", {"id": 999, "slug": "github-actions"}),
            ("check", "app", {"id": 15368, "slug": "third-party"}),
            ("check", "conclusion", "failure"),
            ("check", "started_at", "2026-09-19T05:51:03Z"),
        )
        for kind, field, value in mutations:
            with self.subTest(kind=kind, field=field, value=value):
                data = self.fresh()
                target = self.jobs(data)[0] if kind == "job" else data["routes"][
                    f"{PREFIX}/check-runs/{CHECKS[0]}"]
                target[field] = value
                self.check(data, 2, "identity")

    def test_timestamp_schema_and_chronology(self):
        for stamp in ("not-a-time", "2026-02-30T00:00:00Z",
                      "2026-09-19T05:50:00+09:00", None):
            with self.subTest(stamp=stamp):
                data = self.fresh()
                data["routes"][TIMELINE][0]["created_at"] = stamp
                self.check(data, 2, "timestamp")
        for field, value in (("created_at", "bad"),
                             ("run_started_at", "2026-09-19T05:50:59Z"),
                             ("run_started_at", "2026-09-19T05:51:03Z")):
            with self.subTest(field=field, value=value):
                data = self.fresh()
                self.run_record(data)[field] = value
                self.check(data, 2, "timestamp")
        data = self.fresh()
        for obj in (self.jobs(data)[0], data["routes"][f"{PREFIX}/check-runs/{CHECKS[0]}"]):
            obj["completed_at"] = "2026-09-19T05:51:01Z"
        self.check(data, 2, "timestamp")

    def test_malformed_json_shapes_and_http_auth_failures(self):
        for endpoint in (PREFIX + "/pulls/144", TIMELINE, RUN_LIST,
                         f"{PREFIX}/check-runs/{CHECKS[0]}"):
            with self.subTest(endpoint=endpoint):
                data = self.fresh()
                data["routes"][endpoint] = None
                self.check(data, 2, "schema")
                for error in ("HTTP 401: authentication", "HTTP 403: permission",
                              "HTTP 500: unavailable"):
                    data = self.fresh()
                    data["errors"][endpoint] = error
                    self.check(data, 2, "API")
        for event_id in (None, 0, -1, True, "123"):
            with self.subTest(event_id=event_id):
                data = self.fresh()
                data["routes"][TIMELINE][0]["id"] = event_id
                self.check(data, 2, "identity")

    def pages(self, data, endpoint, key=None):
        value = data["routes"][endpoint]
        items = value if key is None else value[key]
        cut = 0 if key is None else 1
        first, second = items[:cut], items[cut:]
        data["routes"][endpoint] = first if key is None else dict(value, **{key: first})
        next_endpoint = endpoint + "&page=2"
        data["routes"][next_endpoint] = second if key is None else dict(value, **{key: second})
        url = "https://api.github.com/" + next_endpoint.replace(
            PREFIX, "repositories/1330507890", 1)
        data["headers"][endpoint] = {"Link": f'<{url}>; rel="next", <{url}>; rel="last"'}
        return next_endpoint

    def test_complete_multipage_timeline_runs_and_jobs(self):
        data = self.fresh()
        data["routes"][TIMELINE].insert(0, {"event": "committed"})
        self.pages(data, TIMELINE)
        self.pages(data, RUN_LIST, "workflow_runs")
        self.pages(data, f"{PREFIX}/actions/runs/{RUN}/attempts/1/jobs?per_page=100", "jobs")
        self.check(data)

    def test_truncated_second_page_bad_links_counts_duplicates_and_cap(self):
        for mode in ("page2-error", "count", "cap", "duplicate", "external-link",
                     "wrong-resource", "wrong-page", "missing-next", "count-drift"):
            with self.subTest(mode=mode):
                data = self.fresh()
                if mode == "page2-error":
                    second = self.pages(data, TIMELINE)
                    data["errors"][second] = "HTTP 503"
                elif mode == "count":
                    data["routes"][RUN_LIST]["total_count"] = 2
                elif mode == "cap":
                    data["routes"][RUN_LIST]["total_count"] = 1000
                elif mode == "duplicate":
                    data["routes"][RUN_LIST]["workflow_runs"] *= 2
                    data["routes"][RUN_LIST]["total_count"] = 2
                elif mode == "count-drift":
                    second = self.pages(data, RUN_LIST, "workflow_runs")
                    data["routes"][second]["total_count"] = 2
                else:
                    self.pages(data, TIMELINE)
                    link = data["headers"][TIMELINE]["Link"]
                    if mode == "external-link":
                        link = link.replace("api.github.com", "evil.invalid")
                    elif mode == "wrong-resource":
                        link = link.replace("/issues/144/", "/issues/999/")
                    elif mode == "wrong-page":
                        link = link.replace("page=2", "page=3")
                    else:
                        link = link.split(", ")[1]
                    data["headers"][TIMELINE]["Link"] = link
                self.check(data, 2, "API" if mode == "page2-error" else "pagination")

    def test_changing_snapshot_fails_not_success(self):
        for mode in ("head", "base", "retarget", "run-list", "run", "attempt", "check", "jobs"):
            with self.subTest(mode=mode):
                data = self.fresh()
                endpoint = {
                    "head": PREFIX + "/pulls/144", "base": PREFIX + "/pulls/144",
                    "retarget": TIMELINE, "run-list": RUN_LIST,
                    "run": f"{PREFIX}/actions/runs/{RUN}",
                    "attempt": f"{PREFIX}/actions/runs/{RUN}",
                    "check": f"{PREFIX}/check-runs/{CHECKS[0]}",
                    "jobs": f"{PREFIX}/actions/runs/{RUN}/attempts/1/jobs?per_page=100",
                }[mode]
                original = copy.deepcopy(data["routes"][endpoint])
                changed = copy.deepcopy(original)
                if mode == "head":
                    changed["head"]["sha"] = "d" * 40
                elif mode == "base":
                    changed["base"]["ref"] = "other"
                elif mode == "retarget":
                    changed.append(dict(changed[0], id=90000000011))
                elif mode == "run-list":
                    changed["workflow_runs"][0]["run_attempt"] = 2
                elif mode == "attempt":
                    changed["run_attempt"] = 2
                elif mode == "jobs":
                    changed["jobs"][0]["conclusion"] = "failure"
                else:
                    changed["conclusion"] = "failure"
                data["responses"][endpoint] = [original, changed]
                self.check(data, 1, "unstable")

    def test_no_retarget_snapshot_must_also_be_stable(self):
        data = self.fresh()
        retarget = data["routes"][TIMELINE]
        data["routes"][TIMELINE] = []
        data["responses"][TIMELINE] = [[], retarget]
        self.check(data, 1, "unstable")

    def test_edited_base_webhook_is_only_negative_consistency_veto(self):
        for visible in ("absent", "older", "current"):
            with self.subTest(visible=visible):
                data = self.fresh()
                data["event"]["changes"] = {"base": {"ref": {"from": "old-base"}}}
                if visible == "absent":
                    data["routes"][TIMELINE] = []
                elif visible == "older":
                    data["routes"][TIMELINE][0]["created_at"] = "2026-09-19T05:49:00Z"
                self.check(data, 0 if visible == "current" else 1,
                           "FRESH" if visible == "current" else "not yet visible")

    def test_event_identity_and_supported_host(self):
        for mode in ("action", "head", "number", "repository", "changes"):
            with self.subTest(mode=mode):
                data = self.fresh()
                data["event"] = copy.deepcopy(data["event"])
                if mode == "action":
                    data["event"]["action"] = "closed"
                elif mode == "head":
                    data["event"]["pull_request"]["head"]["sha"] = "f" * 40
                elif mode == "number":
                    data["event"]["number"] = 3
                elif mode == "repository":
                    data["event"]["repository"]["id"] = 3
                else:
                    data["event"]["changes"] = {"base": "bad"}
                self.check(data, 2, "identity")
        self.check(self.fresh(), 2, "issuer", env_changes={"GH_HOST": "example.invalid"})


unittest.main(verbosity=2)
PY
