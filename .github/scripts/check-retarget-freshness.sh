#!/usr/bin/env bash
# Read-only, bounded GitHub.com retarget freshness observation; never schedules CI.
set -euo pipefail
for dependency in python3 gh; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf 'UNCHECKABLE PR=%s head=%s retarget=? context=? run=? attempt=? reason=missing dependency %s\n' \
      "${PR_NUMBER:-?}" "${PR_HEAD_SHA:-?}" "$dependency" >&2
    exit 2
  }
done

exec python3 - <<'PY'
from datetime import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import parse_qs, urlencode, urlsplit

CONTEXTS = ("quality", "scaffold-self-check", "copilot-surface")
WORKFLOW = ".github/workflows/ci.yml"
PR = os.environ.get("PR_NUMBER", "?")
HEAD = os.environ.get("PR_HEAD_SHA", "?")
REPO = os.environ.get("GH_REPO", "")
PREFIX = "repos/" + REPO
diagnostic = {"retarget": "?", "context": "-", "run": "-", "attempt": "-"}


class Fault(Exception):
    def __init__(self, code, reason):
        super().__init__(reason)
        self.code = code


def need(condition, reason, code=2):
    if not condition:
        raise Fault(code, reason)


def obj(value, label):
    need(isinstance(value, dict), "schema: expected object for " + label)
    return value


def array(value, label):
    need(isinstance(value, list), "schema: expected array for " + label)
    return value


def ident(value, label):
    need(type(value) is int and value > 0, "identity: invalid " + label)
    return value


def text(value, label):
    need(isinstance(value, str) and value.strip() == value and value
         and not any(ord(c) < 32 or ord(c) == 127 for c in value),
         "identity: invalid " + label)
    return value


def sha(value, label):
    need(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value),
         "identity: invalid " + label)
    return value


def stamp(value):
    need(isinstance(value, str) and re.fullmatch(
        r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|\+00:00)", value),
        "timestamp: expected valid UTC timestamp")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise Fault(2, "timestamp: invalid calendar value") from error


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, "schema: duplicate JSON key")
        result[key] = value
    return result


def bad_constant(_value):
    raise Fault(2, "schema: non-finite JSON number")


def decode(value):
    try:
        return json.loads(value, object_pairs_hook=unique_object, parse_constant=bad_constant)
    except (ValueError, UnicodeError) as error:
        raise Fault(2, "schema: malformed JSON") from error


def get(endpoint):
    try:
        result = subprocess.run(
            ["gh", "api", "--method", "GET", "--include", "-H",
             "Accept: application/vnd.github+json", endpoint],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    except (OSError, subprocess.TimeoutExpired, UnicodeError) as error:
        raise Fault(2, "API: read unavailable or timed out for " + endpoint) from error
    need(result.returncode == 0,
         "API: GET failed (HTTP/auth/permission); cannot verify " + endpoint)
    header, separator, body = result.stdout.replace("\r\n", "\n").partition("\n\n")
    lines = header.splitlines()
    need(separator and lines and re.fullmatch(r"HTTP/\S+ 200(?: .*)?", lines[0]),
         "API: invalid HTTP response for " + endpoint)
    headers = {}
    for line in lines[1:]:
        key, colon, value = line.partition(":")
        key = key.lower()
        need(colon and key not in headers, "API: malformed or duplicate response header")
        headers[key] = value.strip()
    need(headers.get("content-type", "").split(";")[0] == "application/json",
         "API: response is not JSON")
    return decode(body), headers


def page_links(header, endpoint, page, repo_id):
    links = {}
    source = urlsplit(endpoint)
    expected_query = parse_qs(source.query, strict_parsing=True)
    if not header:
        return links
    for part in header.split(","):
        match = re.fullmatch(r'\s*<([^>]+)>;\s*rel="(next|last|first|prev)"\s*', part)
        need(match, "pagination: malformed Link header")
        url, relation = match.groups()
        need(relation not in links, "pagination: duplicate Link relation")
        try:
            parsed = urlsplit(url)
        except ValueError as error:
            raise Fault(2, "pagination: malformed Link URL") from error
        allowed = ("/" + source.path,
                   "/" + source.path.replace(PREFIX, f"repositories/{repo_id}", 1))
        need(parsed.scheme == "https" and parsed.netloc == "api.github.com"
             and not parsed.fragment and parsed.path in allowed,
             "pagination: foreign host or wrong resource Link")
        try:
            query = parse_qs(parsed.query, strict_parsing=True)
        except ValueError as error:
            raise Fault(2, "pagination: malformed Link query") from error
        number = query.pop("page", [])
        need(len(number) == 1 and re.fullmatch(r"[1-9][0-9]*", number[0])
             and query == expected_query, "pagination: wrong Link query")
        number = int(number[0])
        need((relation == "next" and number == page + 1)
             or (relation == "prev" and page > 1 and number == page - 1)
             or (relation == "first" and number == 1)
             or (relation == "last" and number >= page),
             "pagination: inconsistent page sequence")
        links[relation] = number
    return links


def listing(endpoint, repo_id, key=None):
    records, ids = [], set()
    total = last = None
    for page in range(1, 1001):
        target = endpoint if page == 1 else endpoint + "&page=" + str(page)
        data, headers = get(target)
        if key:
            data = obj(data, endpoint)
            count = data.get("total_count")
            need(type(count) is int and count >= 0, "pagination: invalid total_count")
            need(key != "workflow_runs" or count < 1000, "pagination: Actions cap reached")
            need(total is None or count == total, "pagination: total_count changed")
            total = count
            data = data.get(key)
        items = array(data, endpoint)
        need(len(items) <= 100, "pagination: oversized page")
        for item in items:
            obj(item, "page record")
            # Non-retarget timeline kinds need not carry a numeric event ID.
            value = item.get("id")
            if key:
                ident(value, key + " record")
            if type(value) is int:
                need(value not in ids, "pagination: duplicate record ID")
                ids.add(value)
            records.append(item)
        links = page_links(headers.get("link"), endpoint, page, repo_id)
        if "last" in links:
            need(last is None or last == links["last"], "pagination: last page changed")
            last = links["last"]
        if "next" not in links:
            need(last is None or last == page, "pagination: missing next page")
            need(total is None or len(records) == total, "pagination: count mismatch")
            return records
        need(last is not None and page < last, "pagination: missing terminal boundary")
        need(total is None or len(records) < total, "pagination: continuation past count")
    raise Fault(2, "pagination: bounded page limit reached; history uncheckable")


def repository(value):
    return ident(obj(value, "repository").get("id"), "repository ID")


def pr_identity(value):
    value = obj(value, "PR")
    head = obj(value.get("head"), "PR head")
    base = obj(value.get("base"), "PR base")
    base_repo = obj(base.get("repo"), "base repository")
    need(text(base_repo.get("full_name"), "base repository name").lower() == REPO.lower(),
         "identity: PR base repository name differs")
    sha(base.get("sha"), "current base SHA")
    return (ident(value.get("number"), "PR number"), sha(head.get("sha"), "PR head SHA"),
            repository(head.get("repo")), repository(base_repo), text(base.get("ref"), "base ref"))


def history(repo_id):
    events = listing(f"{PREFIX}/issues/{PR}/timeline?per_page=100", repo_id)
    retargets = []
    for event in events:
        need(isinstance(event.get("event"), str), "schema: missing timeline event kind")
        if event["event"] == "base_ref_changed":
            retargets.append((ident(event.get("id"), "retarget ID"), stamp(event.get("created_at"))))
    return tuple(sorted(retargets))


def trigger(identity):
    need(os.environ.get("GITHUB_EVENT_NAME") == "pull_request", "identity: unsupported trigger")
    try:
        event = obj(decode(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()), "event")
    except (KeyError, OSError, UnicodeError) as error:
        raise Fault(2, "identity: event payload unavailable") from error
    need(event.get("action") in ("opened", "synchronize", "reopened", "edited"),
         "identity: unexpected PR action")
    need(event.get("number") == int(PR) and pr_identity(event.get("pull_request")) == identity
         and repository(event.get("repository")) == identity[3],
         "identity: event and current PR disagree")
    changes = obj(event.get("changes", {}), "event changes")
    if event["action"] == "edited" and "base" in changes:
        base = changes["base"]
        need(isinstance(base, dict) and base
             and all(key in ("ref", "sha") and isinstance(value, dict)
                     and isinstance(value.get("from"), str) and value["from"]
                     for key, value in base.items()), "identity: malformed changes.base")
        return stamp(event["pull_request"].get("updated_at"))
    return None


RUN_FIELDS = ("id", "workflow_id", "path", "event", "head_sha", "check_suite_id",
              "run_attempt", "created_at", "run_started_at", "status", "conclusion", "pull_requests")
JOB_FIELDS = ("id", "name", "head_sha", "run_id", "run_attempt", "check_run_url",
              "status", "conclusion", "started_at", "completed_at")
CHECK_FIELDS = ("id", "name", "head_sha", "check_suite", "app",
                "status", "conclusion", "started_at", "completed_at")


def project(value, fields):
    value = obj(value, "evidence")
    return {key: value.get(key) for key in fields}


def descriptor():
    value = obj(get(PREFIX + "/actions/workflows/ci.yml")[0], "workflow")
    need(value.get("path") == WORKFLOW, "identity: ci.yml descriptor path differs")
    return ident(value.get("id"), "workflow ID")


def candidates(runs, workflow_id, identity):
    result = []
    for run in runs:
        if sha(run.get("head_sha"), "run head") != HEAD:
            continue
        same_id = ident(run.get("workflow_id"), "run workflow") == workflow_id
        same_path = text(run.get("path"), "run path") == WORKFLOW
        need(same_id == same_path, "identity: workflow ID/path disagreement")
        if not same_id or text(run.get("event"), "run event") != "pull_request":
            continue
        diagnostic.update(run=run["id"], attempt=run.get("run_attempt", "?"))
        association = array(run.get("pull_requests"), "run PR association identity")
        need(association, "identity: empty PR association")
        matches = []
        for entry in association:
            entry = obj(entry, "PR association")
            number = ident(entry.get("number"), "associated PR number")
            head = obj(entry.get("head"), "associated head")
            base = obj(entry.get("base"), "associated base")
            head_sha = sha(head.get("sha"), "associated head SHA")
            head_repo = repository(head.get("repo"))
            base_repo = repository(base.get("repo"))
            base_ref = text(base.get("ref"), "associated base ref")
            sha(base.get("sha"), "associated base SHA")
            if number == int(PR):
                need(head_sha == HEAD and head_repo == identity[2],
                     "identity: associated PR head/repository mismatch")
                matches.append((base_repo, base_ref))
        if not matches:
            continue
        need(len(matches) == 1, "identity: ambiguous PR association")
        ident(run.get("check_suite_id"), "check suite")
        ident(run.get("run_attempt"), "current attempt")
        result.append((stamp(run.get("created_at")), run, matches[0]))
    need(result, "missing attributable current-head code run", 1)
    latest = max(item[0] for item in result)
    selected = [item for item in result if item[0] == latest]
    need(len(selected) == 1, "identity: ambiguous latest original creation timestamp")
    return selected[0]


def required_jobs(jobs):
    selected = {}
    for context in CONTEXTS:
        diagnostic["context"] = context
        matching = [job for job in jobs if job.get("name") == context]
        need(len(matching) == 1, "missing or duplicate required context in current attempt", 1)
        selected[context] = matching[0]
    return selected


def checks_for(jobs, run, created, started, boundary):
    checks = {}
    for context, job in jobs.items():
        diagnostic["context"] = context
        need(ident(job.get("run_id"), "job run ID") == run["id"]
             and ident(job.get("run_attempt"), "job attempt") == run["run_attempt"]
             and job.get("head_sha") == HEAD, "identity: job run/attempt/head mismatch")
        url = job.get("check_run_url")
        match = re.fullmatch(
            r"https://api\.github\.com/" + re.escape(PREFIX) + r"/check-runs/([1-9][0-9]*)",
            url if isinstance(url, str) else "")
        need(match, "identity: check_run_url is not a local direct check ID")
        check_id = int(match.group(1))
        check = obj(get(f"{PREFIX}/check-runs/{check_id}")[0], "check run")
        need(ident(check.get("id"), "check ID") == check_id
             and check.get("name") == context and check.get("head_sha") == HEAD
             and ident(obj(check.get("check_suite"), "check suite").get("id"), "suite ID")
             == run["check_suite_id"]
             and ident(obj(check.get("app"), "check App").get("id"), "App ID") == 15368
             and check["app"].get("slug") == "github-actions",
             "identity: check name/head/suite/issuer mismatch")
        for field in ("status", "conclusion", "started_at", "completed_at"):
            need(job.get(field) == check.get(field), "identity: job/check " + field + " mismatch")
        need(check.get("status") in ("queued", "in_progress", "completed", "pending", "waiting", "requested")
             and check.get("conclusion") in (None, "success", "failure", "cancelled", "skipped",
                                             "neutral", "timed_out", "action_required", "stale",
                                             "startup_failure"), "schema: invalid check status/conclusion")
        need(check.get("status") == "completed" and check.get("conclusion") == "success",
             "non-success required context (incomplete/failed checks cannot qualify)", 1)
        check_start = stamp(check.get("started_at"))
        check_end = stamp(check.get("completed_at"))
        need(check_start > boundary and check_end > boundary, "stale required context", 1)
        need(created <= started <= check_start <= check_end, "timestamp: check chronology invalid")
        checks[context] = (check_id, project(check, CHECK_FIELDS))
    return checks


def stable(condition):
    need(condition, "unstable snapshot; evidence changed during reads", 1)


def main():
    need(re.fullmatch(r"[1-9][0-9]*", PR), "identity: invalid PR_NUMBER")
    sha(HEAD, "PR_HEAD_SHA")
    need(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", REPO)
         and REPO.split("/")[-1] not in (".", ".."), "identity: invalid GH_REPO")
    need(os.environ.get("GH_HOST", "github.com") == "github.com"
         and os.environ.get("GITHUB_API_URL", "https://api.github.com") == "https://api.github.com",
         "issuer: unsupported host; separately reviewed adaptation required")
    identity = pr_identity(get(f"{PREFIX}/pulls/{PR}")[0])
    need(identity[0] == int(PR) and identity[1] == HEAD, "identity: current PR/head mismatch")
    veto_time = trigger(identity)
    repo_id = identity[3]
    retargets = history(repo_id)
    if retargets:
        boundary = max(value for _, value in retargets)
        diagnostic["retarget"] = ",".join(
            str(event_id) for event_id, value in retargets if value == boundary) + "@" + boundary.isoformat()
    else:
        boundary = None
        diagnostic["retarget"] = "none"
    need(veto_time is None or (boundary is not None and boundary >= veto_time),
         "edited base retarget not yet visible in timeline", 1)
    if boundary is None:
        stable(pr_identity(get(f"{PREFIX}/pulls/{PR}")[0]) == identity)
        stable(history(repo_id) == retargets)
        return "NO_RETARGET: code verification remains independently required"

    workflow_id = descriptor()
    run_endpoint = PREFIX + "/actions/runs?" + urlencode({"head_sha": HEAD, "per_page": 100})
    runs = listing(run_endpoint, repo_id, "workflow_runs")
    created, selected, associated_base = candidates(runs, workflow_id, identity)
    diagnostic.update(run=selected["id"], attempt=selected["run_attempt"])
    need(associated_base == identity[3:5], "selected run base mismatch", 1)
    need(created > boundary, "stale original run; obtain new-head-push or close/reopen code verification", 1)
    run_path = f"{PREFIX}/actions/runs/{selected['id']}"
    current = obj(get(run_path)[0], "selected run")
    need(ident(current.get("id"), "selected run ID") == selected["id"],
         "identity: selected run ID mismatch")
    stable(project(current, RUN_FIELDS) == project(selected, RUN_FIELDS))
    need(current.get("status") in ("queued", "in_progress", "completed", "pending", "waiting", "requested"),
         "schema: invalid run status")
    need(current.get("status") == "completed", "non-success run is incomplete", 1)
    started = stamp(selected.get("run_started_at"))
    need(started >= created, "timestamp: run starts before original creation")
    job_path = run_path + f"/attempts/{selected['run_attempt']}/jobs?per_page=100"
    jobs = required_jobs(listing(job_path, repo_id, "jobs"))
    checks = checks_for(jobs, selected, created, started, boundary)

    # Compare the observed evidence, not a success-filtered replacement snapshot.
    diagnostic["context"] = "-"
    stable(pr_identity(get(f"{PREFIX}/pulls/{PR}")[0]) == identity)
    stable(history(repo_id) == retargets)
    stable(descriptor() == workflow_id)
    reread = listing(run_endpoint, repo_id, "workflow_runs")
    stable(sorted((project(run, RUN_FIELDS) for run in reread), key=lambda run: run["id"])
           == sorted((project(run, RUN_FIELDS) for run in runs), key=lambda run: run["id"]))
    stable(project(get(run_path)[0], RUN_FIELDS) == project(current, RUN_FIELDS))
    again = required_jobs(listing(job_path, repo_id, "jobs"))
    stable({key: project(job, JOB_FIELDS) for key, job in again.items()}
           == {key: project(job, JOB_FIELDS) for key, job in jobs.items()})
    for context, (check_id, check) in checks.items():
        diagnostic["context"] = context
        stable(project(get(f"{PREFIX}/check-runs/{check_id}")[0], CHECK_FIELDS) == check)
    diagnostic["context"] = ",".join(CONTEXTS)
    return "FRESH: all required current-head contexts verified after retarget"


try:
    message = main()
    code = 0
except Fault as error:
    code = error.code
    message = ("STALE" if code == 1 else "UNCHECKABLE") + ": " + str(error)
print(f"PR={PR} head={HEAD} "
      + " ".join(f"{key}={value}" for key, value in diagnostic.items())
      + " reason=" + message, file=sys.stderr if code else sys.stdout)
sys.exit(code)
PY
