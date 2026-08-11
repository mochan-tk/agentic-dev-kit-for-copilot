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

# Recording stub: every invocation lands in $GH_CALLS (one line of argv per
# call); list responses come from $GH_FIXTURES/rulesets.json (absent file
# models a failed list); a POST body is captured to $GH_FIXTURES/posted.json.
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
  "api --method PUT repos/"*"/rulesets/"*) echo '{}' ;;
  "api --method POST repos/"*"/rulesets --input -")
    cat > "$GH_FIXTURES/posted.json"; echo '{"id": 999}' ;;
  *) echo "gh stub: unsupported invocation: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

reset_calls() { : > "$GH_CALLS"; }

run_script() { bash "$SCRIPT" "$@" < /dev/null; }

# --- usage ----------------------------------------------------------------

expect_rc_grep 0 'Usage: setup-ruleset\.sh' "--help prints usage" \
  run_script --help
expect_rc_grep 2 'unknown argument' "unknown flag is a usage error" \
  run_script --bogus
expect_rc_grep 2 "must be 'active' or 'disabled'" \
  "invalid --enforcement is a usage error" \
  run_script --enforcement sometimes

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

t_summary
