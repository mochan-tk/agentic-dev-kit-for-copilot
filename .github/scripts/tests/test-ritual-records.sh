#!/usr/bin/env bash
# Offline CLI contract tests; production children deliberately use Bash 3.2.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"
CLI="$ROOT/.github/scripts/task-ritual.sh"
GUARD="$ROOT/.github/scripts/check-task-ritual.sh"
BASH_BIN="${RITUAL_TEST_BASH:-/bin/bash}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ritual-records.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fixtures"
export GH_FIXTURES="$WORK/fixtures" RITUAL_CALLS="$WORK/calls"
: > "$RITUAL_CALLS"
cat > "$WORK/bin/gh" <<'SHIM'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$RITUAL_CALLS"
[[ "$1" == api ]] || exit 64
shift
endpoint="" query="." paginate=false slurp=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method|-X)
      [[ "$2" == GET ]] || { echo MUTATION >> "$RITUAL_CALLS"; exit 64; }
      shift 2 ;;
    --jq) query="$2"; shift 2 ;;
    --paginate) paginate=true; shift ;;
    --slurp) slurp=true; shift ;;
    repos/*) endpoint="$1"; shift ;;
    *) echo MUTATION >> "$RITUAL_CALLS"; exit 64 ;;
  esac
done
case "$endpoint" in
  repos/*/issues/*/comments*)
    if $paginate; then
      # Emit an initial page before a later-page failure to catch partial success.
      if [[ -f "$GH_FIXTURES/later-failure" ]]; then
        cat "$GH_FIXTURES/comments.json"
        echo 'later page unavailable' >&2
        exit 1
      fi
      if $slurp; then
        if [[ -f "$GH_FIXTURES/pages.json" ]]; then
          cat "$GH_FIXTURES/pages.json"
        else
          jq -s '.' "$GH_FIXTURES/comments.json"
        fi
      elif [[ -f "$GH_FIXTURES/pages.json" ]]; then
        jq -r ".[] | $query" "$GH_FIXTURES/pages.json"
      else
        jq -r "$query" "$GH_FIXTURES/comments.json"
      fi
      exit
    fi
    echo 'comments must be paginated' >&2; exit 64 ;;
  repos/*/issues/comments/*) file=comment ;;
  repos/*/issues/*) file=issue ;;
  repos/*/pulls/*/commits*)
    if $slurp; then jq -s '.' "$GH_FIXTURES/commits.json"; exit; fi
    file=commits ;;
  repos/*/pulls/*) file=pull ;;
  repos/*/contents/*) file=contents ;;
  repos/*) file=repo ;;
  *) exit 64 ;;
esac
[[ -f "$GH_FIXTURES/$file.json" ]] || { echo 'fixture unavailable' >&2; exit 1; }
jq -r "$query" "$GH_FIXTURES/$file.json"
SHIM
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

capture() {
  RC=0
  "$@" > "$WORK/out" 2> "$WORK/err" || RC=$?
}
assert_result() {
  local want="$1" pattern="$2" name="$3"
  if [[ "$RC" -eq "$want" ]] && grep -Eq "$pattern" "$WORK/out" "$WORK/err" \
      && { [[ "$want" -eq 0 ]] || [[ ! -s "$WORK/out" ]]; }; then
    t_ok "$name"
  else
    t_fail "$name (rc=$RC, expected $want; pattern $pattern)"
    cat "$WORK/out" "$WORK/err"
  fi
}
render() {
  printf '%s\n' "$2" > "$WORK/input"
  capture "$BASH_BIN" "$CLI" render "$1" --input "$WORK/input"
}
CLAIM_INPUT='{"task":12,"session":"Task supervisor","branch":"task/12-x"}'
PLAN_INPUT='{"task":12,"content":"Implement and verify."}'
DISPATCH_INPUT='{"task":12,"session":"Task worker","session_id":"abcdef12-3456","branch":"task/12-x"}'
CLAIM=$'Starting in session Task supervisor, branch task/12-x\n\nTask: #12'
RESUME=$'Resuming in session Task supervisor, branch task/12-x\n\nTask: #12'
PLAN=$'## Plan\n\nTask: #12\n\nImplement and verify.'
DISPATCH=$'Dispatching worker: Task worker (session abcdef12-3456), branch task/12-x\n\nTask: #12'
for kind in claim resume plan dispatch; do
  case "$kind" in
    claim) input="$CLAIM_INPUT"; expected="$CLAIM" ;;
    resume) input="$CLAIM_INPUT"; expected="$RESUME" ;;
    plan) input="$PLAN_INPUT"; expected="$PLAN" ;;
    dispatch) input="$DISPATCH_INPUT"; expected="$DISPATCH" ;;
  esac
  render "$kind" "$input"
  if [[ "$RC" -eq 0 && "$(cat "$WORK/out")" == "$expected" && ! -s "$WORK/err" ]]; then
    t_ok "$kind exact canonical body"
  else t_fail "$kind exact canonical body"; fi
done
if [[ ! -s "$RITUAL_CALLS" ]]; then t_ok "render has zero network calls"; else t_fail "render has zero network calls"; fi
capture "$BASH_BIN" "$CLI" render claim --input - <<< "$CLAIM_INPUT"
assert_result 0 '^Starting in session' "stdin input"
for input in '{}' '{"task":0}' '{"task":"12","content":"x"}' '{"task":12,"content":""}' \
  '{"task":12,"content":"x","extra":true}' '[]' 'null' '{' \
  '{"task":12,"content":"x"} {"task":12,"content":"y"}'; do
  render plan "$input"
  assert_result 2 'input|JSON|schema|field|task|content' "reject invalid plan input: $input"
done
for field in session branch session_id; do
  for bad in $'x\n## Plan' $'x\rDispatching worker' $'x\tbranch bad' 'x, branch injected' 'Starting in session injected'; do
    input=$(printf '%s' "$DISPATCH_INPUT" | jq --arg f "$field" --arg v "$bad" '.[$f]=$v')
    render dispatch "$input"
    assert_result 2 'input|identity|session|branch|field' "reject $field injection"
  done
  input=$(printf '%s' "$DISPATCH_INPUT" | jq --arg f "$field" 'del(.[$f])')
  render dispatch "$input"
  assert_result 2 'input|schema|field|session|branch' "reject missing $field"
done
render claim '{"task":12,"session":"s","branch":"bad..ref"}'
assert_result 2 'branch|input' "invalid Git branch"
render plan '{"task":12,"content":"bad\u0000content"}'
assert_result 2 'input|content|control' "plan content rejects NUL"
capture "$BASH_BIN" "$CLI" render claim --input "$WORK/input" --approve
assert_result 2 'option|usage' "no approval option"
capture "$BASH_BIN" "$CLI" render claim --input
assert_result 2 'value|usage|input' "missing option value"
capture "$BASH_BIN" "$CLI" --help
assert_result 0 'preflight' "help includes interface"
for text in 'session_id' 'Exit' 'Stop' 'approval' 'CI' 'publish'; do
  if grep -q "$text" "$WORK/out"; then t_ok "help documents $text"; else t_fail "help documents $text"; fi
done

comment() {
  jq -n --arg body "$1" --arg time "$2" --argjson id "$3" \
    '{id:$id,body:$body,created_at:$time,updated_at:$time,issue_url:"https://api.github.com/repos/o/r/issues/12"}'
}
C=$(comment "$CLAIM" 2026-01-01T09:00:00Z 1)
P=$(comment "$PLAN" 2026-01-01T09:05:00Z 2)
D=$(comment "$DISPATCH" 2026-01-01T09:10:00Z 3)
R=$(comment 'Releasing worker: old worker' 2026-01-01T09:15:00Z 4)
ledger() {
  printf '%s\n' "$1" > "$GH_FIXTURES/comments.json"
  jq '{number:12,comments:length,labels:[{name:"type:task"}],url:"https://api.github.com/repos/o/r/issues/12"}' \
    "$GH_FIXTURES/comments.json" > "$GH_FIXTURES/issue.json"
  printf '%s\n' '{"full_name":"o/r"}' > "$GH_FIXTURES/repo.json"
  printf '%s\n' '{"sha":"exists"}' > "$GH_FIXTURES/contents.json"
  printf '%s\n' "$P" > "$GH_FIXTURES/comment.json"
  printf '%s\n' '{"number":99,"user":{"login":"human","type":"User"},"title":"Work","base":{"ref":"main","repo":{"full_name":"o/r"}},"head":{"ref":"task/12-x"},"commits":1,"body":"Closes #12\n\nPlan: https://github.com/o/r/issues/12#issuecomment-2"}' > "$GH_FIXTURES/pull.json"
  printf '%s\n' '[{"commit":{"committer":{"date":"2026-01-01T10:00:00Z"},"author":{"date":"2026-01-01T08:00:00Z"}}}]' > "$GH_FIXTURES/commits.json"
  rm -f "$GH_FIXTURES/pages.json" "$GH_FIXTURES/later-failure"
}
preflight() {
  local kind="$1" body="$2"
  shift 2
  printf '%s\n' "$body" > "$WORK/body"
  capture "$BASH_BIN" "$CLI" preflight "$kind" --repo o/r --task 12 --body-file "$WORK/body" "$@"
}
ledger '[]'
preflight claim "$CLAIM"
assert_result 0 'observed|draft' "initial claim needs no invented prerequisite"
preflight resume "$RESUME"
assert_result 0 'observed|draft' "resume needs no invented prerequisite"
preflight plan "$PLAN"
assert_result 1 'claim' "plan requires claim"
preflight dispatch "$DISPATCH"
assert_result 1 'claim|plan' "dispatch requires claim and plan"
ledger "[$C]"
preflight dispatch "$DISPATCH"
assert_result 1 'plan' "dispatch requires plan"
preflight plan "$PLAN"
assert_result 0 'observed|draft' "plan after claim"
ledger "[$C,$P]"
preflight dispatch "$DISPATCH" --branch copilot/task/12-x
assert_result 0 'observed|draft' "dispatch after plan and managed branch"
for text in 'CI' 'approval' 'session'; do
  if grep -q "$text" "$WORK/out"; then t_ok "preflight scopes $text"; else t_fail "preflight scopes $text"; fi
done
preflight dispatch "$DISPATCH" --branch task/34-wrong
assert_result 1 'branch' "known wrong branch"
preflight plan "${PLAN/Task: #12/Task: #34}"
assert_result 1 'Task|task' "draft wrong Task"
for bad in $'\nStarting in session s, branch task/12-x' '# Starting in session s' 'Starting session s'; do
  preflight claim "$bad"
  assert_result 1 'draft|claim|prefix' "malformed first-line claim"
done
preflight dispatch 'Dispatching worker: worker, branch task/12-x'
assert_result 1 'session|identity' "dispatch draft needs session identity"
preflight plan 'Plan:'
assert_result 1 'content|plan|draft' "plan draft needs content"
printf 'Starting in session s\0, branch task/12-x\n' > "$WORK/body"
capture "$BASH_BIN" "$CLI" preflight claim --repo o/r --task 12 --body-file "$WORK/body"
assert_result 1 'control|draft' "raw NUL draft cannot be silently normalized"
ledger "[$C,$P,$D]"
preflight dispatch "$DISPATCH"
assert_result 1 'release|replacement' "unreleased replacement"
ledger "[$C,$P,$D,$R]"
preflight dispatch "$DISPATCH" --branch task/12-x
assert_result 0 'observed|draft' "released replacement"
old=$(printf '%s' "$D" | jq '.body |= sub("task/12-x";"managed-old")')
ledger "[$C,$P,$old,$R]"
preflight dispatch "$DISPATCH" --branch task/12-x
assert_result 0 'observed|draft' "released old branch is superseded by candidate"
ledger "[$C,$P,$old]"
preflight resume "$RESUME" --branch task/12-x
assert_result 1 'branch' "unsuperseded historical wrong branch fails"
ledger "[$C,$P,$D]"
jq '.[2].body="Dispatching worker: missing identity, branch task/12-x"' "$GH_FIXTURES/comments.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/comments.json"
preflight resume "$RESUME"
assert_result 1 'session' "earlier malformed dispatch identity fails"
ledger "[$C,$P,$D]"
jq '.[2].created_at="2026-01-01T09:02:00Z" | .[2].updated_at=.[2].created_at' "$GH_FIXTURES/comments.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/comments.json"
preflight resume "$RESUME"
assert_result 1 'order|chronology' "earlier dispatch before plan fails"
for index in 0 1 2 3; do
  ledger "[$C,$P,$D,$R]"
  jq --argjson i "$index" '.[$i].updated_at="2026-01-01T09:30:00Z"' "$GH_FIXTURES/comments.json" > "$WORK/change"
  cp "$WORK/change" "$GH_FIXTURES/comments.json"
  preflight resume "$RESUME"
  assert_result 1 'edited|immutable' "earlier edited record $index cannot be repaired"
done
ledger "[$C,$P]"
jq '.[0].created_at="2026-01-01T09:06:00Z" | .[0].updated_at=.[0].created_at' "$GH_FIXTURES/comments.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/comments.json"
preflight plan "$PLAN"
assert_result 1 'order|chronology' "earlier chronology cannot be repaired"
ledger "[$C,$P,$D]"
preflight resume "$RESUME" --pr 99
assert_result 0 'observed|draft' "optional PR checks existing valid trail"
ledger "[$C,$P,$D]"
jq '.[0].commit.committer.date=null | .[0].commit.author.date="2026-01-01T10:00:00Z"' "$GH_FIXTURES/commits.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/commits.json"
preflight resume "$RESUME" --pr 99
assert_result 0 'observed|draft' "optional PR author-date fallback"
preflight resume "$RESUME" --pr 99 --branch wrong
assert_result 1 'branch|head' "optional PR conflicts with explicit branch"
ledger "[$C]"
preflight plan "$PLAN" --pr 99
assert_result 1 'commit|predat|late' "draft cannot backdate missing plan before observed commit"
ledger "[$C,$P]"
preflight dispatch "$DISPATCH" --pr 99
assert_result 1 'commit|predat|late' "draft cannot backdate missing dispatch before observed commit"
ledger "[$C,$P,$D]"
rm "$GH_FIXTURES/pull.json"
preflight resume "$RESUME" --pr 99
assert_result 1 'PR|read|unavailable' "unavailable requested PR never downgrades"
for change in '.body="Closes #34"' '.body="Closes #12\nPlan: https://github.com/other/r/issues/12#issuecomment-2"' \
  '.head.ref="wrong"' '.commits=2' '.base.repo.full_name="other/r"'; do
  ledger "[$C,$P,$D]"
  jq "$change" "$GH_FIXTURES/pull.json" > "$WORK/change"
  cp "$WORK/change" "$GH_FIXTURES/pull.json"
  preflight resume "$RESUME" --pr 99
  assert_result 1 'PR|plan|Plan|branch|head|commit|repository|Task|task' "optional PR rejects $change"
done
ledger "[$C,$P]"
printf '%s\n' '{"full_name":"other/r"}' > "$GH_FIXTURES/repo.json"
preflight dispatch "$DISPATCH"
assert_result 1 'repository|repo' "wrong repository response"
ledger "[$C,$P]"
jq '.number=34' "$GH_FIXTURES/issue.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/issue.json"
preflight dispatch "$DISPATCH"
assert_result 1 'Task|task|issue' "wrong Task response"
ledger "[$C,$P]"
jq '.labels=[]' "$GH_FIXTURES/issue.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/issue.json"
preflight dispatch "$DISPATCH"
assert_result 1 'type:task' "Task routing label required"

# A 101-record ledger: the required plan is only on the second page.
ledger "[$C,$P]"
jq --argjson c "$C" --argjson p "$P" -n \
  '[[$c] + [range(10;109) | {id:.,body:"noise",created_at:"2026-01-01T09:01:00Z",updated_at:"2026-01-01T09:01:00Z",issue_url:"https://api.github.com/repos/o/r/issues/12"}],[$p]]' > "$GH_FIXTURES/pages.json"
jq '.comments=101' "$GH_FIXTURES/issue.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/issue.json"
preflight dispatch "$DISPATCH"
assert_result 0 'observed|draft' "complete multi-page ledger uses later-page plan"
touch "$GH_FIXTURES/later-failure"
preflight dispatch "$DISPATCH"
assert_result 1 'read|page|unavailable' "later page failure rejects partial response"
rm "$GH_FIXTURES/later-failure"
for pages in '[]' '[[]]' '[{},[]]' '[[' '[[],[]]'; do
  printf '%s\n' "$pages" > "$GH_FIXTURES/pages.json"
  preflight dispatch "$DISPATCH"
  assert_result 1 'page|JSON|ledger|comments|count|read' "malformed or incomplete pagination $pages"
done
ledger "[$C,$P]"
printf '%s\n' "[[$C,$C]]" > "$GH_FIXTURES/pages.json"
preflight dispatch "$DISPATCH"
assert_result 1 'duplicate|ledger|comments' "duplicate paginated records"
ledger "[$C,$P]"
printf '%s\n' '[{"body":"Starting in session x"}]' > "$GH_FIXTURES/comments.json"
preflight dispatch "$DISPATCH"
assert_result 1 'ledger|comment|timestamp' "malformed ledger record"
ledger "[$C,$P]"
jq '.[0].created_at="2026-00-00T09:00:00Z" | .[0].updated_at=.[0].created_at' "$GH_FIXTURES/comments.json" > "$WORK/change"
cp "$WORK/change" "$GH_FIXTURES/comments.json"
preflight dispatch "$DISPATCH"
assert_result 1 'timestamp|ledger' "impossible ledger date"
ledger "[$C,$P]"
preflight plan $'Plan: Updated approach.\n\nTask: #12'
assert_result 0 'observed|draft' "legacy Plan prefix remains accepted"

# The rendered artifacts themselves, not a test-only parser, feed the CI wall.
ledger '[]'
for kind in claim plan dispatch; do
  case "$kind" in
    claim) input="$CLAIM_INPUT"; stamp=2026-01-01T09:00:00Z; id=1 ;;
    plan) input="$PLAN_INPUT"; stamp=2026-01-01T09:05:00Z; id=2 ;;
    dispatch) input="$DISPATCH_INPUT"; stamp=2026-01-01T09:10:00Z; id=3 ;;
  esac
  render "$kind" "$input"
  generated=$(cat "$WORK/out")
  preflight "$kind" "$generated"
  assert_result 0 'observed|draft' "$kind generated preflight round trip"
  row=$(comment "$generated" "$stamp" "$id")
  jq --argjson row "$row" '. + [$row]' "$GH_FIXTURES/comments.json" > "$WORK/change"
  ledger "$(cat "$WORK/change")"
done
capture "$BASH_BIN" "$GUARD" 99
assert_result 0 'ritual in order' "generated records pass production CI parser"
render resume "$CLAIM_INPUT"
row=$(comment "$(cat "$WORK/out")" 2026-01-01T09:00:00Z 1)
jq --argjson row "$row" '.[0]=$row' "$GH_FIXTURES/comments.json" > "$WORK/change"
ledger "$(cat "$WORK/change")"
capture "$BASH_BIN" "$GUARD" 99
assert_result 0 'ritual in order' "generated resume passes production CI parser"
ledger "[$C]"
render plan '{"task":12,"content":"Small change; no worker will be spawned."}'
preflight plan "$(cat "$WORK/out")"
assert_result 0 'observed|draft' "explicit human-supplied exemption remains allowed"
if grep -q 'MUTATION' "$RITUAL_CALLS"; then t_fail "zero mutating API calls"; else t_ok "zero mutating API calls"; fi
if grep -q -- '--method GET' "$RITUAL_CALLS"; then t_ok "preflight explicitly uses GET"; else t_fail "preflight explicitly uses GET"; fi

# An isolated PATH makes dependency failures observable without uninstalling tools.
mkdir "$WORK/no-tools"
ln -s "$(command -v dirname)" "$WORK/no-tools/dirname"
capture env PATH="$WORK/no-tools" "$BASH_BIN" "$CLI" render plan --input "$WORK/input"
assert_result 2 'not found|requires|missing' "missing dependency fails explicitly"
for tool in jq git cat grep sed awk sort head date tr; do
  ln -s "$(command -v "$tool")" "$WORK/no-tools/$tool"
done
capture env PATH="$WORK/no-tools" "$BASH_BIN" "$CLI" preflight claim --repo o/r --task 12 --body-file "$WORK/body"
assert_result 2 'not found: gh' "missing gh fails explicitly"
t_summary
