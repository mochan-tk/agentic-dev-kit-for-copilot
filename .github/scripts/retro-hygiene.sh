#!/usr/bin/env bash
# retro-hygiene.sh — deterministic hygiene report for the retro skill's
# "Scheduled hygiene" trigger: open retro:candidate issues with occurrence
# counts, plus the always-on context budget, printed as a Markdown report.
#
# Report sections:
#   1. Open retro:candidate issues — number, title, occurrence count
#      (1 filing + N occurrence comments), age in days; count >= 2 is
#      flagged PROMOTION OVERDUE (retro skill, Candidate ledger).
#   2. Optional source-template platform capability review: only when the
#      current repository is the source template (`sha=unknown` in
#      SCAFFOLD-CHANGELOG.md), compare the official change checkpoints against
#      a committed baseline and render only official URLs and titles.
#   3. Always-on budget — line counts of AGENTS.md and
#      .github/copilot-instructions.md against the ~150-line target
#      (retro skill, Budget rule).
#   4. Pointer to the retro skill Procedure for acting on the findings.
#
# Usage:
#   retro-hygiene.sh [-R owner/repo]                 Print the report to stdout.
#   retro-hygiene.sh --create-issue [-R owner/repo]  Also file the report as an
#                                                    issue titled "Retro hygiene
#                                                    review <YYYY-MM>" labeled
#                                                    needs:human.
#   retro-hygiene.sh --help
#
# Options:
#   --create-issue           File the report as the monthly review issue.
#                            Idempotent: when an OPEN issue with exactly that
#                            title already exists, print its URL and exit 0
#                            without creating a duplicate.
#   -R, --repo <owner/repo>  Target repository. Default: the repository the
#                            current directory belongs to (via `gh repo view`).
#   -h, --help               Show this help and exit.
#
# Exits 0 even when there are zero open candidates (the report says so).
# Always-on line counts are measured in this script's own checkout; issue
# data comes from the target repository. Ages are computed from epoch
# seconds inside `gh --jq`, so BSD vs GNU `date` differences do not matter.
#
# Requires: gh (authenticated; the needs:human label from
# .github/scripts/setup-labels.sh must exist for --create-issue). No external jq.
# Compatible with bash 3.2 (macOS /bin/bash).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUDGET_TARGET=150
BASELINE_FILE="$ROOT/.github/scripts/platform-capability-baseline.tsv"

usage() { sed -n '2,/^$/{s/^# \{0,1\}//p;}' "$0"; }

fail() { echo "error: $*" >&2; exit 1; }

usage_error() {
 echo "error: $*" >&2
 echo "Run '$(basename "$0") --help' for usage." >&2
 exit 2
}

sanitize_md_cell() {
 printf '%s' "$1" | tr '\r\n\t' ' ' | tr -d '\000-\037' | \
   sed 's/[<>&]/ /g; s/|/\\|/g; s/[[:space:]]\+/ /g; s/[[:space:]]\+$//; s/^[[:space:]]\+//'
}

normalize_title() {
 printf '%s' "$1" | tr '\r\n\t' ' ' | tr -d '\000-\037' | \
   sed 's/[<>&]/ /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

canonical_url() {
 local url="${1%%#*}"
 url="${url%%\?*}"
 printf '%s' "${url%/}"
}

source_template_gate() {
 if [ -f "$ROOT/SCAFFOLD-CHANGELOG.md" ] && \
   grep -Eq '^<!-- scaffold-version: .* sha=unknown ' "$ROOT/SCAFFOLD-CHANGELOG.md"; then
   return 0
 fi
 return 1
}

fetch_official_title() {
 local url="$1" title="" effective="" tmp=""
 [ -n "$url" ] || return 1
 if ! command -v curl >/dev/null 2>&1; then
   return 1
 fi

 tmp="$(mktemp "${TMPDIR:-/tmp}/retro-hygiene.XXXXXX")"
 if ! effective="$(curl -fsSL --max-time 15 -w '%{url_effective}' -o "$tmp" "$url" 2>/dev/null)"; then
   rm -f "$tmp"
   return 1
 fi

 if [ -z "$effective" ]; then
   rm -f "$tmp"
   return 1
 fi

 if [ "$(canonical_url "$effective")" != "$(canonical_url "$url")" ]; then
   rm -f "$tmp"
   return 1
 fi

 title="$(tr '\r' '\n' < "$tmp" | sed -n 's:.*<title[^>]*>\(.*\)</title>.*:\1:pI' | head -n 1)"
 rm -f "$tmp"

 if [ -n "$title" ]; then
   printf '%s\n' "$(normalize_title "$title")"
   return 0
 fi
 return 1
}

build_platform_capability_section() {
 local table state label url expected current observed

 if ! source_template_gate; then
   return 0
 fi

 if [ ! -f "$BASELINE_FILE" ]; then
   cat <<'EOF'
## Platform capability checkpoints

No committed platform-capability baseline is present in this source template.
EOF
   return 0
 fi

 table=""
 while IFS=$'\t' read -r label url expected; do
   [ -n "$label" ] || continue
   case "$label" in
     capability) continue ;;
     '') continue ;;
   esac

   observed="$(fetch_official_title "$url" 2>/dev/null || true)"
   state="unknown"
   current="unknown"
   if [ -n "$observed" ]; then
     current="$(sanitize_md_cell "$observed")"
     observed_norm="$(normalize_title "$observed")"
     expected_norm="$(normalize_title "$expected")"
     if [ "$observed_norm" = "$expected_norm" ]; then
       state="unchanged"
     else
       state="changed"
     fi
   fi

   table="${table}| $(sanitize_md_cell "$label") | $(sanitize_md_cell "$url") | $(sanitize_md_cell "$expected") | ${current} | $(sanitize_md_cell "$state") |
"
 done < "$BASELINE_FILE"

 if [ -z "$table" ]; then
   cat <<'EOF'
## Platform capability checkpoints

The source-template baseline is present, but it contains no rows to compare.
EOF
   return 0
 fi

 cat <<EOF
## Platform capability checkpoints

This review is source-template-only: it runs only when the repository is the
source template (the scaffold marker reads "sha=unknown"), and it renders only
official URLs and titles. Upstream titles and content are never evaluated or
interpolated into shell commands.

| Capability | Official URL | Baseline title | Observed title | Status |
|---|---|---|---|---|
${table}
EOF
}

CREATE_ISSUE=0
REPO=""

while [ $# -gt 0 ]; do
 case "$1" in
   --create-issue) CREATE_ISSUE=1 ;;
   -R|--repo)
     [ -n "${2:-}" ] || usage_error "$1 requires an owner/repo argument"
     REPO="$2"
     shift
     ;;
   -h|--help) usage; exit 0 ;;
   *) usage_error "unknown argument: $1" ;;
 esac
 shift
done

command -v gh >/dev/null 2>&1 || fail "gh CLI not found on PATH"

if [ -z "$REPO" ]; then
 REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
[[ "$REPO" == */* ]] || usage_error "repository must be owner/repo, got: $REPO"

list_candidates() {
 gh issue list -R "$REPO" --label retro:candidate --state open --limit 1000 \
   --json number,title,comments,createdAt \
   --jq '.[] | [.number,
                (1 + ([.comments[] | select(.body | startswith("Occurrence:"))] | length)),
                (((now - (.createdAt | fromdateiso8601)) / 86400) | floor),
                .title] | @tsv'
}

budget_row() {
 local file="$1" lines status
 [ -f "$ROOT/$file" ] || fail "always-on file not found: $ROOT/$file"
 lines="$(wc -l < "$ROOT/$file" | tr -d '[:space:]')"
 if [ "$lines" -le "$BUDGET_TARGET" ]; then
   status="under target"
 else
   status="**OVER TARGET**"
 fi
 printf '| %s | %s | ~%s | %s |' "$file" "$lines" "$BUDGET_TARGET" "$status"
}

build_report() {
 local tsv num count age title status total overdue table
 local candidates_section budget_rows platform_section

 tsv="$(list_candidates)"
 total=0
 overdue=0
 table=""
 while IFS=$'\t' read -r num count age title; do
   [ -n "$num" ] || continue
   total=$((total + 1))
   status="ok"
   if [ "$count" -ge 2 ]; then
     status="**PROMOTION OVERDUE**"
     overdue=$((overdue + 1))
   fi
   title="${title//|/\\|}"
   table="${table}| #${num} | ${title} | ${count} | ${age} | ${status} |
"
 done <<< "$tsv"

 if [ "$total" -eq 0 ]; then
   candidates_section="No open \`retro:candidate\` issues — the ledger is clean."
 else
   candidates_section="| Issue | Title | Occurrences | Age (days) | Status |
|---|---|---|---|---|
${table}
${total} open candidate(s), ${overdue} at or over the promotion threshold (>= 2 occurrences)."
 fi

 budget_rows="$(budget_row "AGENTS.md")
$(budget_row ".github/copilot-instructions.md")"
 platform_section="$(build_platform_capability_section)"

 cat <<EOF
# ${ISSUE_TITLE}

Deterministic retro-loop snapshot for \`${REPO}\` (retro skill, "Scheduled
hygiene" trigger). Occurrence count = 1 (the filing) + N (occurrence
comments); candidates reaching 2 occurrences are due for promotion to a
\`retro:\` PR.

## Open retro candidates

${candidates_section}

${platform_section}

## Always-on budget

| File | Lines | Target | Status |
|---|---|---|---|
${budget_rows}

## Next steps

Act via the Procedure in \`.github/skills/retro/SKILL.md\`: promote each
overdue candidate into a \`retro:\` PR (which closes the candidate), trim
or demote lines when an always-on file exceeds the Budget-rule target, and
review any official capability checkpoint that is marked as changed or
unknown before extending the local implementation.
EOF
}

create_review_issue() {
 local existing
 existing="$(gh issue list -R "$REPO" --state open --limit 1000 \
   --json title,url \
   --jq "[.[] | select(.title == \"${ISSUE_TITLE}\") | .url] | .[0] // empty")"
 if [ -n "$existing" ]; then
   echo "Idempotent skip — open review issue already exists: ${existing}"
   return 0
 fi
 echo "Filing review issue: ${ISSUE_TITLE}"
 gh issue create -R "$REPO" --title "$ISSUE_TITLE" --label needs:human \
   --body "$REPORT"
}

MONTH="$(date -u +%Y-%m)"
ISSUE_TITLE="Retro hygiene review ${MONTH}"

REPORT="$(build_report)"
printf '%s\n' "$REPORT"

if [ "$CREATE_ISSUE" -eq 1 ]; then
 create_review_issue
fi
