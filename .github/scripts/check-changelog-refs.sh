#!/usr/bin/env bash
# check-changelog-refs.sh — fail when SCAFFOLD-CHANGELOG.md cites an issue
# number that cannot belong to this repository.
#
# Why: GitHub resolves a bare `#<n>` against the repository the file lives
# in. A number carried over from somewhere else therefore does not go dead —
# it silently links to an unrelated issue here, and gets *more* wrong as
# this repository's numbering grows into the borrowed range.
#
# The rule this enforces: a bare `#<n>` in the changelog must be an issue or
# pull request that exists here. Since the ceiling moves as the repository
# grows, the check compares against the highest number seen locally (git tags
# cannot tell us, so the bound is the largest referenced number that is also
# plausibly ours). To stay offline and deterministic, the bound is stored in
# the sentinel below and raised deliberately when entries are added.
#
# References to other repositories are fine when qualified: `owner/repo#12`
# renders as an explicit cross-repository link and is skipped by this check.
#
# Output: brief OK summary and exit 0 when every reference is in range; the
# offending lines and exit 1 otherwise.
# Dependencies: bash 3.2+, grep, sed, awk only — runs identically in CI and
# on a developer machine, no network.
set -euo pipefail

FILE="${1:-SCAFFOLD-CHANGELOG.md}"

# Highest issue/PR number this repository is known to have reached. Raise it
# in the same PR that adds an entry citing a higher number.
MAX_KNOWN=200

[ -f "$FILE" ] || { echo "error: $FILE not found" >&2; exit 2; }

# Drop code spans first: `#123` inside backticks is documentation, not a link.
# Then drop qualified cross-repository references (owner/repo#n) so only bare
# numbers remain.
# shellcheck disable=SC2016  # the backticks are literal Markdown, not a subshell
stripped="$(sed -e 's/`[^`]*`//g' -e 's|[A-Za-z0-9._-]\{1,\}/[A-Za-z0-9._-]\{1,\}#[0-9]\{1,\}||g' "$FILE")"

bad=0
line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))
  # shellcheck disable=SC2001
  for ref in $(printf '%s\n' "$line" | grep -oE '#[0-9]+' || true); do
    n="${ref#\#}"
    if [ "$n" -gt "$MAX_KNOWN" ]; then
      echo "FAIL: $FILE:$line_no cites $ref, above this repository's known range (#$MAX_KNOWN)."
      echo "      A bare number always resolves here — qualify it as owner/repo#n,"
      echo "      restate the entry without a number, or raise MAX_KNOWN in $0."
      bad=1
    fi
  done
done <<EOF
$stripped
EOF

if [ "$bad" -ne 0 ]; then
  exit 1
fi

count="$(printf '%s\n' "$stripped" | { grep -oE '#[0-9]+' || true; } | wc -l | tr -d ' ')"
echo "check-changelog-refs: OK — $count bare reference(s) in $FILE, all within #$MAX_KNOWN."
