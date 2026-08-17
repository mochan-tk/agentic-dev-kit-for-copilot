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
# call); responses come from fixed files under $GH_FIXTURES; request bodies
# are captured so reconciliation shape and write ordering stay observable.
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
  "api --method PUT repos/"*"/rulesets/"*" --input -")
    cat > "$GH_FIXTURES/put.json"; echo '{"id":42}' ;;
  "api repos/"*"/rulesets")
    [ -f "$GH_FIXTURES/rulesets.json" ] || exit 1
    cat "$GH_FIXTURES/rulesets.json" ;;
  "api repos/"*"/rulesets/"*)
    [ -f "$GH_FIXTURES/ruleset-detail.json" ] || exit 1
    cat "$GH_FIXTURES/ruleset-detail.json" ;;
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
  ! grep -Eq -- '--method (POST|PUT|PATCH|DELETE).*(actions/variables|rulesets)' "$GH_CALLS"
}

profile_fixtures() {
  reset_calls
  unset GH_FAIL GH_FAIL_EXACT GH_FAIL_MESSAGE
  export GH_VARIABLE=missing
  rm -f "$GH_FIXTURES/variable.json" "$GH_FIXTURES/variable-written.json" \
    "$GH_FIXTURES/posted.json" "$GH_FIXTURES/put.json" \
    "$GH_FIXTURES/ruleset-detail.json"
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

canonical_detail() {
  local profile="$1" enforcement="${2:-disabled}" app="${3:-15368}"
  jq -n --arg profile "$profile" --arg enforcement "$enforcement" \
    --argjson app "$app" '{
      id: 42, name: "scaffold-branch-protection", target: "branch",
      enforcement: $enforcement,
      bypass_actors: [{actor_id: 5, actor_type: "RepositoryRole",
                       bypass_mode: "pull_request"}],
      conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
      rules: [
        {type: "pull_request", parameters: {
          required_approving_review_count: 1,
          dismiss_stale_reviews_on_push: ($profile == "team"),
          require_code_owner_review: ($profile == "team"),
          require_last_push_approval: ($profile == "team"),
          required_review_thread_resolution: ($profile == "team")}},
        {type: "required_status_checks", parameters: {
          strict_required_status_checks_policy: ($profile == "team"),
          required_status_checks:
            (["quality","task-ritual","scaffold-self-check","copilot-surface"]
             | map({context: .})
             | if $profile == "team"
               then map(. + {integration_id: $app}) else . end)}}
      ]
    }'
}

existing_profile_fixtures() {
  local profile="$1" enforcement="${2:-disabled}" app="${3:-15368}"
  profile_fixtures
  printf '[{"id":42,"name":"scaffold-branch-protection","enforcement":"%s"}]\n' \
    "$enforcement" > "$GH_FIXTURES/rulesets.json"
  canonical_detail "$profile" "$enforcement" "$app" \
    > "$GH_FIXTURES/ruleset-detail.json"
}

detail_fails_closed() {
  local name="$1" profile="$2" rc=0 out
  out="$(run_script -R acme/widget --profile "$profile" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] \
     && printf '%s\n' "$out" | grep -Eqi 'canonical|custom|detail|malformed' \
     && grep -q 'api repos/acme/widget/rulesets/42' "$GH_CALLS" \
     && no_profile_writes; then
    t_ok "$name"
  else
    t_fail "$name (detail must be read and rejected before writes)"
  fi
}

assert_team_put() {
  local name="$1" enforcement="$2" app="$3"
  if [ -f "$GH_FIXTURES/put.json" ] \
     && jq -e --arg enforcement "$enforcement" --argjson app "$app" '
       .name == "scaffold-branch-protection" and .target == "branch"
       and .enforcement == $enforcement
       and .bypass_actors == [{actor_id:5, actor_type:"RepositoryRole",
                               bypass_mode:"pull_request"}]
       and .conditions == {ref_name:{include:["~DEFAULT_BRANCH"],exclude:[]}}
       and [.rules[].type] == ["pull_request","required_status_checks"]
       and (.rules[0].parameters == {
         required_approving_review_count:1,
         dismiss_stale_reviews_on_push:true,
         require_code_owner_review:true,
         require_last_push_approval:true,
         required_review_thread_resolution:true})
       and .rules[1].parameters.strict_required_status_checks_policy
       and (.rules[1].parameters.required_status_checks | sort_by(.context))
         == (["copilot-surface","quality","scaffold-self-check","task-ritual"]
             | map({context:.,integration_id:$app}))
     ' "$GH_FIXTURES/put.json" >/dev/null; then
    t_ok "$name"
  else
    t_fail "$name"
  fi
}

team_refresh_case() {
  local run_name="$1" body_name="$2" old_enforcement="$3"
  local old_app="$4" requested_enforcement="$5"
  existing_profile_fixtures team "$old_enforcement" "$old_app"
  expect_rc 0 "$run_name" run_script -R acme/widget --profile team \
    --enforcement "$requested_enforcement"
  assert_team_put "$body_name" "$requested_enforcement" 15368
}

variable_write_fails_closed() {
  local name="$1" endpoint="$2" profile="${3:-team}" rc=0 out
  out="$(run_script -R acme/widget --profile "$profile" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] \
     && printf '%s\n' "$out" | grep -Eqi 'could not (create|update).*variable' \
     && [ "$(grep -c -- "$endpoint" "$GH_CALLS")" -eq 1 ] \
     && ! grep -Eq -- '--method (POST|PUT|PATCH|DELETE).*rulesets|probe' "$GH_CALLS"; then
    t_ok "$name"
  else
    t_fail "$name (variable write must fail before any ruleset mutation)"
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

# --- explicit profiles: existing canonical reconciliation -------------------

existing_profile_fixtures solo
expect_rc 0 "canonical solo upgrades in place to explicit team" \
  run_script -R acme/widget --profile team
assert_team_put "team upgrade writes the complete canonical team body" disabled 15368
if [ "$(grep -nE 'rulesets/42|repos/acme/widget$|check-runs|actions/variables|--method PUT' \
          "$GH_CALLS" | cut -d: -f2-)" = "$(printf '%s\n' \
     'api repos/acme/widget/rulesets/42' \
     'api repos/acme/widget' \
     'api repos/acme/widget/commits/trunk/check-runs?filter=latest&per_page=100 --paginate' \
     'api repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE' \
     'api --method POST repos/acme/widget/actions/variables --input -' \
     'api --method PUT repos/acme/widget/rulesets/42 --input -')" ]; then
  t_ok "team upgrade completes every read and persists intent before ruleset PUT"
else
  t_fail "team upgrade completes every read and persists intent before ruleset PUT"
fi

team_refresh_case "canonical team refreshes changed source and enforcement" \
  "team refresh uses observed source and requested enforcement" disabled 77 active
team_refresh_case "team refreshes when only the observed source differs" \
  "source-only refresh full-PUTs the newly observed App ID" active 77 active
team_refresh_case "team refreshes when only requested enforcement differs" \
  "enforcement-only refresh full-PUTs requested enforcement" disabled 15368 active

existing_profile_fixtures team active
expect_rc 0 "exact canonical team match is idempotent" \
  run_script -R acme/widget --profile team --enforcement active
if jq -e '.value == "team"' "$GH_FIXTURES/variable-written.json" >/dev/null \
   && grep -q 'rulesets/42' "$GH_CALLS" \
   && ! grep -Eq -- '--method (PUT|POST).*rulesets' "$GH_CALLS"; then
  t_ok "exact team match persists team intent and performs no ruleset write"
else
  t_fail "exact team match persists team intent and performs no ruleset write"
fi

existing_profile_fixtures solo active
expect_rc 0 "exact canonical solo match is idempotent" \
  run_script -R acme/widget --profile solo --enforcement active
if jq -e '.value == "solo"' "$GH_FIXTURES/variable-written.json" >/dev/null \
   && ! grep -Eq -- '--method (PUT|POST).*rulesets' "$GH_CALLS"; then
  t_ok "exact solo match persists solo intent and performs no ruleset write"
else
  t_fail "exact solo match persists solo intent and performs no ruleset write"
fi

existing_profile_fixtures team active
expect_rc 0 "explicit solo accepts canonical team without downgrade" \
  run_script -R acme/widget --profile solo --enforcement active
if jq -e '.value == "solo"' "$GH_FIXTURES/variable-written.json" >/dev/null \
   && ! grep -Eq -- '--method (PUT|POST).*rulesets' "$GH_CALLS"; then
  t_ok "solo persists intent without rewriting canonical team controls"
else
  t_fail "solo persists intent without rewriting canonical team controls"
fi

existing_profile_fixtures team active 77
expect_rc 0 "explicit solo ignores canonical team source drift" \
  run_script -R acme/widget --profile solo --enforcement active
if jq -e '.value == "solo"' "$GH_FIXTURES/variable-written.json" >/dev/null \
   && ! grep -Eq -- '--method (PUT|POST).*rulesets' "$GH_CALLS"; then
  t_ok "solo source drift persists solo intent with zero ruleset writes"
else
  t_fail "solo source drift persists solo intent with zero ruleset writes"
fi

existing_profile_fixtures team disabled
expect_rc 0 "solo may update only enforcement on canonical team" \
  run_script -R acme/widget --profile solo --enforcement active
if jq -e '.value == "solo"' "$GH_FIXTURES/variable-written.json" >/dev/null \
   && [ "$(grep -E 'rulesets/42|actions/variables|--method PUT' "$GH_CALLS")" \
        = "$(printf '%s\n' \
       'api repos/acme/widget/rulesets/42' \
       'api repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE' \
       'api --method POST repos/acme/widget/actions/variables --input -' \
       'api --method PUT repos/acme/widget/rulesets/42 -f enforcement=active')" ] \
   && ! grep -q -- '--method PUT repos/acme/widget/rulesets/42 --input -' \
     "$GH_CALLS"; then
  t_ok "solo intent persists before enforcement-only PUT without rule rewrite"
else
  t_fail "solo intent persists before enforcement-only PUT without rule rewrite"
fi

existing_profile_fixtures team
expect_rc 0 "existing canonical team dry-run validates with GET calls only" \
  run_script -R acme/widget --profile team --dry-run
if grep -q 'api repos/acme/widget/rulesets/42' "$GH_CALLS" \
   && no_profile_writes; then
  t_ok "existing-profile dry-run reads detail without mutation"
else
  t_fail "existing-profile dry-run reads detail without mutation"
fi

# Exact shape: each single mutation is adopter-owned and must fail closed.
while IFS='|' read -r name base filter; do
  existing_profile_fixtures "$base"
  jq "$filter" "$GH_FIXTURES/ruleset-detail.json" \
    > "$GH_FIXTURES/detail.tmp"
  mv "$GH_FIXTURES/detail.tmp" "$GH_FIXTURES/ruleset-detail.json"
  detail_fails_closed "$name" "$base"
done <<'NONCANONICAL'
tag target is noncanonical|solo|.target = "tag"
changed include is noncanonical|solo|.conditions.ref_name.include = ["refs/heads/main"]
extra exclude is noncanonical|solo|.conditions.ref_name.exclude = ["refs/heads/dev"]
extra bypass is noncanonical|solo|.bypass_actors += [{actor_id:4,actor_type:"RepositoryRole",bypass_mode:"pull_request"}]
changed bypass mode is noncanonical|solo|.bypass_actors[0].bypass_mode = "always"
changed approval count is noncanonical|solo|.rules[0].parameters.required_approving_review_count = 2
extra rule is noncanonical|solo|.rules += [{type:"deletion"}]
duplicate rule is noncanonical|solo|.rules += [.rules[0]]
missing rule is noncanonical|solo|.rules |= map(select(.type != "pull_request"))
extra context is noncanonical|solo|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks) += [{context:"extra"}]
renamed context is noncanonical|solo|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[0].context) = "renamed"
duplicate context is noncanonical|solo|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks) |= . + [.[0]]
mixed review controls are noncanonical|solo|(.rules[]|select(.type=="pull_request").parameters.dismiss_stale_reviews_on_push) = true
mixed strictness is noncanonical|solo|(.rules[]|select(.type=="required_status_checks").parameters.strict_required_status_checks_policy) = true
solo source binding is noncanonical|solo|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[0].integration_id) = 15368
team missing source is noncanonical|team|del(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[0].integration_id)
team mixed source is noncanonical|team|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[0].integration_id) = 42
team null source is noncanonical|team|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[0].integration_id) = null
team malformed source is noncanonical|team|(.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[0].integration_id) = "bad"
NONCANONICAL

# Zero matches intentionally remains the #95 fresh-create path tested above.
profile_fixtures
printf '%s\n' \
  '[{"id":42,"name":"scaffold-branch-protection","enforcement":"disabled"},' \
  '{"id":43,"name":"scaffold-branch-protection","enforcement":"disabled"}]' \
  > "$GH_FIXTURES/rulesets.json"
expect_rc_grep 1 'multiple|duplicate|exactly one' \
  "multiple same-name rulesets fail closed" \
  run_script -R acme/widget --profile team
if no_profile_writes; then
  t_ok "multiple same-name rulesets cause zero writes"
else
  t_fail "multiple same-name rulesets cause zero writes"
fi

existing_profile_fixtures team
rm -f "$GH_FIXTURES/ruleset-detail.json"
detail_fails_closed "failed team ruleset detail read blocks all writes" team

existing_profile_fixtures solo
rm -f "$GH_FIXTURES/ruleset-detail.json"
detail_fails_closed "failed solo ruleset detail read blocks all writes" solo

existing_profile_fixtures team
printf '%s\n' '{"id":42,"name":"scaffold-branch-protection"}' \
  > "$GH_FIXTURES/ruleset-detail.json"
detail_fails_closed "malformed team ruleset detail blocks all writes" team

existing_profile_fixtures solo
printf '%s\n' '{"id":42,"name":"scaffold-branch-protection"}' \
  > "$GH_FIXTURES/ruleset-detail.json"
detail_fails_closed "malformed solo ruleset detail blocks all writes" solo

existing_profile_fixtures solo
export GH_FAIL_EXACT='api --method POST repos/acme/widget/actions/variables --input -'
variable_write_fails_closed \
  "existing solo variable create failure blocks later ruleset PUT" \
  '--method POST repos/acme/widget/actions/variables' solo

existing_profile_fixtures team
export GH_VARIABLE=present
echo '{"name":"SCAFFOLD_GOVERNANCE_PROFILE","value":"solo"}' \
  > "$GH_FIXTURES/variable.json"
export GH_FAIL_EXACT='api --method PATCH repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE --input -'
variable_write_fails_closed \
  "existing team variable update failure blocks later ruleset PUT" \
  '--method PATCH repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE' team

# --- explicit profiles: discovery and persistence failures ------------------

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
variable_write_fails_closed "variable create failure blocks ruleset creation" \
  '--method POST repos/acme/widget/actions/variables'

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
variable_write_fails_closed "variable update failure blocks ruleset creation" \
  '--method PATCH repos/acme/widget/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE'

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
