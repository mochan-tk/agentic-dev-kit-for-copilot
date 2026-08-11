#!/usr/bin/env bash
# test-ritual-chronology.sh — regression tests for the chronology rules in
# .github/scripts/check-task-ritual.sh: claim → plan → first commit, and claim/plan
# comment immutability. Existence rules are covered by test-task-ritual.sh,
# linkage/label/allowlist rules by test-ritual-linkage.sh; every fixture
# here is existence- and linkage-complete so only chronology varies, and
# each failing case pins its rule's distinct message via expect_rc_grep.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-task-ritual.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
install_gh_shim "$WORK"

PR_JSON='{"user":{"login":"mochan-tk","type":"User"},"body":"Closes #12\\n\\nPlan: https://github.com/o/r/issues/12#issuecomment-777"}'
ISSUE_TASK='{"labels":[{"name":"type:task"}]}'
PLAN_COMMENT_12='{"issue_url":"https://api.github.com/repos/o/r/issues/12","body":"## Plan\\n\\n1. Steps."}'

# claim_at / plan_at <created> [<updated>] — comment JSON with timestamps.
# commits_at <committer-date> [<author-date>] — one-commit PR listing.
claim_at() {
  printf '{"body":"Starting in session s1, branch task/12-x.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
plan_at() {
  printf '{"body":"## Plan\\n\\n1. Steps.\\n\\nNo worker will be spawned.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
commits_at() {
  printf '[{"commit":{"committer":{"date":"%s"},"author":{"date":"%s"}}}]' "$1" "${2:-$1}"
}

# new_case <pull-json> <comments-json> <commits-json> — write fixtures
# (plus the static linkage-complete issue/comment pair); sets CASE.
SANDBOX_N=0
new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  mkdir -p "$CASE"
  printf '%s\n' "$1" > "$CASE/pull.json"
  printf '%s\n' "$2" > "$CASE/comments.json"
  printf '%s\n' "$3" > "$CASE/commits.json"
  printf '%s\n' "$ISSUE_TASK" > "$CASE/issue.json"
  printf '%s\n' "$PLAN_COMMENT_12" > "$CASE/comment.json"
  printf '%s\n' '{"full_name":"o/r"}' > "$CASE/repo.json"
}

# --- claim → plan → commit in order passes ------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'ritual in order' \
  "correct chronology passes" bash "$GUARD" 12

# --- plan posted before the claim fails ---------------------------------------
new_case "$PR_JSON" "[$(plan_at 2026-01-01T08:55:00Z), $(claim_at 2026-01-01T09:00:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'out of order' \
  "plan before claim fails" bash "$GUARD" 12

# --- first commit before the plan fails ---------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T09:02:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'predates the plan comment' \
  "commit before plan fails" bash "$GUARD" 12

# --- edited plan comment fails -------------------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z 2026-01-01T09:30:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'edited after posting' \
  "edited plan comment fails" bash "$GUARD" 12

# --- edited claim comment fails -------------------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z 2026-01-01T09:10:00Z), $(plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'edited after posting' \
  "edited claim comment fails" bash "$GUARD" 12

# --- allowlisted bot PRs stay exempt from chronology too -------------------------
new_case '{"user":{"login":"dependabot[bot]","type":"Bot"},"body":"Bumps actions/checkout."}' \
  "[$(plan_at 2026-01-01T08:00:00Z 2026-01-01T08:30:00Z)]" "$(commits_at 2026-01-01T07:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'allowlisted bot' \
  "allowlisted bot PR remains exempt" bash "$GUARD" 12

t_summary
