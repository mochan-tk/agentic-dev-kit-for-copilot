#!/usr/bin/env bash
# check-md-links.sh — fail when Markdown references a repo path that does
# not exist.
#
# Scans scaffold-owned Markdown (AGENTS.md, README.md, SCAFFOLD-CHANGELOG.md,
# .github/**/*.md) for references matching
#   .github/<path>.(md|yml|sh|json)
# and asserts each referenced path exists in the working tree. App-owned
# Markdown outside those paths is never scanned — the scaffold does not
# police application docs.
#
# Allowlist — intentional example paths that documentation cites although
# the files do not exist (onboarding placeholders, replaced per project):
#   .github/docs/context/device-pairing/   example area cited in agreements
#   .github/docs/context/line-integration/ example area in the
#                                          context-collection skill
#
# Output: brief OK summary and exit 0 when everything resolves; list of
# missing paths and exit 1 otherwise.
# Dependencies: bash 3.2+, grep, awk, git only — runs identically in CI
# (.github/workflows/ci.yml, scaffold-self-check job) and on dev machines.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REF_PATTERN='\.github/[A-Za-z0-9_/.-]+\.(md|yml|sh|json)'

ALLOW_PREFIXES=(
  ".github/docs/context/device-pairing/"
  ".github/docs/context/line-integration/"
)

md_files=()
while IFS= read -r f; do md_files+=("$f"); done < <(
  git ls-files 'AGENTS.md' 'README.md' 'SCAFFOLD-CHANGELOG.md' '.github/*.md'
)

if [ "${#md_files[@]}" -eq 0 ]; then
  echo "check-md-links: OK — no tracked Markdown files to scan."
  exit 0
fi

# Unique references in first-seen order (awk dedupe keeps dependencies lean).
refs="$({ grep -hoE "$REF_PATTERN" ${md_files[@]+"${md_files[@]}"} || true; } \
  | awk '!seen[$0]++')"

missing=()
checked=0
allowlisted=0
while IFS= read -r ref; do
  if [ -z "$ref" ]; then
    continue
  fi
  skip=0
  for prefix in "${ALLOW_PREFIXES[@]}"; do
    case "$ref" in
      "$prefix"*)
        skip=1
        break
        ;;
    esac
  done
  if [ "$skip" -eq 1 ]; then
    allowlisted=$((allowlisted + 1))
    continue
  fi
  checked=$((checked + 1))
  if [ ! -e "$ref" ]; then
    missing+=("$ref")
  fi
done < <(printf '%s\n' "$refs")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "check-md-links: FAIL — ${#missing[@]} referenced path(s) missing:" >&2
  printf '  MISSING: %s\n' ${missing[@]+"${missing[@]}"} >&2
  exit 1
fi

echo "check-md-links: OK — $checked unique path reference(s) resolve" \
  "($allowlisted allowlisted example reference(s) skipped," \
  "${#md_files[@]} Markdown file(s) scanned)."
