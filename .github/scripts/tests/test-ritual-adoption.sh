#!/usr/bin/env bash
# test-ritual-adoption.sh — regression tests for the adoption exemption in
# .github/scripts/check-task-ritual.sh.
#
# The PR that installs this scaffold has no Task issue to link: when it
# opens, the repository has no scaffold, usually no issues, and the workflow
# doing the enforcing arrives in that very diff. An adopter hit exactly that
# and needed an admin merge (#53). Exemption 2 cannot cover it — its
# self-limiting signal asks whether the base is *already* adopted.
#
# What these cases pin is that the exemption is narrow and cannot be claimed
# by an ordinary PR: the base must genuinely lack AGENTS.md, and the diff
# must genuinely add both AGENTS.md and copilot-instructions.md. A missing
# contents fixture stands for a 404, which is how "the base has no scaffold"
# is expressed here.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-task-ritual.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/adopttest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
install_gh_shim "$WORK"

# The reported PR: no task link, no plan, no issues in the repository. If the
# exemption does not fire, everything after it fails — which is the point.
PULL_ADOPTION='{"user":{"login":"mochan-tk","type":"User"},"title":"Add Agentic Dev Kit for Copilot scaffold","body":"Closes #N/A\n\nPlan: N/A (scaffold bootstrap, no Task issue)","base":{"ref":"main"}}'

FILES_SCAFFOLD='[{"filename":"AGENTS.md","status":"added"},{"filename":".github/copilot-instructions.md","status":"added"},{"filename":".github/workflows/ci.yml","status":"added"}]'
FILES_AGENTS_ONLY='[{"filename":"AGENTS.md","status":"added"}]'
FILES_ORDINARY='[{"filename":"src/main.c","status":"added"},{"filename":"README.md","status":"modified"}]'

# new_case <pull-json> <files-json> [base-has-agents] — writes fixtures and
# sets CASE. Omitting the third argument leaves contents-agents.json absent,
# which the shim answers as 404: a base with no scaffold.
SANDBOX_N=0
new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  mkdir -p "$CASE"
  printf '%s\n' "$1" > "$CASE/pull.json"
  printf '%s\n' "$2" > "$CASE/pull-files.json"
  printf '%s\n' '{"full_name":"o/r"}' > "$CASE/repo.json"
  printf '%s\n' '[]' > "$CASE/comments.json"
  printf '%s\n' '[]' > "$CASE/commits.json"
  printf '%s\n' '{"labels":[]}' > "$CASE/issue.json"
  [ $# -ge 3 ] && printf '%s\n' '{"sha":"abc1234","content":""}' > "$CASE/contents-agents.json"
  return 0
}

# --- the adoption PR passes ------------------------------------------------
new_case "$PULL_ADOPTION" "$FILES_SCAFFOLD"
GH_FIXTURES="$CASE" expect_rc_grep 0 'adopts the scaffold' \
  "a PR adding the scaffold to a repository without one passes" \
  bash "$GUARD" 1

# --- and lapses the moment it has merged -----------------------------------
# Same PR, same diff; the only change is that the base now has AGENTS.md.
# This is the whole self-limiting argument, so it is pinned rather than
# argued: after the merge the exemption can never hold in that repository.
new_case "$PULL_ADOPTION" "$FILES_SCAFFOLD" base-has-agents
GH_FIXTURES="$CASE" expect_rc_grep 1 'no task link' \
  "the same PR against an adopted base is held to the ritual" \
  bash "$GUARD" 1

# --- adding AGENTS.md alone is not adopting --------------------------------
# A repository writing its own agent notes must not inherit the exemption.
new_case "$PULL_ADOPTION" "$FILES_AGENTS_ONLY"
GH_FIXTURES="$CASE" expect_rc_grep 1 'no task link' \
  "adding AGENTS.md without copilot-instructions.md is not an adoption" \
  bash "$GUARD" 1

# --- an ordinary PR cannot claim it ----------------------------------------
new_case "$PULL_ADOPTION" "$FILES_ORDINARY"
GH_FIXTURES="$CASE" expect_rc_grep 1 'no task link' \
  "a PR touching neither scaffold file is held to the ritual" \
  bash "$GUARD" 1

# --- a modified AGENTS.md is not an added one ------------------------------
# Retro PRs amend AGENTS.md routinely; if "modified" counted, every one of
# them against a scaffold-less base would skip the ritual.
new_case "$PULL_ADOPTION" \
  '[{"filename":"AGENTS.md","status":"modified"},{"filename":".github/copilot-instructions.md","status":"added"}]'
GH_FIXTURES="$CASE" expect_rc_grep 1 'no task link' \
  "modifying AGENTS.md rather than adding it is not an adoption" \
  bash "$GUARD" 1

t_summary
