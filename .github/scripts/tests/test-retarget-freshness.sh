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
        calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
        return subprocess.CompletedProcess([], result.returncode, output), calls


class Freshness(unittest.TestCase):
    def test_stale_retarget_fails_ledger(self):
        result, calls = execute(fixture("retarget_after_success"), ledger=True)
        self.assertIn("PASS: PR #144 is authored by allowlisted bot", result.stdout)
        self.assertTrue(calls)
        self.assertEqual(
            result.returncode, 1,
            "retarget_after_success: shipped ledger returned "
            f"{result.returncode}; expected exit 1 for stale successful code\n{result.stdout}")


unittest.main(verbosity=2)
PY
