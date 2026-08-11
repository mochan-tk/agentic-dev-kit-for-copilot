#!/usr/bin/env bash
# check-action-pins.sh — CI wall: every GitHub Actions reference must be
# pinned to a full commit SHA with a trailing version comment.
#
# Tags can be moved or re-signed; SHAs cannot. A compliant reference looks
# like:  uses: owner/action@<40-hex-sha> # vX.Y.Z
# Local composite actions (uses: ./path) are exempt — they ship with the
# repository and need no pin.
#
# This logic previously lived inline in .github/workflows/ci.yml (quality
# job); it was extracted verbatim so the guard regression tests
# (.github/scripts/tests/) can exercise it offline. Keep the regexes identical to
# the documented contract above.
#
# Output: single OK line and exit 0 when clean; offending lines plus a
# ::error:: annotation and exit 1 on violation. Dependencies: bash 3.2+,
# git, grep, xargs only — runs identically in CI and on dev machines.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

files=$(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')
if [ -z "$files" ]; then
  echo "All action references are SHA-pinned (no workflow files to scan)."
  exit 0
fi

bad=$(printf '%s\n' "$files" \
  | xargs grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]' \
  | grep -vE 'uses:[[:space:]]+\./' \
  | grep -vE '@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' || true)
if [ -n "$bad" ]; then
  printf '%s\n' "$bad"
  echo "::error::Unpinned uses: reference above — pin to a full 40-hex commit SHA with a trailing '# vX.Y.Z' comment."
  exit 1
fi
echo "All action references are SHA-pinned."
