#!/usr/bin/env bash
# check-template-sync.sh — fail when an issue form and the canonical body
# template it mirrors drift apart (their header comments promise sync).
#
# Pairs checked (form `label:` values vs body-template `## ` headings, in
# document order):
#   .github/ISSUE_TEMPLATE/ai-task.yml
#     <-> .github/skills/plan-management/templates/task-body.md
#   .github/ISSUE_TEMPLATE/epic.yml
#     <-> .github/skills/plan-management/templates/epic-body.md
#
# Collapse rule: a run of consecutive form labels prefixed "Routing — "
# (Surface, Suggested role, ...) maps to the single body heading "Routing".
#
# Output: brief OK summary and exit 0 when in sync; diff-style listing
# ("- " = form label, "+ " = body heading) and exit 1 on mismatch.
# Dependencies: bash 3.2+, grep, sed, git only — runs identically in CI
# (.github/workflows/ci.yml, scaffold-self-check job) and on dev machines.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAIL=0

# Ordered `label:` values of an issue form, surrounding quotes and trailing
# whitespace stripped, runs of "Routing — *" collapsed to one "Routing".
extract_labels() {
  local file="$1"
  local line label prev=""
  while IFS= read -r line; do
    label="$(printf '%s\n' "$line" \
      | sed -e 's/^[[:space:]]*label:[[:space:]]*//' \
            -e 's/[[:space:]]*$//' \
            -e 's/^"\(.*\)"$/\1/' \
            -e "s/^'\(.*\)'\$/\1/")"
    case "$label" in
      "Routing — "*) label="Routing" ;;
    esac
    if [ "$label" = "Routing" ] && [ "$prev" = "Routing" ]; then
      continue
    fi
    printf '%s\n' "$label"
    prev="$label"
  done < <(grep -E '^[[:space:]]*label:' "$file")
}

# Ordered `## ` headings of a body template, trailing whitespace stripped.
extract_headings() {
  local file="$1"
  { grep -E '^## ' "$file" || true; } \
    | sed -e 's/^## //' -e 's/[[:space:]]*$//'
}

# Compare one form/template pair; report; return 1 on any problem.
check_pair() {
  local form_file="$1" body_file="$2"
  local f form_list body_list count
  for f in "$form_file" "$body_file"; do
    if [ ! -f "$f" ]; then
      echo "check-template-sync: ERROR — missing file: $f" >&2
      return 1
    fi
  done

  form_list="$(extract_labels "$form_file")"
  body_list="$(extract_headings "$body_file")"

  if [ -z "$form_list" ]; then
    echo "check-template-sync: ERROR — no 'label:' entries in $form_file" >&2
    return 1
  fi
  if [ -z "$body_list" ]; then
    echo "check-template-sync: ERROR — no '## ' headings in $body_file" >&2
    return 1
  fi

  if [ "$form_list" = "$body_list" ]; then
    count="$(printf '%s\n' "$body_list" | grep -c '')"
    echo "OK: $form_file <-> $body_file ($count sections in sync)"
    return 0
  fi

  echo "MISMATCH: $form_file labels do not match $body_file headings" >&2
  echo "--- $form_file (label: values, 'Routing — *' collapsed)" >&2
  echo "+++ $body_file (## headings)" >&2

  local form_arr body_arr item i nf nb max fv bv
  form_arr=()
  body_arr=()
  while IFS= read -r item; do form_arr+=("$item"); done \
    < <(printf '%s\n' "$form_list")
  while IFS= read -r item; do body_arr+=("$item"); done \
    < <(printf '%s\n' "$body_list")
  nf="${#form_arr[@]}"
  nb="${#body_arr[@]}"
  max="$nf"
  if [ "$nb" -gt "$max" ]; then
    max="$nb"
  fi
  i=0
  while [ "$i" -lt "$max" ]; do
    fv="${form_arr[$i]-}"
    bv="${body_arr[$i]-}"
    if [ "$fv" = "$bv" ]; then
      printf '  %s\n' "$fv" >&2
    else
      if [ "$i" -lt "$nf" ]; then
        printf -- '- %s\n' "$fv" >&2
      fi
      if [ "$i" -lt "$nb" ]; then
        printf '+ %s\n' "$bv" >&2
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

check_pair ".github/ISSUE_TEMPLATE/ai-task.yml" \
  ".github/skills/plan-management/templates/task-body.md" || FAIL=1
check_pair ".github/ISSUE_TEMPLATE/epic.yml" \
  ".github/skills/plan-management/templates/epic-body.md" || FAIL=1

if [ "$FAIL" -ne 0 ]; then
  echo "check-template-sync: FAIL — template pairs out of sync (see above)." >&2
  exit 1
fi
echo "check-template-sync: OK — issue forms and body templates are in sync."
