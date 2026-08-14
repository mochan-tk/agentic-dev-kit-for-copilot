#!/usr/bin/env bash
# run-tests.sh — offline regression harness for the CI guard scripts.
#
# Discovers every .github/scripts/tests/test-*.sh, runs each in its own bash
# process, and aggregates the results. The guards under test never touch
# the network: GitHub API reads are served by a PATH shim over recorded
# fixtures, and filesystem guards run against throwaway git sandboxes.
#
# These tests belong to the kit, not to the projects that adopt it. They
# exercise scaffold machinery — the installer's symlink refusal, the ritual
# wall's exemptions, the gh fixture shim — none of which an adopting project
# owns or can act on. So they decline to run outside the template, and say so
# in a line instead of costing six minutes and, on Windows, failing (#58).
# The signal is the scaffold-version marker: `sha=unknown` is the template
# itself, a real commit sha is an adopting repository (the same discriminator
# the ritual wall's onboarding exemption uses). Set FORCE_GUARD_TESTS=1 to run
# them anywhere — a fork, or a checkout without the marker.
#
# Usage: bash .github/scripts/tests/run-tests.sh [suite ...]
#   suite: a test file name, with or without the test- prefix and .sh suffix,
#          or a substring of one — `run-tests.sh ritual` runs every ritual
#          suite. No arguments runs all of them.
# Exit: 0 when every test file passes (or when declining), 1 on any failure,
# 2 on a missing dependency or an unmatched suite name.
# Dependencies: bash 3.2+, git, jq (for the gh shim).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

if [ "${FORCE_GUARD_TESTS:-0}" != "1" ]; then
  marker="$ROOT/SCAFFOLD-CHANGELOG.md"
  # An adopted scaffold records the commit it came from; the template's own
  # copy has nothing to record and reads `sha=unknown`. A missing marker file
  # means neither, so the tests run — a bare checkout of this repository is
  # the likeliest cause and a contributor is the likeliest owner.
  if [ -f "$marker" ] && ! grep -q '^<!-- scaffold-version: .* sha=unknown ' "$marker"; then
    echo "skip - these tests verify the scaffold's own machinery, so they do not"
    echo "       run in a repository that adopted it. Your project's checks are"
    echo "       the ones in .github/copilot-instructions.md; the guards here are"
    echo "       covered by the kit's CI. Set FORCE_GUARD_TESTS=1 to run anyway."
    exit 0
  fi
fi

for dep in git jq; do
  command -v "$dep" >/dev/null 2>&1 || {
    echo "error: '$dep' not found — the guard tests need it." >&2
    exit 2
  }
done

# Selecting suites: match each argument as a substring of a file's base name,
# so `ritual-adoption`, `test-ritual-adoption` and `test-ritual-adoption.sh`
# all reach the same file, and `ritual` reaches every ritual suite. An
# argument that matches nothing is an error rather than a silent empty run.
selected=()
if [ "$#" -gt 0 ]; then
  for want in "$@"; do
    found=0
    for t in "$HERE"/test-*.sh; do
      [ -e "$t" ] || continue
      case "$(basename "$t")" in
        *"$want"*) selected[${#selected[@]}]="$t"; found=1 ;;
      esac
    done
    [ "$found" -eq 1 ] || {
      echo "error: no test file matches '$want'." >&2
      printf '       available:' >&2
      for t in "$HERE"/test-*.sh; do printf ' %s' "$(basename "$t")" >&2; done
      printf '\n' >&2
      exit 2
    }
  done
else
  for t in "$HERE"/test-*.sh; do
    [ -e "$t" ] || { echo "error: no test files found in $HERE" >&2; exit 2; }
    selected[${#selected[@]}]="$t"
  done
  # Six minutes was read as a hang in this repository's own work, by the
  # person who wrote the tests. Saying so costs one line.
  echo "Running the full guard suite; expect roughly six minutes."
  echo "Pass a suite name to run one — for example: run-tests.sh ritual-adoption"
  echo
fi

failed=0
total=0
for t in ${selected[@]+"${selected[@]}"}; do
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
