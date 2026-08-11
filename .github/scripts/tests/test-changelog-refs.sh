#!/usr/bin/env bash
# test-changelog-refs.sh — regression tests for
# .github/scripts/check-changelog-refs.sh.
#
# The guard exists because a bare `#<n>` always resolves against the
# repository the file lives in: a number carried over from elsewhere links
# to an unrelated issue here rather than going dead. Each case writes a
# throwaway changelog and asserts the exit code and message.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-changelog-refs.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/clreftest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

write_changelog() {
  printf '%s\n' "$2" > "$WORK/$1"
}

# --- in-range references pass ---------------------------------------------
write_changelog ok.md '- An entry citing this repository (refs #12).'
expect_rc_grep 0 "check-changelog-refs: OK" \
  "in-range bare reference passes" \
  bash "$GUARD" "$WORK/ok.md"

# --- an inherited number is caught ----------------------------------------
# The failure mode this guard was written for: a number from another
# repository that silently links to an unrelated issue here.
write_changelog inherited.md '- An entry carried over from elsewhere (refs #228).'
expect_rc_grep 1 "above this repository's known range" \
  "out-of-range bare reference fails" \
  bash "$GUARD" "$WORK/inherited.md"

# --- qualified cross-repository references are allowed --------------------
# owner/repo#n renders as an explicit cross-repository link, so it cannot
# mis-resolve and must not be flagged however large the number.
write_changelog qualified.md '- Superseded upstream (see other-owner/other-repo#4242).'
expect_rc_grep 0 "check-changelog-refs: OK" \
  "qualified cross-repository reference passes" \
  bash "$GUARD" "$WORK/qualified.md"

# --- code spans are documentation, not links ------------------------------
write_changelog codespan.md '- The guard rejects a bare `#9999` in prose.'
expect_rc_grep 0 "check-changelog-refs: OK" \
  "number inside a code span is ignored" \
  bash "$GUARD" "$WORK/codespan.md"

# --- the shipped changelog itself is clean --------------------------------
expect_rc_grep 0 "check-changelog-refs: OK" \
  "the repository's own changelog passes the guard" \
  bash "$GUARD" "$REPO_ROOT/SCAFFOLD-CHANGELOG.md"

t_summary
