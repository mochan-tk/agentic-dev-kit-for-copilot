#!/usr/bin/env bash
# test-workflow-permissions.sh — regression tests for
# .github/scripts/check-workflow-permissions.sh.
#
# The guard catches a defect this repository's own CI cannot: a job that
# declares `permissions:` without `contents` and then checks out fails only
# on private repositories, while this repository is public. Each case writes
# a throwaway workflow directory and asserts the exit code.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-workflow-permissions.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wfpermtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# new_wf <case-name> <job-body> — build a one-job workflow directory and set
# CASE_DIR to it.
new_wf() {
  CASE_DIR="$WORK/$1"
  mkdir -p "$CASE_DIR"
  {
    printf 'name: t\non: [push]\npermissions:\n  contents: read\njobs:\n'
    printf '%s\n' "$2"
  } > "$CASE_DIR/wf.yml"
}

# --- the broken shape is caught -------------------------------------------
new_wf broken '  ritual:
    runs-on: ubuntu-latest
    permissions:
      issues: read
      pull-requests: read
    steps:
      - uses: actions/checkout@0000000000000000000000000000000000000000
      - run: echo hi'
expect_rc_grep 1 "grants no 'contents' scope" \
  "job with permissions and checkout but no contents fails" \
  bash "$GUARD" "$CASE_DIR"

# --- the fixed shape passes -----------------------------------------------
new_wf fixed '  ritual:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: read
    steps:
      - uses: actions/checkout@0000000000000000000000000000000000000000'
expect_rc_grep 0 "check-workflow-permissions: OK" \
  "job that grants contents passes" \
  bash "$GUARD" "$CASE_DIR"

# --- inheriting the workflow grant is fine --------------------------------
# The common case: no job-level block, so the workflow-level grant applies.
new_wf inherit '  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0000000000000000000000000000000000000000'
expect_rc_grep 0 "check-workflow-permissions: OK" \
  "job without a permissions block passes" \
  bash "$GUARD" "$CASE_DIR"

# --- permissions without checkout is fine ---------------------------------
# Narrow scopes are correct when the job never clones; the guard must not
# push `contents` onto jobs that do not need it.
new_wf nocheckout '  label:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - run: gh issue edit 1 --add-label x'
expect_rc_grep 0 "check-workflow-permissions: OK" \
  "job with narrow permissions and no checkout passes" \
  bash "$GUARD" "$CASE_DIR"

# --- one bad job among good ones is still caught --------------------------
new_wf mixed '  good:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@0000000000000000000000000000000000000000
  bad:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: read
    steps:
      - uses: actions/checkout@0000000000000000000000000000000000000000'
expect_rc_grep 1 "job 'bad'" \
  "a single offending job among healthy ones is reported" \
  bash "$GUARD" "$CASE_DIR"

# --- this repository's own workflows pass ---------------------------------
expect_rc_grep 0 "check-workflow-permissions: OK" \
  "the scaffold's own workflows pass the guard" \
  bash "$GUARD" "$REPO_ROOT/.github/workflows"

t_summary
