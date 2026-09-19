#!/usr/bin/env bash
# Local record rendering and read-only observation, never authorization.
set -euo pipefail

fail() { printf 'error: %s\n' "$2" >&2; exit "$1"; }
help_text() {
  cat <<'HELP'
Usage:
  task-ritual.sh render <claim|resume|plan|dispatch> --input <json-file|->
  task-ritual.sh preflight <claim|resume|plan|dispatch> --repo <owner/repo>
    --task <positive-number> --body-file <file|-> [--branch <known-branch>]
    [--pr <positive-number>]

JSON input schema (one object; unknown fields rejected):
  All kinds: task (positive integer).
  claim/resume: session (nonempty display name), branch (Git branch name).
  dispatch: session, session_id (8+ hexadecimal/hyphen characters), branch.
  plan: content (nonempty, human-supplied plan prose).
Identity fields must be single-line, without controls, commas, parentheses,
or ritual-marker injection. No identity, plan, worker or exemption is invented.
Outputs:
  render: only the canonical publishable body on stdout, no network.
  preflight: observed draft/ledger checks on stdout, diagnostics on stderr.
  Failures: stderr only, no publishable body.
Exit states: 0 scoped success; 1 rejected draft/ledger or unavailable read;
  2 usage, input schema, or missing dependency.
Requires Bash 3.2+, jq, git, standard Unix tools; preflight also requires gh.

Examples:
  printf '%s\n' '{"task":12,"session":"Task supervisor","branch":"task/12-x"}' |
    bash .github/scripts/task-ritual.sh render claim --input - > claim.txt
  bash .github/scripts/task-ritual.sh preflight claim --repo owner/repo \
    --task 12 --body-file claim.txt --branch task/12-x
  bash .github/scripts/task-ritual.sh render plan --input plan.json > plan.txt
  bash .github/scripts/task-ritual.sh preflight plan --repo owner/repo \
    --task 12 --body-file plan.txt --pr 99

Stop on preflight failure; investigate and escalate rather than edit history.
Only after success and the separate procedural authorization may a supervisor
post the body separately. This tool never publishes, edits, deletes, approves,
supersedes records, backdates timestamps, or writes governance settings.
Claim/resume needs no future plan; plan needs a recorded claim; dispatch needs
a recorded claim/plan and a release for replacement. Existing invalid records
remain invalid. Optional PR context requires readable head/link/commit evidence.
The unpublished draft is provisionally evaluated at observation time, not
assigned a publication timestamp; it cannot repair late authorization.
Pre-PR checks cover only the observed draft and ledger, not future CI, approval,
authenticated authorship/session existence, or the create -> confirm worker ->
record dispatch -> implement duty. Races and future publication require a new
check; human approval and merge authority remain unchanged.
HELP
}
[[ "${1:-}" != --help ]] || { help_text; exit 0; }
[[ $# -ge 2 ]] || fail 2 'usage: specify render/preflight and record kind; see --help'
mode="$1" kind="$2"
shift 2
case "$mode" in render|preflight) ;; *) fail 2 'usage: unknown operation' ;; esac
case "$kind" in claim|resume|plan|dispatch) ;; *) fail 2 'usage: unknown record kind' ;; esac
input="" repo="" task="" body_file="" branch="" pr="" seen=" "
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail 2 "missing option value for $1"
  [[ "$seen" != *" $1 "* ]] || fail 2 "duplicate option $1"
  seen="$seen$1 "
  case "$mode:$1" in
    render:--input) input="$2" ;;
    preflight:--repo) repo="$2" ;;
    preflight:--task) task="$2" ;;
    preflight:--body-file) body_file="$2" ;;
    preflight:--branch) branch="$2" ;;
    preflight:--pr) pr="$2" ;;
    *) fail 2 "unknown option $1 for $mode" ;;
  esac
  shift 2
done
for tool in jq git dirname cat grep sed awk sort head date tr; do
  command -v "$tool" >/dev/null 2>&1 || fail 2 "required tool not found: $tool"
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/task-ritual-lib.sh"

read_input() {
  if [[ "$1" == - ]]; then cat; else cat -- "$1"; fi
}
valid_branch() {
  [[ "$1" != -* ]] && git check-ref-format --branch "$1" >/dev/null 2>&1
}
if [[ "$mode" == render ]]; then
  [[ -n "$input" ]] || fail 2 'input file is required'
  json=$(read_input "$input" | jq -cs 'if length == 1 then .[0] else error("expected one JSON object") end') \
    || fail 2 'cannot read input file or malformed JSON input'
  # jq variables intentionally remain literal in this program.
  # shellcheck disable=SC2016
  schema='
    def text: type == "string" and test("\\S");
    def identity: text and (test("[\\x00-\\x1f\\x7f,()]|Starting in session|Resuming in session|Dispatching worker|Releasing worker|## Plan|Plan:") | not)
      and (test("^\\s|\\s$") | not);
    length == 1 and (.[0] |
      type == "object" and
      (.task | type == "number" and . > 0 and . == floor and . <= 9007199254740991) and
      if $kind == "plan" then
        keys == ["content","task"] and (.content | text and (test("[\\x00-\\x08\\x0b-\\x1f\\x7f]") | not))
      elif $kind == "dispatch" then
        keys == ["branch","session","session_id","task"] and
        (.session | identity) and (.branch | identity) and
        (.session_id | type == "string" and test("^[0-9a-fA-F-]{8,}$"))
      else
        keys == ["branch","session","task"] and (.session | identity) and (.branch | identity)
      end)'
  printf '%s\n' "$json" | jq -se --arg kind "$kind" "$schema" >/dev/null 2>&1 \
    || fail 2 'invalid JSON input schema, required field, task, content, or identity'
  if [[ "$kind" != plan ]]; then
    branch=$(printf '%s\n' "$json" | jq -r .branch)
    valid_branch "$branch" || fail 2 'invalid branch input'
  fi
  printf '%s\n' "$json" | jq -r --arg kind "$kind" '
    if $kind == "plan" then "## Plan\n\nTask: #\(.task)\n\n\(.content)"
    elif $kind == "dispatch" then "Dispatching worker: \(.session) (session \(.session_id)), branch \(.branch)\n\nTask: #\(.task)"
    else (if $kind == "claim" then "Starting" else "Resuming" end) +
      " in session \(.session), branch \(.branch)\n\nTask: #\(.task)" end'
  exit 0
fi

command -v gh >/dev/null 2>&1 || fail 2 'required tool not found: gh'
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ && "${repo#*/}" != . && "${repo#*/}" != .. ]] \
  || fail 2 'invalid repository owner/repo'
[[ "$task" =~ ^[1-9][0-9]*$ ]] || fail 2 'task must be a positive number'
[[ -z "$pr" || "$pr" =~ ^[1-9][0-9]*$ ]] || fail 2 'PR must be a positive number'
[[ -n "$body_file" ]] || fail 2 'body-file is required'
[[ -z "$branch" ]] || valid_branch "$branch" || fail 2 'invalid known branch'
draft_json=$(read_input "$body_file" | jq -Rs .) || fail 2 'cannot read body-file'
printf '%s' "$draft_json" | jq -e 'test("[\\x00-\\x08\\x0b-\\x1f\\x7f]") | not' >/dev/null \
  || fail 1 'draft contains control characters'
draft=$(printf '%s\n' "$draft_json" | jq -r .)
first_line="${draft%%$'\n'*}"
case "$kind" in
  claim|resume)
    prefix=Starting; [[ "$kind" != resume ]] || prefix=Resuming
    [[ "$first_line" == "$prefix in session "*", branch "* ]] || fail 1 'invalid claim/resume draft prefix or identity'
    name="${first_line#* in session }"; name="${name%, branch *}"
    [[ -n "$name" ]] || fail 1 'draft session identity is empty'
    ;;
  plan)
    printf '%s\n' "$draft" | jq -Rse "$RITUAL_JQ ritual_plan" >/dev/null \
      || fail 1 'draft needs a plan prefix or heading'
    prose=$(printf '%s\n' "$draft" | sed -E '/^Task: #[0-9]+$/d; s/^## Plan[[:space:]]*$//; s/^Plan:[[:space:]]*//')
    [[ "$prose" =~ [^[:space:]] ]] || fail 1 'plan draft needs content'
    ;;
  dispatch)
    [[ "$first_line" == "Dispatching worker"* ]] || fail 1 'invalid dispatch draft prefix'
    ritual_has_session "$first_line" || fail 1 'dispatch draft needs session identity'
    ;;
esac
if [[ "$kind" != plan ]]; then
  draft_branch=$(ritual_branch "$first_line")
  if [[ -z "$draft_branch" ]] || ! valid_branch "$draft_branch"; then
    fail 1 'draft needs a valid branch'
  fi
  [[ -z "$branch" ]] || ritual_branch_matches "$draft_branch" "$branch" || fail 1 'draft branch differs from known branch'
  [[ -n "$branch" ]] || branch="$draft_branch"
fi
while IFS= read -r declared; do
  [[ -n "$declared" ]] || continue
  [[ "$declared" == "Task: #$task" ]] || fail 1 'draft Task differs from explicit task'
done <<< "$(printf '%s\n' "$draft" | grep -E '^Task: #' || true)"

# No caller-controlled method, endpoint, timestamp, or write options.
get() {
  local out attempt
  for attempt in 1 2 3; do
    if out=$(gh api "$@" --method GET); then printf '%s\n' "$out"; return; fi
    if [[ "$attempt" -lt 3 && "${RITUAL_API_RETRY_DELAY:-2}" != 0 ]]; then
      sleep "${RITUAL_API_RETRY_DELAY:-2}"
    fi
  done
  fail 1 "unavailable read: $1 (three attempts)"
}
valid_json() {
  printf '%s\n' "$1" | jq -se 'length == 1' >/dev/null 2>&1 || fail 1 'malformed JSON read'
}
repo_json=$(get "repos/$repo")
valid_json "$repo_json"
printf '%s\n' "$repo_json" | jq -e --arg repo "$repo" \
  '(.full_name | ascii_downcase) == ($repo | ascii_downcase)' >/dev/null 2>&1 \
  || fail 1 'repository response does not match requested repo'
repo=$(printf '%s\n' "$repo_json" | jq -r .full_name)
issue_url="https://api.github.com/repos/$repo/issues/$task"
issue_json=$(get "repos/$repo/issues/$task")
valid_json "$issue_json"
printf '%s\n' "$issue_json" | jq -e --arg url "$issue_url" --arg task "$task" '
  .url == $url and (.number | tostring) == $task and (has("pull_request") | not) and
  (.comments | type == "number" and . >= 0 and . == floor) and
  (.labels | type == "array" and any(.[]; .name == "type:task"))' >/dev/null 2>&1 \
  || fail 1 'invalid Task metadata, comments count, or missing type:task label'
pages=$(get "repos/$repo/issues/$task/comments?per_page=100" --paginate --slurp)
valid_json "$pages"
printf '%s\n' "$pages" | jq -e '
  type == "array" and length > 0 and all(.[]; type == "array" and length <= 100)
  and all(.[0:-1][]; length == 100)' >/dev/null 2>&1 || fail 1 'malformed or incomplete comments pages'
comments=$(printf '%s\n' "$pages" | jq 'add')
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' "$comments" | jq -e --arg url "$issue_url" --arg now "$now" \
  --argjson count "$(printf '%s\n' "$issue_json" | jq .comments)" '
    def stamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
      and . <= $now and (. as $original | try ((fromdateiso8601 | todateiso8601) == $original) catch false);
    length == $count and ([.[].id] | length == (unique | length)) and
    all(.[]; type == "object" and (.id | type == "number" and . > 0 and . == floor) and
      (.body | type == "string") and .issue_url == $url and
      (.created_at | stamp) and (.updated_at | stamp))' >/dev/null 2>&1 \
  || fail 1 'invalid ledger comments: count, duplicate, identity, or timestamp'
markers=$(printf '%s\n' "$comments" | jq -r "$RITUAL_JQ ritual_markers")
edited=$(printf '%s\n' "$markers" | awk -F '\t' '$1 != "EXEMPT" && $2 != $3')
[[ -z "$edited" ]] || fail 1 'earlier ritual records were edited; a draft cannot repair immutable history'
earliest() { printf '%s\n' "$markers" | awk -F '\t' -v kind="$1" '$1 == kind {print $2}' | sort | head -n1; }
claim_time=$(earliest CLAIM)
plan_time=$(earliest PLAN)
dispatch_time=$(earliest DISPATCH)
if [[ "$kind" == plan || "$kind" == dispatch || -n "$plan_time$dispatch_time" ]]; then
  [[ -n "$claim_time" ]] || fail 1 'recorded claim prerequisite is missing'
fi
if [[ "$kind" == dispatch || -n "$dispatch_time" ]]; then
  [[ -n "$plan_time" ]] || fail 1 'recorded plan prerequisite is missing'
fi
[[ -z "$plan_time" || ! "$claim_time" > "$plan_time" ]] || fail 1 'existing claim/plan chronology is out of order'
[[ -z "$dispatch_time" || ! "$plan_time" > "$dispatch_time" ]] || fail 1 'existing plan/dispatch chronology is out of order'

# The provisional row never leaves memory and is never used as a posted record.
candidate=$(jq -n --arg body "$draft" --arg now "$now" \
  '[{body:$body,created_at:$now,updated_at:$now}]')
markers="$markers"$'\n'"$(printf '%s\n' "$candidate" | jq -r "$RITUAL_JQ ritual_markers")"
previous=""
releases=$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "RELEASE" {print $2}')
while IFS= read -r time; do
  [[ -n "$time" ]] || continue
  if [[ -n "$previous" ]]; then
    released=false
    while IFS= read -r release; do
      [[ -n "$release" ]] || continue
      if [[ ! "$release" < "$previous" && ! "$release" > "$time" ]]; then released=true; break; fi
    done <<< "$releases"
    $released || fail 1 'replacement dispatch needs a release between dispatches'
  fi
  previous="$time"
done <<< "$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "DISPATCH" {print $2}' | sort)"

if [[ -n "$pr" ]]; then
  pull=$(get "repos/$repo/pulls/$pr")
  valid_json "$pull"
  printf '%s\n' "$pull" | jq -e --arg repo "$repo" --arg pr "$pr" '
    (.number | tostring) == $pr and .base.repo.full_name == $repo and
    (.body | type == "string") and (.head.ref | type == "string" and length > 0) and
    (.commits | type == "number" and . > 0 and . == floor)' >/dev/null 2>&1 \
    || fail 1 'invalid requested PR metadata, repository, head, or commit count'
  head_ref=$(printf '%s\n' "$pull" | jq -r .head.ref)
  [[ -z "$branch" ]] || ritual_branch_matches "$branch" "$head_ref" || fail 1 'known branch conflicts with PR head'
  branch="$head_ref"
  body=$(printf '%s\n' "$pull" | jq -r .body)
  link=$(printf '%s\n' "$body" | ritual_task_link)
  [[ "${link##*#}" == "$task" ]] || fail 1 'PR task linkage does not match explicit Task'
  plan_link=$(printf '%s\n' "$body" | ritual_plan_link | tr '[:upper:]' '[:lower:]')
  link_repo=$(printf '%s\n' "$plan_link" | sed -E 's|.*github\.com/([^/]+/[^/]+)/issues/.*|\1|')
  link_task=$(printf '%s\n' "$plan_link" | sed -E 's|.*/issues/([0-9]+)#issuecomment-[0-9]+.*|\1|')
  [[ "$link_repo" == "$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')" && "$link_task" == "$task" ]] \
    || fail 1 'PR plan link must name this repository and Task'
  comment_id="${plan_link##*#issuecomment-}"
  resolved=$(get "repos/$repo/issues/comments/$comment_id")
  valid_json "$resolved"
  printf '%s\n' "$resolved" | jq -e --arg url "$issue_url" "$RITUAL_JQ"'
    .issue_url == $url and (.body | ritual_plan)' >/dev/null 2>&1 || fail 1 'PR plan link does not resolve to a plan on this Task'
  commit_pages=$(get "repos/$repo/pulls/$pr/commits?per_page=100" --paginate --slurp)
  valid_json "$commit_pages"
  printf '%s\n' "$commit_pages" | jq -e --arg now "$now" --argjson count "$(printf '%s\n' "$pull" | jq .commits)" '
    type == "array" and length > 0 and all(.[]; type == "array" and length <= 100) and
    all(.[0:-1][]; length == 100) and (add |
      length == $count and all(.[]; (.commit.committer.date // .commit.author.date) |
        type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and . <= $now and
        (. as $original | try ((fromdateiso8601 | todateiso8601) == $original) catch false)))' >/dev/null 2>&1 \
    || fail 1 'incomplete or malformed PR commits read'
  first_commit=$(printf '%s\n' "$commit_pages" | jq -r 'add | .[].commit | .committer.date // .author.date' | sort | head -n1)
  plan_time=$(earliest PLAN)
  [[ -n "$plan_time" ]] || fail 1 'PR needs a recorded plan before its commit'
  [[ ! "$plan_time" > "$first_commit" ]] || fail 1 'first commit predates plan; draft cannot backdate authorization'
  dispatch_time=$(earliest DISPATCH)
  if [[ -n "$dispatch_time" ]]; then
    [[ ! "$dispatch_time" > "$first_commit" ]] || fail 1 'first commit predates dispatch; draft cannot backdate authorization'
  else
    exempt_time=$(earliest EXEMPT)
    [[ -n "$exempt_time" && ! "$exempt_time" > "$first_commit" ]] || fail 1 'PR lacks an execution mode declared before its commit'
  fi
fi
while IFS=$'\t' read -r _kind _created _updated line superseded; do
  [[ -n "$line" ]] || continue
  ritual_has_session "$line" || fail 1 'ledger dispatch names no session identity'
  dispatched=$(ritual_branch "$line")
  [[ -n "$dispatched" ]] || fail 1 'ledger dispatch names no branch'
  if [[ "$superseded" -eq 0 && -n "$branch" ]]; then
    ritual_branch_matches "$dispatched" "$branch" || fail 1 'unsuperseded dispatch branch does not match known branch'
  fi
done <<< "$(printf '%s\n' "$markers" | ritual_dispatch_rows)"
printf 'PASS: observed %s draft and ledger checks for %s#%s%s only.\n' "$kind" "$repo" "$task" "${pr:+ with PR #$pr}"
printf '%s\n' 'Not publication, future CI success, approval, or authenticated session existence. Recheck before separately posting.'
