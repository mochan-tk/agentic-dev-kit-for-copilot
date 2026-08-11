#!/usr/bin/env bash
# run-tests.sh — offline regression harness for the CI guard scripts.
#
# Discovers every .github/scripts/tests/test-*.sh, runs each in its own bash
# process, and aggregates the results. The guards under test never touch
# the network: GitHub API reads are served by a PATH shim over recorded
# fixtures, and filesystem guards run against throwaway git sandboxes.
#
# Usage: bash .github/scripts/tests/run-tests.sh
# Exit: 0 when every test file passes, 1 on any failure, 2 on a missing
# dependency. Dependencies: bash 3.2+, git, jq (for the gh shim).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for dep in git jq; do
  command -v "$dep" >/dev/null 2>&1 || {
    echo "error: '$dep' not found — the guard tests need it." >&2
    exit 2
  }
done

failed=0
total=0
for t in "$HERE"/test-*.sh; do
  [ -e "$t" ] || { echo "error: no test files found in $HERE" >&2; exit 2; }
  total=$((total + 1))
  echo "== $(basename "$t")"
  if bash "$t"; then
    echo
  else
    failed=$((failed + 1))
    echo
  fi
done

if [ "$failed" -gt 0 ]; then
  echo "FAIL — $failed of $total guard test file(s) failed."
  exit 1
fi
echo "OK — all $total guard test file(s) passed."
