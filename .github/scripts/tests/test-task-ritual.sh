#!/usr/bin/env bash
# test-task-ritual.sh — regression tests for .github/scripts/check-task-ritual.sh
# (existence rules: task link, claim, plan; bot exemption; usage).
#
# The guard reads GitHub through `gh api … --jq <expr>`; lib.sh's
# install_gh_shim puts a fake `gh` first in PATH that answers from per-case
# JSON fixtures. No network, no auth, no repository state. Chronology rules
# are covered by test-ritual-chronology.sh; plan-link provenance, label and
# bot-allowlist rules by test-ritual-linkage.sh — fixtures here are
# linkage-complete so only existence varies.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-task-ritual.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
install_gh_shim "$WORK"

# new_case <pull-json> <comments-json> [<commits-json>] [<issue-json>]
# [<comment-json>] — write per-case fixtures; sets CASE. Defaults keep the
# case chronology- and linkage-clean: commits postdate every fixture
# comment, the issue carries type:task, and comment.json answers the PR
# body's plan link with a real plan comment on issue 12.
SANDBOX_N=0
new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  mkdir -p "$CASE"
  printf '%s\n' "$1" > "$CASE/pull.json"
  printf '%s\n' "$2" > "$CASE/comments.json"
  printf '%s\n' "${3:-$COMMITS_LATER}" > "$CASE/commits.json"
  printf '%s\n' "${4:-$ISSUE_TASK}" > "$CASE/issue.json"
  printf '%s\n' "${5:-$PLAN_COMMENT_12}" > "$CASE/comment.json"
  printf '%s\n' '{"full_name":"o/r"}' > "$CASE/repo.json"
}

HUMAN_PR_BODY='{"user":{"login":"mochan-tk","type":"User"},"body":"Closes #12\\n\\nPlan: https://github.com/o/r/issues/12#issuecomment-777"}'
CLAIM='{"body":"Starting in session abc123 (Copilot CLI). Branch: task/12-x.","created_at":"2026-01-01T09:00:00Z","updated_at":"2026-01-01T09:00:00Z"}'
PLAN_HEADING='{"body":"## Plan\\n\\n1. Do the thing.\\n2. Verify.\\n\\nNo worker will be spawned.","created_at":"2026-01-01T09:05:00Z","updated_at":"2026-01-01T09:05:00Z"}'
PLAN_PREFIX='{"body":"Plan: extract, test, wire into CI. No worker will be spawned.","created_at":"2026-01-01T09:05:00Z","updated_at":"2026-01-01T09:05:00Z"}'
NOISE='{"body":"Drive-by comment that is neither claim nor plan.","created_at":"2026-01-01T09:03:00Z","updated_at":"2026-01-01T09:03:00Z"}'
COMMITS_LATER='[{"commit":{"committer":{"date":"2026-01-01T10:00:00Z"},"author":{"date":"2026-01-01T09:55:00Z"}}}]'
ISSUE_TASK='{"labels":[{"name":"type:task"},{"name":"ai:ready"},{"name":"exec:app"}]}'
PLAN_COMMENT_12='{"issue_url":"https://api.github.com/repos/o/r/issues/12","body":"## Plan\\n\\n1. Do the thing."}'
PLAN_COMMENT_34='{"issue_url":"https://api.github.com/repos/o/r/issues/34","body":"## Plan\\n\\n1. Do the thing."}'

# --- allowlisted bot PRs are exempt -------------------------------------------
new_case '{"user":{"login":"dependabot[bot]","type":"Bot"},"body":"Bumps actions/checkout."}' '[]'
GH_FIXTURES="$CASE" expect_rc 0 "allowlisted bot PR is exempt" bash "$GUARD" 12

# --- missing task link fails -------------------------------------------------
new_case '{"user":{"login":"mochan-tk","type":"User"},"body":"No link here."}' '[]'
GH_FIXTURES="$CASE" expect_rc 1 "PR body without a task link fails" bash "$GUARD" 12

# --- claim missing fails -----------------------------------------------------
new_case "$HUMAN_PR_BODY" "[$PLAN_HEADING, $NOISE]"
GH_FIXTURES="$CASE" expect_rc 1 "issue without a start claim fails" bash "$GUARD" 12

# --- plan missing fails ------------------------------------------------------
new_case "$HUMAN_PR_BODY" "[$CLAIM, $NOISE]"
GH_FIXTURES="$CASE" expect_rc 1 "issue without a plan comment fails" bash "$GUARD" 12

# --- claim + '## Plan' heading passes ---------------------------------------
new_case "$HUMAN_PR_BODY" "[$NOISE, $CLAIM, $PLAN_HEADING]"
GH_FIXTURES="$CASE" expect_rc 0 "claim plus '## Plan' heading passes" bash "$GUARD" 12

# --- claim + 'Plan:' body prefix passes --------------------------------------
new_case "$HUMAN_PR_BODY" "[$CLAIM, $PLAN_PREFIX]"
GH_FIXTURES="$CASE" expect_rc 0 "claim plus 'Plan:' prefix passes" bash "$GUARD" 12

# --- 'Refs #N' links the task too (post-merge acceptance, AGENTS.md §4) ------
new_case '{"user":{"login":"mochan-tk","type":"User"},"body":"Refs #34 — verified after merge.\\n\\nPlan: https://github.com/o/r/issues/34#issuecomment-777"}' \
  "[$CLAIM, $PLAN_HEADING]" "" "" "$PLAN_COMMENT_34"
GH_FIXTURES="$CASE" expect_rc 0 "'Refs #N' task link is accepted" bash "$GUARD" 12

# --- usage error without a PR number ------------------------------------------
unset PR_NUMBER
expect_rc 2 "missing PR number is a usage error" bash "$GUARD"

t_summary
