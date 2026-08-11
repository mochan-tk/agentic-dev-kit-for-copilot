#!/usr/bin/env bash
# test-escalation-wording.sh — regression tests for
# .github/scripts/check-escalation-wording.sh.
#
# Each case builds a throwaway git repo, copies the guard into it, stages
# surface fixtures, and asserts the exit code. The guard scans only the
# staged Copilot surfaces (AGENTS.md, .github/…), never .github/scripts/.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SANDBOX_N=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  init_sandbox_repo "$CASE"
  mkdir -p "$CASE/.github/scripts" "$CASE/.github/skills/session-orchestration"
  cp "$REPO_ROOT/.github/scripts/check-escalation-wording.sh" "$CASE/.github/scripts/"
}

# --- clean surfaces pass ------------------------------------------------------
new_case
cat > "$CASE/AGENTS.md" <<'EOF'
# Constitution
Escalate per the ladder in session-orchestration; never restate its budgets.
EOF
stage_all "$CASE"
expect_rc 0 "surfaces without counts pass" bash "$CASE/.github/scripts/check-escalation-wording.sh"

# --- count + escalation word on one surface line fails ------------------------
new_case
cat > "$CASE/AGENTS.md" <<'EOF'
# Constitution
After two failures on the same gate, stop and escalate.
EOF
stage_all "$CASE"
expect_rc 1 "count paired with escalation word fails" bash "$CASE/.github/scripts/check-escalation-wording.sh"

# --- the normative skill is allowlisted ---------------------------------------
new_case
cat > "$CASE/.github/skills/session-orchestration/SKILL.md" <<'EOF'
# Session orchestration
Two consecutive failures on the same gate escalate to the parent session.
EOF
cat > "$CASE/AGENTS.md" <<'EOF'
# Constitution
Defer to the escalation ladder; it owns the numbers.
EOF
stage_all "$CASE"
expect_rc 0 "normative skill may state failure counts" bash "$CASE/.github/scripts/check-escalation-wording.sh"

# --- count and escalation words on different lines pass ------------------------
new_case
cat > "$CASE/AGENTS.md" <<'EOF'
# Constitution
There are three phases of planning.
Escalate when blocked.
EOF
stage_all "$CASE"
expect_rc 0 "count and escalation on separate lines pass" bash "$CASE/.github/scripts/check-escalation-wording.sh"

t_summary
