#!/usr/bin/env bash
# test-tuning-status.sh — regression tests for .github/scripts/tuning-status.sh.
#
# Covers the report / --quiet / --ci contracts against throwaway sandbox
# trees (no git, no network): marker detection and exit codes, the
# ::warning:: stream, and the --ci GITHUB_STEP_SUMMARY emission — a summary
# block is appended only when the variable names a file AND findings exist,
# stdout stays byte-identical with or without the variable (proved with cmp
# on captured files, not $(...) which strips trailing newlines), a tuned
# tree appends nothing, and an unwritable summary path cannot break the
# --ci always-exit-0 contract. Every invocation pins the variable
# explicitly (env -u / env VAR=...) because real CI exports
# GITHUB_STEP_SUMMARY to this test.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tuningtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

SCRIPT_SRC="$REPO_ROOT/.github/scripts/tuning-status.sh"

# make_sandbox <dir> — minimal tree with the script at its real relative
# path, so the script's own ROOT resolution lands on the sandbox.
make_sandbox() {
  mkdir -p "$1/.github/scripts"
  cp "$SCRIPT_SRC" "$1/.github/scripts/tuning-status.sh"
}

# Two markers in one target file: deterministic finding order for the
# byte-exact stdout comparison below.
MARKED="$WORK/marked"
make_sandbox "$MARKED"
printf '%s\n%s\n%s\n' \
  '<!-- CUSTOMIZE: map the layout -->' \
  '# body' \
  '<!-- CUSTOMIZE: verify the commands -->' \
  > "$MARKED/.github/copilot-instructions.md"

TUNED="$WORK/tuned"
make_sandbox "$TUNED"
echo '# tuned instructions' > "$TUNED/.github/copilot-instructions.md"

# run_no_summary <sandbox> [args...] — run with GITHUB_STEP_SUMMARY unset.
run_no_summary() {
  local dir="$1"
  shift
  env -u GITHUB_STEP_SUMMARY bash "$dir/.github/scripts/tuning-status.sh" "$@"
}

# run_with_summary <file> <sandbox> [args...] — run with the variable set.
run_with_summary() {
  local file="$1" dir="$2"
  shift 2
  env GITHUB_STEP_SUMMARY="$file" bash "$dir/.github/scripts/tuning-status.sh" "$@"
}

# --- report and --quiet: exit codes and messages --------------------------
expect_rc_grep 1 'NOT TUNED' "report mode on markers exits 1 and says NOT TUNED" \
  run_no_summary "$MARKED"
expect_rc_grep 0 '^TUNED:' "report mode on a tuned tree exits 0 and says TUNED" \
  run_no_summary "$TUNED"
expect_rc 1 "--quiet on markers exits 1" run_no_summary "$MARKED" --quiet
expect_rc 0 "--quiet on a tuned tree exits 0" run_no_summary "$TUNED" --quiet
expect_rc_grep 2 'Unknown argument' "unknown argument exits 2" \
  run_no_summary "$MARKED" --bogus

# --- --ci without the variable: today's contract, byte for byte -----------
# Expected stdout and actual stdout live in files compared with cmp, because
# $(...) strips trailing newlines and cannot prove byte identity.
EXPECTED_WARNINGS="$WORK/expected-warnings.txt"
printf '%s\n' \
  '::warning::scaffold not onboarded — .github/copilot-instructions.md:1:<!-- CUSTOMIZE: map the layout -->' \
  '::warning::scaffold not onboarded — .github/copilot-instructions.md:3:<!-- CUSTOMIZE: verify the commands -->' \
  > "$EXPECTED_WARNINGS"

OUT_UNSET="$WORK/stdout-ci-unset.txt"
rc=0
run_no_summary "$MARKED" --ci > "$OUT_UNSET" || rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$OUT_UNSET" "$EXPECTED_WARNINGS"; then
  t_ok "--ci with the variable unset: exit 0, exactly the ::warning:: lines"
else
  t_fail "--ci with the variable unset: exit 0, exactly the ::warning:: lines (rc=$rc)"
  sed 's/^/    # /' "$OUT_UNSET"
fi

OUT_TUNED="$WORK/stdout-ci-tuned.txt"
rc=0
run_no_summary "$TUNED" --ci > "$OUT_TUNED" || rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$OUT_TUNED" ]; then
  t_ok "--ci on a tuned tree, variable unset: exit 0 and silent"
else
  t_fail "--ci on a tuned tree, variable unset: exit 0 and silent (rc=$rc)"
fi

# --- --ci with the variable: summary appended, stdout unchanged -----------
SUM_NEW="$WORK/summary-new.md"
: > "$SUM_NEW"
OUT_SET="$WORK/stdout-ci-set.txt"
rc=0
run_with_summary "$SUM_NEW" "$MARKED" --ci > "$OUT_SET" || rc=$?
if [ "$rc" -eq 0 ]; then
  t_ok "--ci with the variable set still exits 0"
else
  t_fail "--ci with the variable set still exits 0 (rc=$rc)"
fi
if cmp -s "$OUT_SET" "$OUT_UNSET"; then
  t_ok "stdout is byte-identical with and without GITHUB_STEP_SUMMARY"
else
  t_fail "stdout is byte-identical with and without GITHUB_STEP_SUMMARY"
  sed 's/^/    # /' "$OUT_SET"
fi
if grep -qF 'Scaffold not onboarded' "$SUM_NEW" \
  && grep -qF '/onboard-project' "$SUM_NEW" \
  && grep -qF '.github/copilot-instructions.md:1:<!-- CUSTOMIZE: map the layout -->' "$SUM_NEW" \
  && grep -qF '.github/copilot-instructions.md:3:<!-- CUSTOMIZE: verify the commands -->' "$SUM_NEW"; then
  t_ok "summary file gains headline, /onboard-project nudge, and every finding"
else
  t_fail "summary file gains headline, /onboard-project nudge, and every finding"
  sed 's/^/    # /' "$SUM_NEW"
fi
if [ "$(grep -cF '```' "$SUM_NEW")" = "2" ]; then
  t_ok "findings sit inside one opened-and-closed code fence"
else
  t_fail "findings sit inside one opened-and-closed code fence"
fi

# --- --ci appends after prior content, never truncates ---------------------
SUM_SEEDED="$WORK/summary-seeded.md"
echo 'pre-existing summary content' > "$SUM_SEEDED"
run_with_summary "$SUM_SEEDED" "$MARKED" --ci >/dev/null
if [ "$(head -n 1 "$SUM_SEEDED")" = 'pre-existing summary content' ] \
  && grep -qF 'Scaffold not onboarded' "$SUM_SEEDED"; then
  t_ok "summary emission appends after pre-existing content"
else
  t_fail "summary emission appends after pre-existing content"
  sed 's/^/    # /' "$SUM_SEEDED"
fi

# --- --ci on a tuned tree writes nothing (documented choice) ---------------
SUM_TUNED="$WORK/summary-tuned.md"
: > "$SUM_TUNED"
rc=0
OUT=$(run_with_summary "$SUM_TUNED" "$TUNED" --ci) || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$SUM_TUNED" ]; then
  t_ok "--ci on a tuned tree appends nothing to the summary file"
else
  t_fail "--ci on a tuned tree appends nothing to the summary file (rc=$rc)"
fi

# --- --ci with the variable set but empty behaves like unset ----------------
OUT_EMPTY="$WORK/stdout-ci-empty.txt"
rc=0
env GITHUB_STEP_SUMMARY= bash "$MARKED/.github/scripts/tuning-status.sh" --ci \
  > "$OUT_EMPTY" || rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$OUT_EMPTY" "$EXPECTED_WARNINGS"; then
  t_ok "--ci with an empty variable behaves exactly like unset"
else
  t_fail "--ci with an empty variable behaves exactly like unset (rc=$rc)"
fi

# --- --ci with an unwritable summary path keeps the exit-0 contract --------
# set -euo pipefail would abort on the failed redirect without the guard.
OUT_UNWRITABLE="$WORK/stdout-ci-unwritable.txt"
rc=0
run_with_summary "$WORK/no-such-dir/summary.md" "$MARKED" --ci \
  > "$OUT_UNWRITABLE" 2>"$WORK/stderr-ci-unwritable.txt" || rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$OUT_UNWRITABLE" "$EXPECTED_WARNINGS"; then
  t_ok "--ci with an unwritable summary path: exit 0, stdout still exact"
else
  t_fail "--ci with an unwritable summary path: exit 0, stdout still exact (rc=$rc)"
  sed 's/^/    # /' "$OUT_UNWRITABLE"
fi

t_summary
