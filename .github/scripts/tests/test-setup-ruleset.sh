#!/usr/bin/env bash
# test-setup-ruleset.sh — regression tests for setup-ruleset.sh: usage
# errors, the write-free dry-run, fresh creation (payload carries the
# admin PR-only bypass), the exists-same-enforcement skip, the
# exists-different-enforcement PUT promotion (#187), and the fail-loud
# list, plus opt-in solo/team profiles and fail-closed source discovery.
# Sandboxed: a recording gh PATH stub — no network, no auth.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"
SCRIPT="$HERE/../setup-ruleset.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Recording stub: every invocation lands in $GH_CALLS (one line of argv per
# call); list responses come from $GH_FIXTURES/rulesets.json (absent file
# models a failed list); a POST body is captured to $GH_FIXTURES/posted.json.
export GH_FIXTURES="$WORK/fixtures"
export GH_CALLS="$WORK/gh-calls.log"
export GH_ALL_CALLS="$WORK/gh-all-calls.log"
mkdir -p "$GH_FIXTURES" "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
printf '%s\n' "$*" >> "$GH_ALL_CALLS"
[ "${GH_FAIL_EXACT:-}" != "$*" ] \
  || { echo "${GH_FAIL_MESSAGE:-gh: HTTP 500 (simulated)}" >&2; exit 1; }
for frag in ${GH_FAIL:-}; do
  case "$*" in
    *"$frag"*) echo "${GH_FAIL_MESSAGE:-gh: HTTP 500 (simulated)}" >&2; exit 1 ;;
  esac
done
case "$*" in
  "api user --jq .login") echo someone ;;
  "api repos/"*"/commits/"*"/check-runs?filter=latest&per_page=100 --paginate"|"api --paginate repos/"*"/commits/"*"/check-runs?filter=latest&per_page=100")
    cat "$GH_FIXTURES/checkruns.json" ;;
  "api repos/"*"/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE")
    case "${GH_VARIABLE:-present}" in
      missing) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      *) cat "$GH_FIXTURES/variable.json" ;;
    esac ;;
  "api --method POST repos/"*"/actions/variables --input -")
    cat > "$GH_FIXTURES/variable-written.json"; echo '{}' ;;
  "api --method PATCH repos/"*"/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE --input -")
    cat > "$GH_FIXTURES/variable-written.json"; echo '{}' ;;
  "api repos/"*"/rulesets")
    [ -f "$GH_FIXTURES/rulesets.json" ] || exit 1
    cat "$GH_FIXTURES/rulesets.json" ;;
  "api --method PUT repos/"*"/rulesets/"*) echo '{}' ;;
  "api --method POST repos/"*"/rulesets --input -")
    cat > "$GH_FIXTURES/posted.json"; echo '{"id": 999}' ;;
  "api repos/"*)
    cat "$GH_FIXTURES/repo.json" ;;
  *) echo "gh stub: unsupported invocation: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

reset_calls() { : > "$GH_CALLS"; }

run_script() { bash "$SCRIPT" "$@" < /dev/null; }

no_profile_writes() {
  ! grep -Eq -- '--method (POST|PUT|PATCH).*(actions/variables|rulesets)' "$GH_CALLS"
}

profile_fixtures() {
  reset_calls
  unset GH_FAIL GH_FAIL_EXACT GH_FAIL_MESSAGE
  export GH_VARIABLE=missing
  rm -f "$GH_FIXTURES/variable.json" "$GH_FIXTURES/variable-written.json" \
    "$GH_FIXTURES/posted.json"
  echo '[]' > "$GH_FIXTURES/rulesets.json"
  echo '{"default_branch":"trunk"}' > "$GH_FIXTURES/repo.json"
  cat > "$GH_FIXTURES/checkruns.json" <<'JSON'
{"check_runs":[
  {"name":"quality","app":{"id":15368}},
  {"name":"task-ritual","app":{"id":15368}},
  {"name":"scaffold-self-check","app":{"id":15368}},
  {"name":"copilot-surface","app":{"id":15368}}
]}
JSON
}

team_fails_closed() {
  local name="$1" pattern="$2" rc=0 out
  out="$(run_script -R acme/widget --profile team 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] \
     && printf '%s\n' "$out" | grep -Eqi "$pattern" \
     && no_profile_writes; then
    t_ok "$name"
  else
    t_fail "$name (rc=$rc; expected failure before writes)"
    printf '%s\n' "$out" | sed 's/^/    # /'
    sed 's/^/    # call: /' "$GH_CALLS"
  fi
}

# --- usage ----------------------------------------------------------------

expect_rc_grep 0 'Usage: setup-ruleset\.sh' "--help prints usage" \
  run_script --help
expect_rc_grep 2 'unknown argument' "unknown flag is a usage error" \
  run_script --bogus
expect_rc_grep 2 "must be 'active' or 'disabled'" \
  "invalid --enforcement is a usage error" \
  run_script --enforcement sometimes
expect_rc_grep 2 "profile.*solo.*team" \
  "invalid --profile is a usage error" \
  run_script --profile pirate

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

# --- explicit profiles: dry-run candidates and fresh writes ----------------

profile_fixtures
rc=0
SOLO="$(run_script -R acme/widget --profile solo --dry-run 2>/dev/null)" || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$SOLO" | jq -e '
     .rules[] | select(.type == "pull_request") | .parameters
     | (.dismiss_stale_reviews_on_push == false
        and .require_last_push_approval == false
        and .require_code_owner_review == false
        and .required_review_thread_resolution == false)
   ' >/dev/null && [ ! -s "$GH_CALLS" ]; then
  t_ok "explicit solo dry-run prints the legacy payload with zero gh calls"
else
  t_fail "explicit solo dry-run prints the legacy payload with zero gh calls"
fi

profile_fixtures
rc=0
TEAM="$(run_script -R acme/widget --profile team --dry-run 2>/dev/null)" || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$TEAM" | jq -e '
     all(.rules[] | select(.type == "pull_request").parameters;
       .dismiss_stale_reviews_on_push and .require_last_push_approval
       and .require_code_owner_review and .required_review_thread_resolution)
     and all(.rules[] | select(.type == "required_status_checks").parameters;
       .strict_required_status_checks_policy
       and all(.required_status_checks[]; .integration_id == 15368))
   ' >/dev/null \
   && grep -Eq -- 'commits/trunk/check-runs\?filter=latest&per_page=100.*--paginate' "$GH_CALLS" \
   && no_profile_writes; then
  t_ok "team dry-run uses paginated GET evidence and prints a bound candidate"
else
  t_fail "team dry-run uses paginated GET evidence and prints a bound candidate"
fi

profile_fixtures
expect_rc_grep 0 "Created ruleset 'scaffold-branch-protection'" \
  "fresh explicit solo persists intent before creating the ruleset" \
  run_script -R acme/widget --profile solo
if jq -e '.name == "SCAFFOLD_GOVERNANCE_PROFILE" and .value == "solo"' \
     "$GH_FIXTURES/variable-written.json" >/dev/null \
   && [ "$(grep -nE 'actions/variables|--method POST .*rulesets' "$GH_CALLS" \
             | cut -d: -f2-)" = "$(printf '%s\n' \
       'api repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE' \
       'api --method POST repos/acme/widget/actions/variables --input -' \
       'api --method POST repos/acme/widget/rulesets --input -')" ]; then
  t_ok "explicit solo reads then writes intent before the ruleset POST"
else
  t_fail "explicit solo reads then writes intent before the ruleset POST"
  sed 's/^/    # /' "$GH_CALLS"
fi

profile_fixtures
expect_rc 0 "fresh team profile creates from complete common issuer evidence" \
  run_script -R acme/widget --profile team
if jq -e '
     ([.rules[] | select(.type == "required_status_checks")
       | .parameters.required_status_checks[].integration_id] | unique) == [15368]
   ' "$GH_FIXTURES/posted.json" >/dev/null \
   && jq -e '.value == "team"' "$GH_FIXTURES/variable-written.json" >/dev/null; then
  t_ok "team payload binds every context and persists exact team intent"
else
  t_fail "team payload binds every context and persists exact team intent"
fi

# --- explicit profiles: refusal, discovery, and persistence failures --------

profile_fixtures
echo '[{"id":42,"name":"scaffold-branch-protection","enforcement":"disabled"}]' \
  > "$GH_FIXTURES/rulesets.json"
expect_rc_grep 1 'reconciliation|required.*existing' \
  "explicit profile refuses an existing same-name ruleset" \
  run_script -R acme/widget --profile solo
if grep -q -- 'api repos/acme/widget/rulesets' "$GH_CALLS" \
   && no_profile_writes; then
  t_ok "same-name refusal happens before all profile writes"
else
  t_fail "same-name refusal happens before all profile writes"
fi

profile_fixtures
export GH_FAIL_EXACT='api repos/acme/widget'
team_fails_closed "repository metadata failure blocks team before writes" \
  'repository|metadata'

profile_fixtures
export GH_FAIL='check-runs'
team_fails_closed "check-run API failure blocks team before writes" 'check.run'

issuer_case=0
issuer_names=(
  "missing requested contexts fail closed"
  "multiple issuers for one context fail closed"
  "different issuers across contexts fail closed"
  "numeric plus null evidence fails closed"
  "numeric plus malformed evidence fails closed"
)
for fixture in \
  '[{"name":"quality","app":{"id":15368}}]' \
  '[{"name":"quality","app":{"id":15368}},{"name":"quality","app":{"id":42}},{"name":"task-ritual","app":{"id":15368}},{"name":"scaffold-self-check","app":{"id":15368}},{"name":"copilot-surface","app":{"id":15368}}]' \
  '[{"name":"quality","app":{"id":15368}},{"name":"task-ritual","app":{"id":42}},{"name":"scaffold-self-check","app":{"id":15368}},{"name":"copilot-surface","app":{"id":15368}}]' \
  '[{"name":"quality","app":{"id":15368}},{"name":"quality","app":{"id":null}},{"name":"task-ritual","app":{"id":15368}},{"name":"scaffold-self-check","app":{"id":15368}},{"name":"copilot-surface","app":{"id":15368}}]' \
  '[{"name":"quality","app":{"id":15368}},{"name":"quality","app":{"id":"bad"}},{"name":"task-ritual","app":{"id":15368}},{"name":"scaffold-self-check","app":{"id":15368}},{"name":"copilot-surface","app":{"id":15368}}]'
do
  profile_fixtures
  printf '{"check_runs":%s}\n' "$fixture" > "$GH_FIXTURES/checkruns.json"
  team_fails_closed "${issuer_names[$issuer_case]}" 'issuer|evidence|context'
  issuer_case=$((issuer_case + 1))
done

profile_fixtures
export GH_FAIL='actions/variables/SCAFFOLD_GOVERNANCE_PROFILE'
team_fails_closed "unreadable variable endpoint blocks ruleset creation" \
  'variable|Actions'

profile_fixtures
export GH_FAIL='actions/variables/SCAFFOLD_GOVERNANCE_PROFILE'
export GH_FAIL_MESSAGE='gh: Actions are disabled (HTTP 409)'
team_fails_closed "Actions-disabled target blocks ruleset creation" \
  'variable|Actions'

profile_fixtures
export GH_FAIL_EXACT='api --method POST repos/acme/widget/actions/variables --input -'
team_fails_closed "variable create failure blocks ruleset creation" 'variable'

profile_fixtures
export GH_VARIABLE=present
echo '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}' \
  > "$GH_FIXTURES/variable.json"
expect_rc 0 "existing intent is updated before fresh team creation" \
  run_script -R acme/widget --profile team
if grep -q -- '--method PATCH repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE' \
     "$GH_CALLS" \
   && ! grep -q -- '--method POST repos/acme/widget/actions/variables' "$GH_CALLS" \
   && jq -e '.value == "team"' "$GH_FIXTURES/variable-written.json" >/dev/null; then
  t_ok "existing intent uses PATCH with the exact selected value"
else
  t_fail "existing intent uses PATCH with the exact selected value"
fi

profile_fixtures
export GH_VARIABLE=present
echo '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}' \
  > "$GH_FIXTURES/variable.json"
export GH_FAIL_EXACT='api --method PATCH repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE --input -'
team_fails_closed "variable update failure blocks ruleset creation" 'variable'

profile_fixtures
export GH_FAIL_EXACT='api --method POST repos/acme/widget/rulesets --input -'
expect_rc_grep 1 'ruleset.*creat|create.*ruleset' \
  "ruleset-create failure is reported distinctly" \
  run_script -R acme/widget --profile team
if grep -q -- '--method POST repos/acme/widget/actions/variables' "$GH_CALLS"; then
  t_ok "ruleset-create failure occurs only after intent persistence"
else
  t_fail "ruleset-create failure occurs only after intent persistence"
fi

if grep -Eq -- 'DELETE|probe' "$GH_ALL_CALLS"; then
  t_fail "fixture wall rejects DELETE and temporary probes"
else
  t_ok "fixture wall observes no DELETE or temporary probes"
fi

t_summary
