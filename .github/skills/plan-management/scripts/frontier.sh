#!/usr/bin/env bash
# frontier.sh — print the actionable frontier of the plan.
#
# Frontier = open issues labeled `type:task` and `ai:ready` whose "Blocked by"
# issues are all CLOSED. These are the tasks an orchestrator may dispatch right
# now. Epics never qualify: they are outline items, not work orders.
#
# Usage:
#   frontier.sh [-R owner/repo] [--all]
#     -R, --repo   Target repository (defaults to the current directory's repo).
#     --all        Also list blocked ai:ready issues with their open blockers.
#
# Requires: GitHub CLI (gh) >= 2.94 recommended. The script tries the JSON
# dependency field first and falls back to parsing the human-readable
# "Blocked by:" row of `gh issue view`, which is stable but text-based.
# Cross-repo blockers (owner/repo#N) are resolved in text mode only.

set -euo pipefail

REPO_ARGS=()
SHOW_ALL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -R|--repo) REPO_ARGS=(--repo "$2"); shift 2 ;;
    --all)     SHOW_ALL=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }

# Collect blocker references for one issue, one per line.
# Emits either "123" (same repo) or "owner/repo#123" (cross-repo).
blockers_of() {
  local num="$1" json
  # Preferred: JSON field (field name may vary by gh version; fall back on error).
  if json=$(gh issue view "$num" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json blockedBy 2>/dev/null); then
    printf '%s\n' "$json" | grep -o '"number":[[:space:]]*[0-9]\+' | grep -o '[0-9]\+' || true
    return 0
  fi
  # Fallback: parse the "Blocked by:" row of the default text output.
  gh issue view "$num" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} 2>/dev/null \
    | awk '/^Blocked by:/ {print}' \
    | grep -oE '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' \
    | sed 's/^#//' || true
}

# Return 0 if the referenced blocker issue is CLOSED.
blocker_closed() {
  local ref="$1" state
  if [[ "$ref" == */*#* ]]; then
    local repo="${ref%%#*}" n="${ref##*#}"
    state=$(gh issue view "$n" --repo "$repo" --json state -q .state 2>/dev/null || echo "UNKNOWN")
  else
    state=$(gh issue view "$ref" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json state -q .state 2>/dev/null || echo "UNKNOWN")
  fi
  [[ "$state" == "CLOSED" ]]
}

# Read line-by-line instead of `mapfile` (a bash 4+ builtin absent from the
# bash 3.2 that ships as /bin/bash on macOS, where this script also runs).
# ${arr[@]+"${arr[@]}"} guards the empty-array expansion, which is an unbound
# variable under `set -u` on bash 3.2 (macOS /bin/bash); fixed in bash 4.4.
CANDIDATES=()
while IFS= read -r cand; do CANDIDATES+=("$cand"); done < <(gh issue list \
  ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --state open --label "type:task" \
  --label "ai:ready" --limit 200 \
  --json number,title \
  --template '{{range .}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}')

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  echo "No open Task issues labeled ai:ready."
  exit 0
fi

echo "== Actionable frontier (open, type:task + ai:ready, no open blockers) =="
BLOCKED_REPORT=""
for line in "${CANDIDATES[@]}"; do
  num="${line%%$'\t'*}"
  title="${line#*$'\t'}"
  open_blockers=""
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if ! blocker_closed "$ref"; then
      open_blockers+="${open_blockers:+, }${ref}"
    fi
  done < <(blockers_of "$num")

  if [[ -z "$open_blockers" ]]; then
    printf '#%s\t%s\n' "$num" "$title"
  else
    BLOCKED_REPORT+=$(printf '#%s\t%s\t(waiting on: %s)\n' "$num" "$title" "$open_blockers")
    BLOCKED_REPORT+=$'\n'
  fi
done

if $SHOW_ALL && [[ -n "$BLOCKED_REPORT" ]]; then
  echo
  echo "== Blocked (ai:ready but waiting on open blockers) =="
  printf '%s' "$BLOCKED_REPORT"
fi
