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
#      a committed baseline and render only official URLs and safe titles.
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

normalize_literal() {
 printf '%s' "$1" | tr '\r\n\t' ' ' | tr -d '\000-\037' | \
   sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
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

fetch_official_value() {
 local url="$1"
 local kind="${2:-title}"
 local effective="" tmp="" output=""

 [ -n "$url" ] || return 1
 if ! command -v curl >/dev/null 2>&1; then
   return 1
 fi

 tmp="$(mktemp "${TMPDIR:-/tmp}/retro-hygiene.XXXXXX")"
 if ! effective="$(curl -fsSL --max-time 15 -w '%{url_effective}' -o "$tmp" "$url" 2>/dev/null)"; then
   rm -f "$tmp"
   return 1
 fi

 if [ -n "$effective" ] && [ "$(canonical_url "$effective")" != "$(canonical_url "$url")" ]; then
   rm -f "$tmp"
   return 1
 fi

 case "$kind" in
   title|"")
     output="$(tr '\r' '\n' < "$tmp" | sed -n 's:.*<title[^>]*>\(.*\)</title>.*:\1:pI' | head -n 1)"
     ;;
   sha256|file_sha|docs_sha|changelog_sha|url_sha|sha)
     output="$(sha256sum "$tmp" | awk '{print $1}')"
     ;;
   release|version|release_id)
     output="$(python3 - "$tmp" <<'PY'
import re, sys
path = sys.argv[1]
try:
   text = open(path, 'r', encoding='utf-8', errors='replace').read()
except Exception:
   raise SystemExit
for pattern in [r'^[#*\- ]*v?([0-9]+\.[0-9]+\.[0-9]+(?:[-+._a-zA-Z0-9]+)?)', r'^(?:#+)\s+([^\n]+)']:
   match = re.search(pattern, text, re.M)
   if match:
       print(match.group(1).strip())
       raise SystemExit
print('unknown')
PY
)"
     ;;
   rss_guid)
     output="$(python3 - "$tmp" <<'PY'
import sys, xml.etree.ElementTree as ET
path = sys.argv[1]
try:
   root = ET.fromstring(open(path, 'rb').read())
except Exception:
   raise SystemExit
items = root.findall('.//item')
if not items:
   raise SystemExit
item = items[0]
text = (item.findtext('guid') or '').strip()
print(text or 'unknown')
PY
)"
     ;;
   rss_guid_date|rss)
     output="$(python3 - "$tmp" <<'PY'
import sys, xml.etree.ElementTree as ET
path = sys.argv[1]
try:
   root = ET.fromstring(open(path, 'rb').read())
except Exception:
   raise SystemExit
items = root.findall('.//item')
if not items:
   raise SystemExit
item = items[0]
guid = (item.findtext('guid') or '').strip()
pub = (item.findtext('pubDate') or '').strip()
print(f'{guid}|{pub}' if guid or pub else 'unknown')
PY
)"
     ;;
   *)
     output="$(tr '\r' '\n' < "$tmp" | sed -n 's:.*<title[^>]*>\(.*\)</title>.*:\1:pI' | head -n 1)"
     ;;
 esac

 rm -f "$tmp"
 if [ -n "$output" ]; then
   printf '%s\n' "$output"
   return 0
 fi
 return 1
}

render_capability_detail() {
 local label="$1" url="$2" expected="$3" observed="$4" state="$5"
 local safe_label safe_url safe_expected safe_observed

 safe_label="$(sanitize_md_cell "$label")"
 safe_url="$(sanitize_md_cell "$url")"
 safe_expected="$(sanitize_md_cell "$expected")"
 safe_observed="$(sanitize_md_cell "$observed")"

 case "$state" in
   unchanged)
     printf -- '- %s: unchanged at %s\n' "$safe_label" "$safe_url"
     ;;
   changed)
     printf -- '- %s: changed — old %s -> new %s at %s\n' "$safe_label" "$safe_expected" "$safe_observed" "$safe_url"
     printf '  1. Does the platform now duplicate a skill, prompt, instruction, custom agent or guard in this kit?\n'
     printf '  2. Can anything be deleted or retired rather than added?\n'
     printf '  3. Does it close or change a known runtime limitation (#6, #43, #45, #47)?\n'
     printf '  4. Which surface supports it (app, CLI, cloud, IDE), and is it preview or GA?\n'
     printf '  5. Has the capability been verified in this environment rather than inferred from release prose?\n'
     ;;
   *)
     printf -- '- %s: unknown — preserving baseline %s at %s\n' "$safe_label" "$safe_expected" "$safe_url"
     ;;
 esac
}

build_platform_capability_section() {
 local table state label kind url expected current observed observed_norm expected_norm line detail
 local changed_count unknown_count unchanged_count

 changed_count=0
 unknown_count=0
 unchanged_count=0

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
 detail=""
 while IFS= read -r line || [ -n "$line" ]; do
   [ -n "${line//[[:space:]]/}" ] || continue
   case "$line" in
     \#*) continue ;;
   esac

   IFS=$'\t' read -r -a cols <<< "$line"
   case "${#cols[@]}" in
     3)
       label="${cols[0]}"
       kind="title"
       url="${cols[1]}"
       expected="${cols[2]}"
       ;;
     4)
       label="${cols[0]}"
       kind="${cols[1]}"
       url="${cols[2]}"
       expected="${cols[3]}"
       ;;
     *)
       continue
       ;;
   esac

   [ -n "$label" ] || continue
   case "$label" in
     capability) continue ;;
   esac

   observed="$(fetch_official_value "$url" "$kind" 2>/dev/null || true)"
   state="unknown"
   current="unknown"

   if [ -n "$observed" ]; then
     current="$(sanitize_md_cell "$observed")"
     observed_norm="$(normalize_literal "$observed")"
     expected_norm="$(normalize_literal "$expected")"
     if [ "$expected_norm" = "unknown" ] || [ "$observed_norm" = "unknown" ]; then
       state="unknown"
     elif [ "$observed_norm" = "$expected_norm" ]; then
       state="unchanged"
     else
       state="changed"
     fi
   fi

   case "$state" in
     changed)
       changed_count=$((changed_count + 1))
       ;;
     unknown)
       unknown_count=$((unknown_count + 1))
       ;;
     unchanged)
       unchanged_count=$((unchanged_count + 1))
       ;;
   esac

   table="${table}| $(sanitize_md_cell "$label") | $(sanitize_md_cell "$url") | $(sanitize_md_cell "$expected") | ${current} | $(sanitize_md_cell "$state") |\n"
   detail="${detail}$(render_capability_detail "$label" "$url" "$expected" "$current" "$state")"
 done < "$BASELINE_FILE"

 if [ -z "$table" ]; then
   cat <<'EOF'
## Platform capability checkpoints

The source-template baseline is present, but it contains no rows to compare.
EOF
   return 0
 fi

 if [ "$changed_count" -eq 0 ] && [ "$unknown_count" -eq 0 ]; then
   cat <<'EOF'
## Platform capability checkpoints

No official Copilot capability changes detected against the committed source-template baseline.
EOF
   return 0
 fi

 cat <<EOF
## Platform capability checkpoints

This review is source-template-only: it runs only when the repository is the
source template (the scaffold marker reads "sha=unknown"), it renders only
official URLs, and it keeps upstream content as untrusted data rather than as a
source of truth or shell input. Baseline advances are PR-only and record one
line per changed source with the outcome: adopt, retire local mechanism,
watch, or not relevant.

| Capability | Official URL | Baseline | Observed | Status |
|---|---|---|---|---|
${table}
${detail}
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
   table="${table}| #${num} | ${title} | ${count} | ${age} | ${status} |\n"
 done <<< "$tsv"

 if [ "$total" -eq 0 ]; then
   candidates_section="No open \`retro:candidate\` issues — the ledger is clean."
 else
   candidates_section="| Issue | Title | Occurrences | Age (days) | Status |\n|---|---|---|---|---|\n${table}${total} open candidate(s), ${overdue} at or over the promotion threshold (>= 2 occurrences)."
 fi

 budget_rows="$(budget_row "AGENTS.md")
$(budget_row ".github/copilot-instructions.md")"
 platform_section="$(build_platform_capability_section)"

 cat <<EOF
# ${ISSUE_TITLE}

Deterministic retro-loop snapshot for \`${REPO}\` (retro skill, "Scheduled
hygiene" trigger). Occurrence count = 1 (the filing) + N (occurrence
comments); candidates reaching 2 occurrences are due for promotion to a
\`retro:\` PR. Seed occurrence: the initial Rubber Duck/#68 review-model
question is the first ledger item; #69 retired the review-model variant, and
this official capability ledger is the engine-class follow-up.

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
