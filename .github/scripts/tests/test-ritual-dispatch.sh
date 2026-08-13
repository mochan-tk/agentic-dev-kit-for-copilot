#!/usr/bin/env bash
# test-ritual-dispatch.sh — regression tests for the execution-mode rules in
# .github/scripts/check-task-ritual.sh (ADR-0003 Decision 2): a PR's linked
# Task shows either a worker-dispatch trail (dispatch after the plan and
# before the first commit, a release between successive dispatches,
# dispatch/release comments immutable) or a small-task exemption declared in
# a plan comment ("no worker will be spawned", matched case-insensitively);
# an undeclared mode fails.
# Existence rules live in test-task-ritual.sh, claim/plan chronology in
# test-ritual-chronology.sh, linkage/label/allowlist rules in
# test-ritual-linkage.sh; every fixture here is existence-, chronology- and
# linkage-complete so only the execution mode varies, and each failing case
# pins its rule's distinct message via expect_rc_grep.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-task-ritual.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
install_gh_shim "$WORK"

PR_JSON='{"user":{"login":"mochan-tk","type":"User"},"head":{"ref":"task/12-x"},"body":"Closes #12\\n\\nPlan: https://github.com/o/r/issues/12#issuecomment-777"}'
ISSUE_TASK='{"labels":[{"name":"type:task"}]}'
PLAN_COMMENT_12='{"issue_url":"https://api.github.com/repos/o/r/issues/12","body":"## Plan\\n\\n1. Steps."}'

# claim_at / plan_at / exempt_plan_at / dispatch_at / release_at
# <created> [<updated>] — comment JSON with timestamps. The exempt plan is
# a regular plan comment carrying the AGENTS.md §4 exemption phrase.
# commits_at <committer-date> [<author-date>] — one-commit PR listing.
claim_at() {
  printf '{"body":"Starting in session s1, branch task/12-x.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
plan_at() {
  printf '{"body":"## Plan\\n\\n1. Steps.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
exempt_plan_at() {
  printf '{"body":"## Plan\\n\\nTrivial change; no worker will be spawned.\\n\\n1. Steps.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
exempt_plan_sentence_at() {
  printf '{"body":"## Plan\\n\\n1. Steps.\\n\\nNo worker will be spawned.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
dispatch_at() {
  printf '{"body":"Dispatching worker: PR #99 worker (session 6af9582d-42d1-425d-82c8-f9ec651225a8), branch task/12-x","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
release_at() {
  printf '{"body":"Releasing worker w1 (context exhausted); successor w2 follows.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
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

# --- declared small-task exemption passes ---------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(exempt_plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'small-task exemption' \
  "declared exemption passes" bash "$GUARD" 12

# --- sentence-case exemption phrase passes (matching is case-insensitive) -------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(exempt_plan_sentence_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'small-task exemption' \
  "sentence-case exemption phrase passes" bash "$GUARD" 12

# --- worker-dispatch trail passes -----------------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:10:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'two-tier' \
  "dispatch trail passes" bash "$GUARD" 12

# --- neither dispatch nor exemption fails ---------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'declares no execution mode' \
  "missing dispatch and exemption fails" bash "$GUARD" 12

# --- dispatch posted before the plan fails --------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(dispatch_at 2026-01-01T09:02:00Z), $(plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'dispatch .* predates earliest plan' \
  "dispatch before plan fails" bash "$GUARD" 12

# --- first commit before the dispatch fails -------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:30:00Z)]" \
  "$(commits_at 2026-01-01T09:20:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'predates the worker-dispatch comment' \
  "commit before dispatch fails" bash "$GUARD" 12

# --- replacement dispatch without a release fails -------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:10:00Z), $(dispatch_at 2026-01-01T09:30:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'no release comment' \
  "second dispatch without release fails" bash "$GUARD" 12

# --- released replacement dispatch passes ---------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:10:00Z), $(release_at 2026-01-01T09:20:00Z), $(dispatch_at 2026-01-01T09:30:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'two-tier' \
  "released replacement dispatch passes" bash "$GUARD" 12

# --- edited dispatch comment fails ----------------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:10:00Z 2026-01-01T09:15:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'edited after posting' \
  "edited dispatch comment fails" bash "$GUARD" 12

# --- edited release comment fails -----------------------------------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:10:00Z), $(release_at 2026-01-01T09:20:00Z 2026-01-01T09:25:00Z), $(dispatch_at 2026-01-01T09:30:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'edited after posting' \
  "edited release comment fails" bash "$GUARD" 12

# --- a dispatch trail overrides a declared exemption ----------------------------
# The exemption phrase must not rescue a violating dispatch trail: with any
# dispatch comment present the two-tier checks apply, exemption ignored.
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(dispatch_at 2026-01-01T09:02:00Z), $(exempt_plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'dispatch .* predates earliest plan' \
  "dispatch overrides declared exemption" bash "$GUARD" 12

# --- a dispatch naming no session fails -----------------------------------------
# The point of the two-tier split is that a worker session really exists. A
# dispatch comment that names none records a split that may not have happened.
dispatch_no_session_at() {
  printf '{"body":"Dispatching worker w1 on branch task/12-x.","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_no_session_at 2026-01-01T09:10:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'names no session' \
  "dispatch without a session identifier fails" bash "$GUARD" 12

# --- a dispatch naming another task's branch fails ------------------------------
# Without this, one task's dispatch comment satisfies another's trail: the
# first line matched, and nothing tied it to this PR.
dispatch_wrong_branch_at() {
  printf '{"body":"Dispatching worker: PR #99 worker (session 6af9582d-42d1-425d-82c8-f9ec651225a8), branch task/34-other","created_at":"%s","updated_at":"%s"}' "$1" "${2:-$1}"
}
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_wrong_branch_at 2026-01-01T09:10:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 "dispatches branch 'task/34-other'" \
  "dispatch naming another branch fails" bash "$GUARD" 12

# --- a managed-surface branch prefix still matches ------------------------------
# Managed surfaces prefix the branch they generate (AGENTS.md §4), so a head
# ref ending in the dispatched name is the same branch.
PR_PREFIXED='{"user":{"login":"mochan-tk","type":"User"},"head":{"ref":"copilot/task/12-x"},"body":"Closes #12\\n\\nPlan: https://github.com/o/r/issues/12#issuecomment-777"}'
new_case "$PR_PREFIXED" "[$(claim_at 2026-01-01T09:00:00Z), $(plan_at 2026-01-01T09:05:00Z), $(dispatch_at 2026-01-01T09:10:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'two-tier' \
  "managed-prefix head ref matches the dispatched branch" bash "$GUARD" 12

# --- a retroactive exemption fails ----------------------------------------------
# The exemption is a decision recorded before implementing, mirroring
# plan-before-commit; claimed afterwards it is hindsight, not a trail.
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(exempt_plan_at 2026-01-01T11:00:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 1 'predates the small-task exemption' \
  "exemption declared after the first commit fails" bash "$GUARD" 12

# --- an exemption declared before the commit still passes -----------------------
new_case "$PR_JSON" "[$(claim_at 2026-01-01T09:00:00Z), $(exempt_plan_at 2026-01-01T09:05:00Z)]" \
  "$(commits_at 2026-01-01T10:00:00Z)"
GH_FIXTURES="$CASE" expect_rc_grep 0 'exemption' \
  "exemption declared before the first commit passes" bash "$GUARD" 12

t_summary
