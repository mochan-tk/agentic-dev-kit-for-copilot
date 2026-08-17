#!/usr/bin/env bash
# test-setup-ruleset.sh — regression tests for setup-ruleset.sh: usage
# errors, the write-free dry-run, fresh creation (payload carries the
# admin PR-only bypass), the exists-same-enforcement skip, the
# exists-different-enforcement PUT promotion (#187), and the fail-loud
# list. Sandboxed: a recording gh PATH stub — no network, no auth.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"
SCRIPT="$HERE/../setup-ruleset.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Recording stub: every invocation lands in $GH_CALLS. Missing fixtures fail;
# a `.missing` marker returns a proven 404. Write-failure markers are explicit.
export GH_FIXTURES="$WORK/fixtures"
export GH_CALLS="$WORK/gh-calls.log"
mkdir -p "$GH_FIXTURES" "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
case "$*" in
  "api user --jq .login") echo someone ;;
  "api repos/"*"/rulesets")
    [ -f "$GH_FIXTURES/rulesets.json" ] || exit 1
    cat "$GH_FIXTURES/rulesets.json" ;;
  "api repos/"*"/commits/"*"/check-runs?filter=latest&per_page=100 --paginate --slurp"|"api --paginate --slurp repos/"*"/commits/"*"/check-runs?filter=latest&per_page=100")
    [ ! -f "$GH_FIXTURES/check-runs.forbidden" ] \
      || { echo "gh: Forbidden (HTTP 403)" >&2; exit 1; }
    [ -f "$GH_FIXTURES/check-runs.json" ] || exit 1
    cat "$GH_FIXTURES/check-runs.json" ;;
  "api repos/"*"/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE")
    if [ -f "$GH_FIXTURES/variable.json" ]; then cat "$GH_FIXTURES/variable.json"
    elif [ -f "$GH_FIXTURES/variable.missing" ]; then
      echo "gh: Not Found (HTTP 404)" >&2; exit 1
    else echo "gh: Forbidden (HTTP 403)" >&2; exit 1; fi ;;
  "api repos/"*"/actions/variables?per_page=100")
    [ -f "$GH_FIXTURES/variables.json" ] || exit 1
    cat "$GH_FIXTURES/variables.json" ;;
  "api repos/"*)
    [ -f "$GH_FIXTURES/repo.json" ] || exit 1
    cat "$GH_FIXTURES/repo.json" ;;
  "api --method PUT repos/"*"/rulesets/"*) echo '{}' ;;
  "api --method POST repos/"*"/actions/variables -f name=SCAFFOLD_GOVERNANCE_PROFILE -f value="*)
    [ ! -f "$GH_FIXTURES/variable-write.fail" ] || exit 1
    printf '%s\n' "$*" > "$GH_FIXTURES/variable-write.txt" ;;
  "api --method PATCH repos/"*"/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE -f name=SCAFFOLD_GOVERNANCE_PROFILE -f value="*)
    [ ! -f "$GH_FIXTURES/variable-write.fail" ] || exit 1
    printf '%s\n' "$*" > "$GH_FIXTURES/variable-write.txt" ;;
  "api --method POST repos/"*"/rulesets --input -")
    cat > "$GH_FIXTURES/posted.json"
    [ ! -f "$GH_FIXTURES/ruleset-write.fail" ] || exit 1
    echo '{"id": 999}' ;;
  *) echo "gh stub: unsupported invocation: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

reset_calls() {
  : > "$GH_CALLS"
  rm -f "$GH_FIXTURES/variable.json" \
    "$GH_FIXTURES/variable.missing" "$GH_FIXTURES/variables.json" \
    "$GH_FIXTURES/variable-write.fail" "$GH_FIXTURES/variable-write.txt" \
    "$GH_FIXTURES/ruleset-write.fail" "$GH_FIXTURES/repo.json" \
    "$GH_FIXTURES/check-runs.json" "$GH_FIXTURES/check-runs.forbidden" \
    "$GH_FIXTURES/posted.json"
}

valid_team() {
  echo '{"default_branch":"main"}' > "$GH_FIXTURES/repo.json"
  cat > "$GH_FIXTURES/check-runs.json" <<'JSON'
[{"check_runs":[
  {"name":"quality","app":{"id":77}},{"name":"task-ritual","app":{"id":77}}
]},{"check_runs":[
  {"name":"scaffold-self-check","app":{"id":77}},
  {"name":"copilot-surface","app":{"id":77}}
]}]
JSON
}

assert_no_writes() {
  if ! grep -Eq -- '--method (POST|PUT|PATCH|DELETE)' "$GH_CALLS"; then
    t_ok "$1"
  else
    t_fail "$1"; sed 's/^/    # /' "$GH_CALLS"
  fi
}

run_script() { bash "$SCRIPT" "$@" < /dev/null; }

# --- usage ----------------------------------------------------------------

expect_rc 0 "recording gh authenticates by default" gh api user --jq .login
expect_rc_grep 0 'Usage: setup-ruleset\.sh' "--help prints usage" \
  run_script --help
expect_rc_grep 2 'unknown argument' "unknown flag is a usage error" \
  run_script --bogus
expect_rc_grep 2 "must be 'active' or 'disabled'" \
  "invalid --enforcement is a usage error" \
  run_script --enforcement sometimes
expect_rc_grep 2 "profile.*solo.*team" "invalid profile is a usage error" \
  run_script --profile enterprise

# --- dry-run: valid payload, zero gh calls ---------------------------------

reset_calls
PAYLOAD="$(run_script --dry-run 2>/dev/null)"
if printf '%s' "$PAYLOAD" | jq -e '
     .enforcement == "disabled"
     and .bypass_actors == [{actor_id: 5, actor_type: "RepositoryRole",
                             bypass_mode: "pull_request"}]
     and ([.rules[].type] == ["pull_request", "required_status_checks"])
   ' >/dev/null; then
  t_ok "dry-run payload carries the admin PR-only bypass and both rules"
else
  t_fail "dry-run payload carries the admin PR-only bypass and both rules"
  printf '%s\n' "$PAYLOAD" | sed 's/^/    # /'
fi
if [ ! -s "$GH_CALLS" ]; then
  t_ok "dry-run makes no gh calls"
else
  t_fail "dry-run makes no gh calls"
  sed 's/^/    # /' "$GH_CALLS"
fi

reset_calls
SOLO="$(run_script --profile solo --dry-run 2>/dev/null || true)"
if printf '%s' "$SOLO" | jq -e '
  all(.rules[] | select(.type == "pull_request").parameters;
    (.dismiss_stale_reviews_on_push or .require_last_push_approval
     or .require_code_owner_review or .required_review_thread_resolution) | not)
  and all(.rules[] | select(.type == "required_status_checks").parameters;
    .strict_required_status_checks_policy | not)
' >/dev/null; then t_ok "solo dry-run is the current solo payload"
else t_fail "solo dry-run is the current solo payload"; fi
assert_no_writes "solo dry-run makes no mutation"

reset_calls; valid_team
TEAM="$(run_script -R acme/widget --profile team --dry-run 2>/dev/null || true)"
if printf '%s' "$TEAM" | jq -e '
  ([.rules[] | select(.type == "required_status_checks")
    | .parameters.required_status_checks[].integration_id] == [77,77,77,77])
  and all(.rules[] | select(.type == "pull_request").parameters;
    .dismiss_stale_reviews_on_push and .require_last_push_approval
    and .require_code_owner_review and .required_review_thread_resolution)
  and all(.rules[] | select(.type == "required_status_checks").parameters;
    .strict_required_status_checks_policy)
' >/dev/null; then t_ok "team dry-run is source-bound and enables team controls"
else t_fail "team dry-run is source-bound and enables team controls"; fi
assert_no_writes "team dry-run uses GET-only discovery"

# --- fresh create -----------------------------------------------------------

reset_calls
echo '[]' > "$GH_FIXTURES/rulesets.json"
rm -f "$GH_FIXTURES/posted.json"
expect_rc_grep 0 "Created ruleset 'scaffold-branch-protection' \(id: 999" \
  "fresh repository: ruleset is POSTed" \
  run_script -R acme/widget --enforcement active
if jq -e '
     .enforcement == "active"
     and .bypass_actors[0].bypass_mode == "pull_request"
   ' "$GH_FIXTURES/posted.json" >/dev/null; then
  t_ok "POSTed body carries requested enforcement and the bypass actor"
else
  t_fail "POSTed body carries requested enforcement and the bypass actor"
fi

# --- explicit profiles: discovery, persistence, and ordering ----------------

reset_calls
echo '[{"id":42,"name":"scaffold-branch-protection","enforcement":"disabled"}]' > "$GH_FIXTURES/rulesets.json"
expect_rc_grep 1 'reconciliation.*required' "explicit profile rejects same-name ruleset" \
  run_script -R acme/widget --profile solo
assert_no_writes "same-name explicit profile performs no write"

reset_calls; echo '[]' > "$GH_FIXTURES/rulesets.json"; touch "$GH_FIXTURES/variable.missing"
echo '{"variables":[]}' > "$GH_FIXTURES/variables.json"
expect_rc_grep 0 "Created ruleset" "absent variable is created before solo ruleset" \
  run_script -R acme/widget --profile solo
if sed -n '1p;2p;3p;4p;5p' "$GH_CALLS" | grep -q \
  $'api user --jq .login\napi repos/acme/widget/rulesets\napi repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE\napi repos/acme/widget/actions/variables?per_page=100\napi --method POST repos/acme/widget/actions/variables'; then
  t_ok "solo reads precede variable creation and ruleset POST"
else t_fail "solo reads precede variable creation and ruleset POST"; sed 's/^/    # /' "$GH_CALLS"; fi

reset_calls; valid_team
echo '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}' > "$GH_FIXTURES/variable.json"
expect_rc_grep 0 "Created ruleset" "existing variable is updated before team ruleset" \
  run_script -R acme/widget --profile team
if grep -q -- 'value=team' "$GH_FIXTURES/variable-write.txt" \
   && [ "$(grep -n -- '--method PATCH\|--method POST repos/.*/rulesets' "$GH_CALLS" | cut -d: -f1 | paste -sd, -)" = "6,7" ]; then
  t_ok "team completes auth/list/discovery/variable reads before ordered writes"
else t_fail "team completes auth/list/discovery/variable reads before ordered writes"; sed 's/^/    # /' "$GH_CALLS"; fi

team_failure() {
  local name="$1" runs="$2"
  reset_calls; echo '{"default_branch":"main"}' > "$GH_FIXTURES/repo.json"
  printf '%s\n' "$runs" > "$GH_FIXTURES/check-runs.json"
  expect_rc_grep 1 'check.*evidence|App ID|discover' "$name" \
    run_script -R acme/widget --profile team --dry-run
  assert_no_writes "$name performs no write"
}
team_failure "missing context fails closed" \
  '[{"check_runs":[{"name":"quality","app":{"id":77}}]}]'
team_failure "ambiguous issuer fails closed" \
  '[{"check_runs":[{"name":"quality","app":{"id":77}},{"name":"quality","app":{"id":88}},{"name":"task-ritual","app":{"id":77}},{"name":"scaffold-self-check","app":{"id":77}},{"name":"copilot-surface","app":{"id":77}}]}]'
team_failure "mixed issuers fail closed" \
  '[{"check_runs":[{"name":"quality","app":{"id":77}},{"name":"task-ritual","app":{"id":77}},{"name":"scaffold-self-check","app":{"id":88}},{"name":"copilot-surface","app":{"id":88}}]}]'
team_failure "malformed issuer fails closed" \
  '[{"check_runs":[{"name":"quality","app":{"id":"77"}},{"name":"task-ritual","app":{"id":77}},{"name":"scaffold-self-check","app":{"id":77}},{"name":"copilot-surface","app":{"id":77}}]}]'

reset_calls; echo '{"default_branch":"main"}' > "$GH_FIXTURES/repo.json"
expect_rc_grep 1 'check.*runs|discover' "check-run API failure fails closed" \
  run_script -R acme/widget --profile team --dry-run
assert_no_writes "check-run API failure performs no write"
reset_calls; valid_team; touch "$GH_FIXTURES/check-runs.forbidden"
expect_rc_grep 1 'check.*runs|discover' "check-run authorization failure fails closed" \
  run_script -R acme/widget --profile team --dry-run
assert_no_writes "check-run authorization failure performs no write"

for mode in read create update; do
  reset_calls
  case "$mode" in
    read) : ;;
    create) touch "$GH_FIXTURES/variable.missing" "$GH_FIXTURES/variable-write.fail"; echo '{"variables":[]}' > "$GH_FIXTURES/variables.json" ;;
    update) echo '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}' > "$GH_FIXTURES/variable.json"; touch "$GH_FIXTURES/variable-write.fail" ;;
  esac
  expect_rc_grep 1 'variable' "variable $mode failure stops ruleset creation" \
    run_script -R acme/widget --profile solo
  [ ! -f "$GH_FIXTURES/posted.json" ] && t_ok "variable $mode failure causes zero ruleset POSTs" \
    || t_fail "variable $mode failure causes zero ruleset POSTs"
done

reset_calls; echo '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}' > "$GH_FIXTURES/variable.json"
touch "$GH_FIXTURES/ruleset-write.fail"
expect_rc_grep 1 'ruleset.*creat' "ruleset-create failure is distinct" \
  run_script -R acme/widget --profile solo
if ! grep -q -- '--method DELETE' "$GH_CALLS"; then t_ok "no path creates or deletes probe rulesets"
else t_fail "no path creates or deletes probe rulesets"; fi

# --- exists, same enforcement: skip, no writes ------------------------------

reset_calls
echo '[{"id": 42, "name": "scaffold-branch-protection", "enforcement": "disabled"}]' \
  > "$GH_FIXTURES/rulesets.json"
expect_rc_grep 0 'already exists .* skipping creation' \
  "same-name same-enforcement ruleset is skipped" \
  run_script -R acme/widget --enforcement disabled
if ! grep -Eq -- '--method (PUT|POST)' "$GH_CALLS"; then
  t_ok "skip path performs no write calls"
else
  t_fail "skip path performs no write calls"
  sed 's/^/    # /' "$GH_CALLS"
fi

# --- exists, different enforcement: PUT promotion (#187) --------------------

reset_calls
expect_rc_grep 0 "Updated ruleset 'scaffold-branch-protection' \(id: 42\).*disabled -> active" \
  "disabled ruleset is promoted in place when active is requested" \
  run_script -R acme/widget --enforcement active
if grep -q -- '--method PUT repos/acme/widget/rulesets/42' "$GH_CALLS" \
   && ! grep -q -- '--method POST' "$GH_CALLS"; then
  t_ok "promotion is a PUT to the existing id, never a duplicate POST"
else
  t_fail "promotion is a PUT to the existing id, never a duplicate POST"
  sed 's/^/    # /' "$GH_CALLS"
fi

reset_calls
echo '[{"id": 42, "name": "scaffold-branch-protection", "enforcement": "active"}]' \
  > "$GH_FIXTURES/rulesets.json"
expect_rc_grep 0 'disabled' "active ruleset is demotable back to disabled" \
  run_script -R acme/widget --enforcement disabled

# --- failed list: abort before any creation ---------------------------------

reset_calls
rm -f "$GH_FIXTURES/rulesets.json"
expect_rc_grep 1 'could not list rulesets' \
  "failed ruleset list aborts before any write" \
  run_script -R acme/widget
if ! grep -Eq -- '--method (PUT|POST)' "$GH_CALLS"; then
  t_ok "failed list performs no write calls"
else
  t_fail "failed list performs no write calls"
  sed 's/^/    # /' "$GH_CALLS"
fi

t_summary
