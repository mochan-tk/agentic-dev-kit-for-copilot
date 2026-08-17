#!/usr/bin/env bash
# test-governance-status.sh — fixture wall for the read-only governance
# sensor: profiles, effective-rule aggregation, bypass qualification,
# evidence states, exit precedence, and a GET-only gh shim that hard-fails
# any mutating invocation.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SENSOR="$ROOT/.github/scripts/governance-status.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/governance-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fix" "$WORK/cwd"
export GH_CALLS="$WORK/gh.log" GS_FIX="$WORK/fix"
T="$(printf '\t')"

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$GH_CALLS"
for a in "$@"; do
  case "$a" in
    -X*|--method*|-f*|-F*|--field*|--raw-field*|--input*|POST|PUT|PATCH|DELETE)
      printf 'MUTATION %s\n' "$*" >> "$GH_CALLS"
      echo "gh stub: mutating invocation refused" >&2
      exit 64 ;;
  esac
done
[ "${1:-}" = api ] || { printf 'MUTATION %s\n' "$*" >> "$GH_CALLS"; exit 64; }
shift
path=""
while [ $# -gt 0 ]; do
  case "$1" in
    -H) shift 2 ;;
    --paginate) shift ;;
    *) path="$1"; shift ;;
  esac
done
for frag in ${GS_FAIL:-}; do
  case "$path" in *"$frag"*) echo "gh: HTTP 500 (simulated)" >&2; exit 1 ;; esac
done
if [ "$path" = "repos/o/r/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE" ]; then
  case "${GS_VAR_ERROR:-}" in
    "") ;;
    404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    actions-disabled) echo "gh: Actions are disabled (HTTP 403)" >&2; exit 1 ;;
    unauthorized) echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1 ;;
    generic) echo "gh: Internal Server Error (HTTP 500)" >&2; exit 1 ;;
    *) echo "gh stub: unknown variable error fixture" >&2; exit 64 ;;
  esac
fi
case "$path" in
  repos/*/rules/branches/*) f=rules.json ;;
  repos/*/rulesets/*) f="rs-repo-${path##*/}.json" ;;
  orgs/*/rulesets/*) f="rs-org-${path##*/}.json" ;;
  orgs/*) f=org.json ;;
  repos/*/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE) f=profile.json ;;
  repos/*/actions/permissions/workflow) f=workflow.json ;;
  repos/*/commits/*/check-runs*) f=checkruns.json ;;
  repos/*/contents/.github/workflows/*) p="${path%%\?*}"; f="wff-${p##*/}" ;;
  repos/*/contents/.github/workflows*) f=wfdir.json ;;
  repos/*/contents/SCAFFOLD-CHANGELOG.md*) f=changelog.raw ;;
  repos/*/contents/.github/CODEOWNERS*) f=codeowners.raw ;;
  repos/*) f=repo.json ;;
  *) echo "gh stub: no fixture mapped for '$path'" >&2; exit 64 ;;
esac
[ -f "$GS_FIX/$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
cat "$GS_FIX/$f"
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

solo_rules() {
  cat > "$GS_FIX/rules.json" <<'J'
[{"type":"pull_request","parameters":{"required_approving_review_count":1,
"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,
"require_last_push_approval":false,"required_review_thread_resolution":false},
"ruleset_source_type":"Repository","ruleset_source":"o/r","ruleset_id":101},
{"type":"required_status_checks","parameters":{
"strict_required_status_checks_policy":false,"required_status_checks":[
{"context":"quality"},{"context":"task-ritual"},
{"context":"scaffold-self-check"},{"context":"copilot-surface"}]},
"ruleset_source_type":"Repository","ruleset_source":"o/r","ruleset_id":101}]
J
}
team_rules() { # fully hardened; binds every context to app id $1
  solo_rules
  jq --argjson app "$1" '
    (.[]|select(.type=="pull_request").parameters) |=
      (.dismiss_stale_reviews_on_push=true | .require_code_owner_review=true
       | .require_last_push_approval=true | .required_review_thread_resolution=true)
    | (.[]|select(.type=="required_status_checks").parameters) |=
      (.strict_required_status_checks_policy=true
       | .required_status_checks |= map(.integration_id=$app))' \
    "$GS_FIX/rules.json" > "$GS_FIX/r.tmp" && mv "$GS_FIX/r.tmp" "$GS_FIX/rules.json"
}
mk_repo() { printf '{"default_branch":"main","owner":{"login":"o","type":"%s"},"private":%s%s}\n' "$1" "$2" "${3:-}" > "$GS_FIX/repo.json"; }
mk_org() { printf '{"login":"o"%s}\n' "${1:-}" > "$GS_FIX/org.json"; }
mk_rs() { printf '{"id":%s,"bypass_actors":%s}\n' "$1" "$3" > "$GS_FIX/rs-$2-$1.json"; }
mk_wf() { printf '{"default_workflow_permissions":"%s","can_approve_pull_request_reviews":%s}\n' "$1" "$2" > "$GS_FIX/workflow.json"; }
mk_runs() {
  local out="" sep="" p
  for p in "$@"; do
    out="$out$sep{\"name\":\"${p%%:*}\",\"app\":{\"id\":${p##*:},\"slug\":\"github-actions\"}}"
    sep=","
  done
  printf '{"total_count":%s,"check_runs":[%s]}\n' "$#" "$out" > "$GS_FIX/checkruns.json"
}
mk_marker() { printf '# log\n<!-- scaffold-version: repo=o/r sha=%s date=x -->\n' "$1" > "$GS_FIX/changelog.raw"; }
mk_co() { printf '%s\n/.github/docs/agreements/ @owner\n' "$1" > "$GS_FIX/codeowners.raw"; }
mk_wfdir() { local out="" sep="" n; for n in "$@"; do out="$out$sep{\"name\":\"$n\",\"type\":\"file\"}"; sep=","; done; printf '[%s]\n' "$out" > "$GS_FIX/wfdir.json"; }
mk_wff() { printf '%s\n' "$2" > "$GS_FIX/wff-$1"; }

RRB='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
baseline() { # live-like template repository on the solo minimum
  rm -f "$GS_FIX"/*
  solo_rules
  mk_rs 101 repo "$RRB"
  mk_runs quality:15368 task-ritual:15368 scaffold-self-check:15368 copilot-surface:15368
  mk_wf read false; mk_repo User false
  mk_marker unknown; mk_co '# CUSTOMIZE: replace @owner'
}
team_green() { # hardened adopted fixtures that satisfy team intent end to end
  baseline
  team_rules 15368; mk_rs 101 repo '[]'
  mk_marker abc123; mk_co '# reviewed owners'
}

run() {
  rc=0
  bash "$SENSOR" "$@" > "$WORK/stdout" 2> "$WORK/stderr" || rc=$?
  out="$(cat "$WORK/stdout")"; err="$(cat "$WORK/stderr")"
}
runf() {
  local f="$1"
  shift; rc=0
  GS_FAIL="$f" bash "$SENSOR" "$@" > "$WORK/stdout" 2> "$WORK/stderr" || rc=$?
  out="$(cat "$WORK/stdout")"; err="$(cat "$WORK/stderr")"
}
runv() {
  local e="$1"
  shift; rc=0
  GS_VAR_ERROR="$e" bash "$SENSOR" "$@" > "$WORK/stdout" 2> "$WORK/stderr" || rc=$?
  out="$(cat "$WORK/stdout")"; err="$(cat "$WORK/stderr")"
}
rce() { if [ "$rc" -eq "$2" ]; then t_ok "$1"; else t_fail "$1 (rc=$rc)"; printf '%s\n%s\n' "$out" "$err" | sed 's/^/    # /'; fi; }
chk() { if printf '%s\n' "$out" | grep -Eq "$2"; then t_ok "$1"; else t_fail "$1 (missing: $2)"; printf '%s\n%s\n' "$out" "$err" | sed 's/^/    # /'; fi; }

PROFILE_REQ="api repos/o/r/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE"
PROFILE_UNKNOWN="^governance\\.profile${T}UNKNOWN${T}persisted profile unavailable or invalid; expected exact solo\\|team$"
clear_calls() { : > "$GH_CALLS"; }
mk_profile() { printf '%s\n' "$1" > "$GS_FIX/profile.json"; }
profile_gets() { grep -Fxc "$PROFILE_REQ" "$GH_CALLS" 2>/dev/null || true; }
profile_endpoint_calls() {
  grep -Fc "repos/o/r/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE" "$GH_CALLS" 2>/dev/null || true
}
get_once() {
  if [ "$(profile_gets)" -eq 1 ] && [ "$(profile_endpoint_calls)" -eq 1 ]; then
    t_ok "$1"
  else
    t_fail "$1 (plain=$(profile_gets) endpoint=$(profile_endpoint_calls))"
  fi
}
get_never() {
  if [ "$(profile_endpoint_calls)" -eq 0 ]; then
    t_ok "$1"
  else
    t_fail "$1 (endpoint=$(profile_endpoint_calls))"
  fi
}
save_run() { saved_rc="$rc"; saved_out="$out"; saved_err="$err"; }
same_run() {
  if [ "$rc" -eq "$saved_rc" ] && [ "$out" = "$saved_out" ] && [ "$err" = "$saved_err" ]; then
    t_ok "$1"
  else
    t_fail "$1 (explicit rc=$saved_rc persisted rc=$rc)"
  fi
}
unknown_facts() {
  chk "$1 keeps default branch fact" "^repository\\.default_branch${T}ACTIVE${T}main$"
  chk "$1 keeps approval fact" "^pull_request\\.required_approving_review_count${T}ACTIVE"
  chk "$1 keeps context fact" "^required_checks\\.context\\.quality${T}ACTIVE"
  chk "$1 keeps Actions fact" "^actions\\.default_workflow_permissions${T}ACTIVE${T}read$"
  chk "$1 keeps merge-queue fact" "^merge_queue\\.applicability${T}N/A"
  chk "$1 keeps bypass fact" "^bypass\\.ruleset\\.101${T}ACTIVE"
}
invalid_profile_case() {
  local label="$1" payload="$2" first_out first_err
  baseline; mk_profile "$payload"; clear_calls
  run -R o/r
  rce "$label exits 3" 3
  chk "$label is deterministic UNKNOWN" "$PROFILE_UNKNOWN"
  get_once "$label performs exact plain variable GET"
  if [ -z "$err" ]; then t_ok "$label leaks no API stderr"; else t_fail "$label leaks no API stderr"; fi
  unknown_facts "$label"
  first_out="$out"; first_err="$err"; clear_calls
  run -R o/r
  if [ "$out" = "$first_out" ] && [ "$err" = "$first_err" ]; then
    t_ok "$label repeats deterministically"
  else
    t_fail "$label repeats deterministically"
  fi
  get_once "$label repeat performs exact plain variable GET"
}

baseline
run -R o/r --profile solo
rce "solo baseline is healthy" 0
if grep -q -- '--paginate repos/o/r/commits/main/check-runs?filter=latest&per_page=100' "$GH_CALLS"; then t_ok "check-run evidence is paginated and latest-filtered"; else t_fail "check-run evidence is paginated and latest-filtered"; fi
chk "default branch discovered" "^repository\.default_branch${T}ACTIVE${T}main$"
chk "declared profile echoed" "^governance\.profile${T}ACTIVE${T}solo$"
chk "approval count bypass-qualified" "^pull_request\.required_approving_review_count${T}ACTIVE${T}count=1 bypass=RepositoryRole:5:pull_request$"
chk "solo shows stale-review state without gating" "^pull_request\.dismiss_stale_reviews${T}OFF"
chk "context bypass-qualified" "^required_checks\.context\.quality${T}ACTIVE${T}required by effective rules bypass=RepositoryRole:5:pull_request$"
chk "check source informational for solo" "^required_check_source\.quality${T}N/A${T}configured=none observed=15368"
chk "actions permissions read" "^actions\.default_workflow_permissions${T}ACTIVE${T}read$"
chk "actions approve-reviews false" "^actions\.can_approve_pull_request_reviews${T}ACTIVE${T}false$"
chk "template codeowners not applicable" "^codeowners\.tuning${T}N/A${T}template tree"
chk "user-owned merge queue not applicable" "^merge_queue\.applicability${T}N/A${T}owner_type=User"
chk "bypass ruleset summarized" "^bypass\.ruleset\.101${T}ACTIVE${T}source=Repository:o/r actors=1$"
chk "bypass actor enumerated" "^bypass\.ruleset\.101\.actor\.1${T}ACTIVE${T}actor_type=RepositoryRole actor_id=5 bypass_mode=pull_request$"
if printf '%s\n' "$out" | awk -F"$T" 'NF != 3 { bad = 1 } END { exit bad }'; then t_ok "every line has exactly three tab-separated fields"; else t_fail "every line has exactly three tab-separated fields"; fi
if [ "$(printf '%s\n' "$out" | head -n 2 | cut -f1 | tr '\n' ' ')" = "repository.default_branch governance.profile " ]; then t_ok "key order is fixed"; else t_fail "key order is fixed"; fi
first="$out"
run -R o/r --profile solo
if [ "$first" = "$out" ]; then t_ok "output is deterministic across runs"; else t_fail "output is deterministic across runs"; fi

run -R o/r
rce "omitted profile exits 3, never guessed" 3
chk "omitted profile reported UNKNOWN" "^governance\.profile${T}UNKNOWN"

# Persisted intent must feed the exact existing profile semantics. Complete
# output, stderr, and exit-code equality guards ordering and detail as well.
baseline; clear_calls
run -R o/r --profile solo
save_run
mk_profile '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}'
clear_calls; run -R o/r
same_run "persisted solo equals healthy explicit solo"
chk "persisted solo is ACTIVE" "^governance\.profile${T}ACTIVE${T}solo$"
get_once "persisted solo uses one exact plain variable GET"
persisted_first="$out"; persisted_err="$err"; clear_calls; run -R o/r
if [ "$out" = "$persisted_first" ] && [ "$err" = "$persisted_err" ]; then
  t_ok "persisted solo output repeats deterministically"
else
  t_fail "persisted solo output repeats deterministically"
fi
get_once "persisted solo repeat uses one exact plain variable GET"

baseline; clear_calls
run -R o/r --profile team
save_run
mk_profile '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"team","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}'
clear_calls; run -R o/r
same_run "persisted team equals failing explicit team"
get_once "failing persisted team uses one exact plain variable GET"

team_green; clear_calls
run -R o/r --profile team
save_run
mk_profile '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"team","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}'
clear_calls; run -R o/r
same_run "persisted team equals healthy explicit team"
chk "persisted team is ACTIVE" "^governance\.profile${T}ACTIVE${T}team$"
get_once "healthy persisted team uses one exact plain variable GET"
persisted_first="$out"; persisted_err="$err"; clear_calls; run -R o/r
if [ "$out" = "$persisted_first" ] && [ "$err" = "$persisted_err" ]; then
  t_ok "persisted team output repeats deterministically"
else
  t_fail "persisted team output repeats deterministically"
fi
get_once "persisted team repeat uses one exact plain variable GET"

baseline; clear_calls
runf "actions/permissions" -R o/r --profile team
save_run
mk_profile '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"team"}'
clear_calls; runf "actions/permissions" -R o/r
same_run "persisted team preserves UNKNOWN-over-OFF precedence"
get_once "UNKNOWN-precedence run uses one exact plain variable GET"

# Endpoint failures are isolated from GS_FAIL so the rest of the report stays
# observable and deterministic.
for var_error in 404 actions-disabled unauthorized generic; do
  case "$var_error" in
    404) label="missing variable" ;;
    actions-disabled) label="Actions-disabled variable" ;;
    unauthorized) label="unauthorized variable" ;;
    generic) label="generic variable API failure" ;;
  esac
  baseline; clear_calls; runv "$var_error" -R o/r
  rce "$label exits 3" 3
  chk "$label is deterministic UNKNOWN" "$PROFILE_UNKNOWN"
  get_once "$label uses one exact plain variable GET"
  if [ -z "$err" ]; then t_ok "$label leaks no API stderr"; else t_fail "$label leaks no API stderr"; fi
  unknown_facts "$label"
  failure_first="$out"; failure_err="$err"; clear_calls
  runv "$var_error" -R o/r
  if [ "$out" = "$failure_first" ] && [ "$err" = "$failure_err" ]; then
    t_ok "$label repeats deterministically"
  else
    t_fail "$label repeats deterministically"
  fi
  get_once "$label repeat uses one exact plain variable GET"
done

# Only byte-exact JSON string values solo and team are valid. In particular,
# trailing JSON newlines must be rejected before command substitution can
# strip them.
while IFS='|' read -r invalid_name invalid_payload; do
  [ -n "$invalid_name" ] || continue
  invalid_profile_case "$invalid_name" "$invalid_payload"
done <<'INVALID_PROFILES'
malformed object|{
non-JSON payload|not-json
truncated value|{"value":
absent value|{}
name-only payload|{"name":"SCAFFOLD_GOVERNANCE_PROFILE"}
null value|{"value":null}
boolean value|{"value":true}
numeric value|{"value":0}
array value|{"value":[]}
object value|{"value":{}}
empty value|{"value":""}
leading space|{"value":" solo"}
trailing space|{"value":"solo "}
surrounding space|{"value":" team "}
leading tab|{"value":"\tsolo"}
trailing tab|{"value":"team\t"}
leading newline|{"value":"\nsolo"}
trailing solo newline|{"value":"solo\n"}
trailing team newline|{"value":"team\n"}
leading carriage return|{"value":"\rsolo"}
trailing solo carriage return|{"value":"solo\r"}
trailing team carriage return|{"value":"team\r"}
trailing CRLF|{"value":"solo\r\n"}
title-case solo|{"value":"Solo"}
upper-case solo|{"value":"SOLO"}
title-case team|{"value":"Team"}
upper-case team|{"value":"TEAM"}
arbitrary value|{"value":"pirate"}
solo prefix extension|{"value":"solos"}
team prefix extension|{"value":"teams"}
combined profiles|{"value":"solo team"}
numeric string|{"value":"0"}
boolean string|{"value":"true"}
INVALID_PROFILES

# Explicit profiles are one-shot overrides: the opposite persisted fixture is
# neither read nor modified, and no environment value becomes a fallback.
baseline
mk_profile '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"team"}'
profile_sum="$(cksum "$GS_FIX/profile.json")"; clear_calls
run -R o/r --profile solo
rce "explicit solo overrides persisted team" 0
chk "explicit solo remains ACTIVE" "^governance\.profile${T}ACTIVE${T}solo$"
get_never "explicit solo never reads persisted profile"
if [ "$(cksum "$GS_FIX/profile.json")" = "$profile_sum" ]; then t_ok "explicit solo does not persist"; else t_fail "explicit solo does not persist"; fi

team_green
mk_profile '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}'
profile_sum="$(cksum "$GS_FIX/profile.json")"; clear_calls
run -R o/r --profile team
rce "explicit team overrides persisted solo" 0
chk "explicit team remains ACTIVE" "^governance\.profile${T}ACTIVE${T}team$"
get_never "explicit team never reads persisted profile"
if [ "$(cksum "$GS_FIX/profile.json")" = "$profile_sum" ]; then t_ok "explicit team does not persist"; else t_fail "explicit team does not persist"; fi

baseline; clear_calls
rc=0
SCAFFOLD_GOVERNANCE_PROFILE=team bash "$SENSOR" -R o/r > "$WORK/stdout" 2> "$WORK/stderr" || rc=$?
out="$(cat "$WORK/stdout")"; err="$(cat "$WORK/stderr")"
rce "environment profile is not a fallback" 3
chk "environment profile cannot replace persisted evidence" "$PROFILE_UNKNOWN"
get_once "environment fallback attempt still performs exact variable GET"

run -R o/r --profile team
rce "solo baseline fails team intent" 1
chk "team gap: stale reviews OFF" "^pull_request\.dismiss_stale_reviews${T}OFF${T}false"
chk "team gap: unbound check source OFF" "^required_check_source\.quality${T}OFF${T}configured=none observed=15368$"

team_green
run -R o/r --profile team
rce "fully hardened team is healthy" 0
chk "bound check source matches observation" "^required_check_source\.quality${T}ACTIVE${T}configured=15368 observed=15368$"
chk "tuned codeowners ACTIVE" "^codeowners\.tuning${T}ACTIVE"
chk "no bypass suffix without actors" "^pull_request\.required_approving_review_count${T}ACTIVE${T}count=1$"
chk "empty bypass list stated" "^bypass\.ruleset\.101${T}ACTIVE${T}source=Repository:o/r actors=0$"
run -R o/r --profile solo
rce "stronger settings stay healthy for solo" 0

baseline
jq '. + [{"type":"pull_request","parameters":{"required_approving_review_count":2,
  "dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,
  "required_review_thread_resolution":false},"ruleset_source_type":"Organization","ruleset_source":"orgname","ruleset_id":900}]' \
  "$GS_FIX/rules.json" > "$GS_FIX/r.tmp" && mv "$GS_FIX/r.tmp" "$GS_FIX/rules.json"
mk_rs 900 org '[{"actor_id":42,"actor_type":"Integration","bypass_mode":"always"}]'
run -R o/r --profile solo
rce "parent ruleset aggregation stays healthy" 0
chk "strongest approval threshold wins across sources" "^pull_request\.required_approving_review_count${T}ACTIVE${T}count=2 bypass=RepositoryRole:5:pull_request,Integration:42:always$"
chk "organization bypass enumerated" "^bypass\.ruleset\.900${T}ACTIVE${T}source=Organization:orgname actors=1$"
if grep -q 'orgs/orgname/rulesets/900' "$GH_CALLS"; then t_ok "organization ruleset detail fetched via orgs endpoint"; else t_fail "organization ruleset detail fetched via orgs endpoint"; fi

baseline
runf "rulesets/101" -R o/r --profile solo
rce "failed ruleset detail read exits 3" 3
chk "failed detail read is UNKNOWN, never empty" "^bypass\.ruleset\.101${T}UNKNOWN${T}ruleset detail unavailable"
chk "controls flag unknown bypass evidence" "^pull_request\.required_approving_review_count${T}ACTIVE${T}count=1 bypass=unknown$"

team_green
team_rules 99999
run -R o/r --profile team
rce "configured-observed source mismatch fails team" 1
chk "source mismatch is OFF" "^required_check_source\.quality${T}OFF${T}configured=99999 observed=15368$"

team_green
mk_runs quality:15368 task-ritual:15368 scaffold-self-check:15368
run -R o/r --profile team
rce "absent check run exits 3" 3
chk "absent run is UNCHECKABLE" "^required_check_source\.copilot-surface${T}UNCHECKABLE${T}.*no check run observed"

team_green
mk_runs quality:15368 quality:222 task-ritual:15368 scaffold-self-check:15368 copilot-surface:15368
run -R o/r --profile team
rce "ambiguous issuers exit 3" 3
chk "multiple app ids are UNCHECKABLE" "^required_check_source\.quality${T}UNCHECKABLE${T}multiple issuing app ids: 222,15368$"

team_green
printf '%s\n%s\n' \
  '{"check_runs":[{"name":"task-ritual","app":{"id":15368}},{"name":"scaffold-self-check","app":{"id":15368}},{"name":"copilot-surface","app":{"id":15368}}]}' \
  '{"check_runs":[{"name":"quality","app":{"id":15368}}]}' > "$GS_FIX/checkruns.json"
run -R o/r --profile team
rce "paginated check-run evidence stays healthy" 0
chk "runs found only on a later page are observed" "^required_check_source\.quality${T}ACTIVE${T}configured=15368 observed=15368$"
printf '%s\n%s\n' '{"check_runs":[{"name":"quality","app":{"id":15368}}]}' \
  '{"check_runs":[{"name":"quality","app":{"id":222}}]}' > "$GS_FIX/checkruns.json"
run -R o/r --profile team
rce "cross-page issuer conflict exits 3" 3
chk "app ids union across pages before the source ruling" "^required_check_source\.quality${T}UNCHECKABLE${T}multiple issuing app ids: 222,15368$"

baseline
run -R o/r --profile solo --checks quality,ghost
rce "missing requested context fails solo" 1
chk "missing context is OFF" "^required_checks\.context\.ghost${T}OFF${T}not required by effective rules$"
run -R o/r --profile team --checks quality,ghost
rce "UNCHECKABLE evidence outranks OFF" 3

team_green
mk_co '# CUSTOMIZE: replace @owner'
run -R o/r --profile team
rce "adopted unresolved codeowners fails team" 1
chk "unresolved CUSTOMIZE is OFF" "^codeowners\.tuning${T}OFF${T}adopted tree with unresolved CUSTOMIZE ownership$"
rm -f "$GS_FIX/codeowners.raw"
run -R o/r --profile team
rce "absent codeowners on adopted tree fails team" 1
chk "absent codeowners is OFF" "^codeowners\.tuning${T}OFF${T}adopted tree without \.github/CODEOWNERS$"
runf "contents/.github/CODEOWNERS" -R o/r --profile team
rce "unreadable codeowners exits 3" 3
chk "unreadable codeowners is UNKNOWN" "^codeowners\.tuning${T}UNKNOWN${T}CODEOWNERS evidence unreadable$"
rm -f "$GS_FIX/changelog.raw"
run -R o/r --profile team
rce "missing scaffold marker exits 3" 3
chk "missing marker is UNKNOWN" "^codeowners\.tuning${T}UNKNOWN${T}scaffold marker unavailable"
baseline
mk_marker abc123
run -R o/r --profile solo
rce "unresolved codeowners does not gate solo" 0
chk "solo still shows codeowners OFF" "^codeowners\.tuning${T}OFF"

baseline; mk_repo Organization true; run -R o/r --profile solo
rce "private org without plan evidence fails closed" 3
chk "unavailable org plan is UNKNOWN" "^merge_queue\.applicability${T}UNKNOWN${T}organization plan evidence unavailable"
mk_org ''; run -R o/r --profile solo; rce "plan-less org payload stays unknown" 3; chk "absent plan field is UNKNOWN" "^merge_queue\.applicability${T}UNKNOWN${T}organization plan evidence unavailable"
jq '. + [{"type":"merge_queue","parameters":{},"ruleset_source_type":"Repository","ruleset_source":"o/r","ruleset_id":101}]' "$GS_FIX/rules.json" > "$GS_FIX/r.tmp" && mv "$GS_FIX/r.tmp" "$GS_FIX/rules.json"
mk_wfdir ci.yml; mk_wff ci.yml 'on: [pull_request, merge_group]'
mk_org ',"plan":{"name":"unknown"}'; run -R o/r --profile solo
rce "unrecognized org plan fails closed" 3; chk "unrecognized plan is UNKNOWN" "^merge_queue\.applicability${T}UNKNOWN${T}organization plan evidence unavailable"
for plan in free team; do
  mk_org ",\"plan\":{\"name\":\"$plan\"}"; run -R o/r --profile solo
  rce "private org $plan plan is provably ineligible" 0; chk "$plan plan stays N/A despite rule and coverage" "^merge_queue\.applicability${T}N/A${T}private repository plan=$plan is ineligible"
done
mk_org ',"plan":{"name":"enterprise"}'; run -R o/r --profile solo
rce "private enterprise org is eligible with complete evidence" 0; chk "enterprise org reaches ACTIVE" "^merge_queue\.applicability${T}ACTIVE${T}merge_queue rule active.*merge_group coverage in 1 workflow"
if grep -q '^api orgs/o$' "$GH_CALLS"; then t_ok "org plan evidence read via GET /orgs/{owner}"; else t_fail "org plan evidence read via GET /orgs/{owner}"; fi
mk_repo Organization false; run -R o/r --profile solo; rce "public org repository is eligible by repository evidence" 0; chk "effective merge_queue rule is ACTIVE" "^merge_queue\.applicability${T}ACTIVE${T}merge_queue rule active.*merge_group coverage in 1 workflow"
mk_wfdir ci.yml lint.yml; mk_wff ci.yml $'on:\n  merge_group:\n    branches: [main]'
mk_wff lint.yml $'on: [push]\njobs:\n  x:\n    steps:\n      - run: echo merge_group ready\nenv:\n  NOTE: merge_group'
run -R o/r --profile solo
rce "genuine trigger structure is the only coverage evidence" 0
chk "block-map trigger counts once; token noise never counts" "^merge_queue\.applicability${T}ACTIVE${T}merge_queue rule active.*merge_group coverage in 1 workflow"
mk_wff ci.yml 'on: [pull_request] # merge_group only in this comment'; run -R o/r --profile solo
rce "merge_queue rule without merge_group coverage exits 3" 3
chk "uncovered merge_queue rule is UNCHECKABLE" "^merge_queue\.applicability${T}UNCHECKABLE${T}merge_queue rule active without observed merge_group workflow coverage"
runf "contents/.github/workflows?" -R o/r --profile solo
rce "workflow listing failure exits 3" 3
chk "unreadable listing is UNKNOWN" "^merge_queue\.applicability${T}UNKNOWN${T}merge_group workflow coverage evidence unavailable"
runf "workflows/ci.yml" -R o/r --profile solo
rce "workflow content failure exits 3" 3
chk "unreadable workflow is UNKNOWN" "^merge_queue\.applicability${T}UNKNOWN${T}merge_group workflow coverage evidence unavailable"
rm -f "$GS_FIX/wfdir.json"; run -R o/r --profile solo
rce "absent workflow directory cannot certify coverage" 3
chk "absent workflows are UNCHECKABLE" "^merge_queue\.applicability${T}UNCHECKABLE${T}merge_queue rule active without observed merge_group workflow coverage"
solo_rules; run -R o/r --profile solo
rce "org unresolved applicability gates the declared profile" 3
chk "eligible org without rule is UNCHECKABLE" "^merge_queue\.applicability${T}UNCHECKABLE${T}eligible repository without a merge_queue rule"
runf "rules/branches" -R o/r --profile solo
rce "org effective-rule failure exits 3" 3
chk "org merge queue UNKNOWN without effective rules" "^merge_queue\.applicability${T}UNKNOWN${T}effective rules unavailable"

baseline
runf "rules/branches" -R o/r --profile solo
rce "effective-rules failure exits 3" 3
chk "rule facts become UNKNOWN" "^pull_request\.required_approving_review_count${T}UNKNOWN${T}effective rules unavailable$"
runf "actions/permissions" -R o/r --profile solo
rce "actions failure exits 3" 3
chk "actions posture UNKNOWN on failure" "^actions\.default_workflow_permissions${T}UNKNOWN"
runf "check-runs" -R o/r --profile team
rce "check-run failure exits 3 for team" 3
chk "check source UNKNOWN on API failure" "^required_check_source\.quality${T}UNKNOWN${T}.*check-run evidence unavailable"
runf "check-runs" -R o/r --profile solo
rce "check-run failure does not gate solo" 0
chk "solo source detail shows unknown observation" "^required_check_source\.quality${T}N/A${T}configured=none observed=unknown"
rm -f "$GS_FIX/repo.json"
run -R o/r --profile solo
rce "repository metadata failure exits 3" 3
chk "default branch UNKNOWN on failure" "^repository\.default_branch${T}UNKNOWN"

baseline
runf "actions/permissions" -R o/r --profile team
rce "missing evidence outranks OFF requirements" 3

run
rce "missing -R is a usage error" 2
run -R o/r --profile pirate
rce "invalid profile is a usage error" 2
run -R o/r --bogus
rce "unknown flag is a usage error" 2
run -R norepo --profile solo
rce "malformed repository is a usage error" 2
run -R o/r --profile solo --checks ,,,
rce "degenerate --checks list is a usage error" 2

if grep -q '^MUTATION' "$GH_CALLS"; then t_fail "sensor performed GET-only gh calls"; grep '^MUTATION' "$GH_CALLS" | sed 's/^/    # /'; else t_ok "sensor performed GET-only gh calls"; fi
if grep -Ev '^api ' "$GH_CALLS" | grep -q .; then t_fail "every gh invocation is a plain gh api read"; else t_ok "every gh invocation is a plain gh api read"; fi
rc=0
"$WORK/bin/gh" api -X DELETE repos/o/r/rulesets/1 >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 64 ] && grep -q '^MUTATION' "$GH_CALLS"; then t_ok "shim wall refuses mutating invocations"; else t_fail "shim wall refuses mutating invocations (rc=$rc)"; fi
wall=ok
for bad in --method=DELETE -XDELETE -fk=v -F=k=v --field=k=v --raw-field=k=v --input=p.json PATCH; do
  rc=0; "$WORK/bin/gh" api "$bad" repos/o/r >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] || wall="leaks $bad"
done
if [ "$wall" = ok ]; then t_ok "shim wall refuses equals-form and attached mutating flags"; else t_fail "shim wall refuses equals-form and attached mutating flags ($wall)"; fi

wall_case() {
  local label="$1"
  shift; clear_calls; rc=0
  "$WORK/bin/gh" "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 64 ] && grep -q '^MUTATION ' "$GH_CALLS"; then
    t_ok "$label"
  else
    t_fail "$label (rc=$rc)"
  fi
}
wall_case "wall refuses POST verb" api POST repos/o/r
wall_case "wall refuses PUT verb" api PUT repos/o/r
wall_case "wall refuses PATCH verb" api PATCH repos/o/r
wall_case "wall refuses DELETE verb" api DELETE repos/o/r
wall_case "wall refuses attached -XPOST" api -XPOST repos/o/r
wall_case "wall refuses split -X PUT" api -X PUT repos/o/r
wall_case "wall refuses equals --method=PATCH" api --method=PATCH repos/o/r
wall_case "wall refuses split --method DELETE" api --method DELETE repos/o/r
wall_case "wall refuses attached -f field" api -fk=v repos/o/r
wall_case "wall refuses attached -F field" api -Fkey=value repos/o/r
wall_case "wall refuses equals --field" api --field=k=v repos/o/r
wall_case "wall refuses split --raw-field" api --raw-field k=v repos/o/r
wall_case "wall refuses equals --input" api --input=p.json repos/o/r
wall_case "wall refuses variable creation" api POST repos/o/r/actions/variables
wall_case "wall refuses variable update" api PATCH repos/o/r/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE
wall_case "wall refuses variable deletion" api DELETE repos/o/r/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE
wall_case "wall refuses ruleset update" api PUT repos/o/r/rulesets/1
wall_case "wall refuses ruleset deletion" api DELETE repos/o/r/rulesets/1
wall_case "wall refuses issue edit" api PATCH repos/o/r/issues/109
wall_case "wall refuses workflow dispatch" api POST repos/o/r/actions/workflows/ci.yml/dispatches

baseline
(cd "$WORK/cwd" && bash "$SENSOR" -R o/r --profile solo >/dev/null 2>&1)
if [ -z "$(ls -A "$WORK/cwd")" ]; then t_ok "sensor persists no profile or file state"; else t_fail "sensor persists no profile or file state"; fi

t_summary
