#!/usr/bin/env bash
# test-ritual-linkage.sh — regression tests for the provenance and routing
# rules in .github/scripts/check-task-ritual.sh: the PR's "Plan:" link must resolve
# to a real plan comment on the linked issue, the issue must carry the
# type:task label, and only allowlisted bots skip the ritual. Existence
# rules live in test-task-ritual.sh, chronology in
# test-ritual-chronology.sh; fixtures here are existence- and
# chronology-complete so only linkage varies, and each failing case pins
# its rule's distinct message via expect_rc_grep.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-task-ritual.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
install_gh_shim "$WORK"

# pull_with_body <body> — human-authored PR JSON with the given body.
pull_with_body() {
  printf '{"user":{"login":"mochan-tk","type":"User"},"body":"%s"}' "$1"
}

RITUAL_OK='[{"body":"Starting in session s1, branch task/12-x.","created_at":"2026-01-01T09:00:00Z","updated_at":"2026-01-01T09:00:00Z"},{"body":"## Plan\n\n1. Steps.\n\nNo worker will be spawned.","created_at":"2026-01-01T09:05:00Z","updated_at":"2026-01-01T09:05:00Z"}]'
COMMITS_OK='[{"commit":{"committer":{"date":"2026-01-01T10:00:00Z"},"author":{"date":"2026-01-01T10:00:00Z"}}}]'
ISSUE_TASK='{"labels":[{"name":"type:task"},{"name":"exec:app"}]}'
ISSUE_UNLABELED='{"labels":[{"name":"enhancement"}]}'
PLAN_COMMENT_12='{"issue_url":"https://api.github.com/repos/o/r/issues/12","body":"## Plan\n\n1. Steps."}'
CLAIM_COMMENT_12='{"issue_url":"https://api.github.com/repos/o/r/issues/12","body":"Starting in session s1, branch task/12-x."}'
PLAN_COMMENT_99='{"issue_url":"https://api.github.com/repos/o/r/issues/99","body":"## Plan\n\n1. Steps."}'
BODY_LINKED='Closes #12\n\nPlan: https://github.com/o/r/issues/12#issuecomment-777'

# new_case <pull-json> <issue-json> [<comment-json>] — write fixtures; sets
# CASE. Comments/commits are always ritual-clean; omit <comment-json> to
# model a plan link whose comment does not exist (the shim answers 404).
SANDBOX_N=0
new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  mkdir -p "$CASE"
  printf '%s\n' "$1" > "$CASE/pull.json"
  printf '%s\n' "$2" > "$CASE/issue.json"
  printf '%s\n' "$RITUAL_OK" > "$CASE/comments.json"
  printf '%s\n' "$COMMITS_OK" > "$CASE/commits.json"
  printf '%s\n' '{"full_name":"o/r"}' > "$CASE/repo.json"
  [ $# -ge 3 ] && printf '%s\n' "$3" > "$CASE/comment.json"
}

# --- fully linked PR passes ----------------------------------------------------
new_case "$(pull_with_body "$BODY_LINKED")" "$ISSUE_TASK" "$PLAN_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 0 'plan link and type:task verified' \
  "plan link, label and ritual all verified passes" bash "$GUARD" 12

# --- missing plan link fails ---------------------------------------------------
new_case "$(pull_with_body 'Closes #12\n\nPlan: <!-- link to the plan comment -->')" \
  "$ISSUE_TASK" "$PLAN_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 1 'no plan link' \
  "PR body without a plan link fails" bash "$GUARD" 12

# --- plan link to another repository fails ---------------------------------------
# The comment-id lookup is repository-scoped, so without the repo check a
# foreign-repo link could pass by colliding with an unrelated local comment.
new_case "$(pull_with_body 'Closes #12\n\nPlan: https://github.com/other/elsewhere/issues/12#issuecomment-777')" \
  "$ISSUE_TASK" "$PLAN_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 1 'points at repository other/elsewhere' \
  "plan link naming another repository fails" bash "$GUARD" 12

# --- plan link to another issue fails ------------------------------------------
new_case "$(pull_with_body 'Closes #12\n\nPlan: https://github.com/o/r/issues/13#issuecomment-777')" \
  "$ISSUE_TASK" "$PLAN_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 1 'plan link points at issue #13' \
  "plan link naming the wrong issue fails" bash "$GUARD" 12

# --- plan link resolving to a comment on another issue fails --------------------
new_case "$(pull_with_body "$BODY_LINKED")" "$ISSUE_TASK" "$PLAN_COMMENT_99"
GH_FIXTURES="$CASE" expect_rc_grep 1 'resolves to issue #99' \
  "plan link resolving to another issue's comment fails" bash "$GUARD" 12

# --- plan link to a non-plan comment fails ----------------------------------------
new_case "$(pull_with_body "$BODY_LINKED")" "$ISSUE_TASK" "$CLAIM_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 1 'not a plan comment' \
  "plan link to the claim comment fails" bash "$GUARD" 12

# --- plan link to a nonexistent comment fails (the PR #71 incident: a dead link
# --- shipped in the PR body and passed CI) -----------------------------------------
new_case "$(pull_with_body "$BODY_LINKED")" "$ISSUE_TASK"
GH_FIXTURES="$CASE" expect_rc_grep 1 'does not resolve' \
  "plan link to a nonexistent comment fails" bash "$GUARD" 12

# --- linked issue without type:task fails ---------------------------------------
new_case "$(pull_with_body "$BODY_LINKED")" "$ISSUE_UNLABELED" "$PLAN_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 1 "lacks the 'type:task' label" \
  "linked issue without type:task fails" bash "$GUARD" 12

# --- non-allowlisted bot is held to the full ritual ------------------------------
new_case '{"user":{"login":"copilot-swe-agent[bot]","type":"Bot"},"body":"Closes #12"}' \
  "$ISSUE_TASK" "$PLAN_COMMENT_12"
GH_FIXTURES="$CASE" expect_rc_grep 1 'not allowlisted' \
  "non-allowlisted bot (cloud agent) is held to the ritual" bash "$GUARD" 12

# --- allowlist override honors RITUAL_EXEMPT_BOTS --------------------------------
new_case '{"user":{"login":"custom-bot[bot]","type":"Bot"},"body":"Automated bump."}' "$ISSUE_TASK"
GH_FIXTURES="$CASE" RITUAL_EXEMPT_BOTS='custom-bot[bot]' expect_rc_grep 0 'allowlisted bot' \
  "RITUAL_EXEMPT_BOTS override exempts a custom bot" bash "$GUARD" 12

t_summary
