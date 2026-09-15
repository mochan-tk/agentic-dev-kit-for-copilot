#!/usr/bin/env bash
# frontier.sh — print the actionable frontier of the plan.
#
# Frontier = open issues labeled `type:task` and `ai:ready` whose "Blocked by"
# issues are all CLOSED. Recheck claims, ownership and authorization before
# dispatch. Epics never qualify: they are outline items, not work orders.
#
# Usage:
#   frontier.sh [-R owner/repo] [--all]
#     -R, --repo   Target repository (defaults to the current directory's repo).
#     --all        Also list blocked ai:ready issues with their open blockers.
#
# Requires: gh (>= 2.94 recommended), jq. Prefer complete blockedBy nodes/count
# JSON with canonical HTTPS github.com issue URLs for blocker identity.
# On query failure accept only an explicit, validated legacy metadata row.
# Unknown discovery exits nonzero without output. Reads never mutate GitHub.

set -euo pipefail

REPO_ARGS=()
SHOW_ALL=false
die() { echo "error: $*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -R|--repo)
      [[ $# -ge 2 && -n "$2" ]] || die "$1 requires owner/repo"
      REPO_ARGS=(--repo "$2"); shift 2 ;;
    --all)     SHOW_ALL=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

# Command substitutions return data and status; never stream unchecked results.
blockers_of() {
  local num="$1" json text
  if json=$(gh issue view "$num" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json blockedBy 2>/dev/null); then
    printf '%s\n' "$json" | jq -ers '
      def invalid: error("invalid or incomplete blockedBy");
      if length != 1 then invalid else .[0].blockedBy end |
      if type != "object" then invalid
      elif (.nodes|type) != "array" or (.totalCount|type) != "number" then invalid
      elif .totalCount != (.nodes|length) then invalid else .nodes end |
      map(
        if type != "object" then invalid
        elif (.number|type) != "number" then invalid
        elif .number < 1 or .number != (.number|floor) then invalid
        elif (.url|type) != "string" then invalid
        else
          (.url | capture("\\Ahttps://github\\.com/(?<owner>[A-Za-z0-9][A-Za-z0-9-]*)/(?<repo>[A-Za-z0-9_.-]+)/issues/(?<number>[1-9][0-9]*)\\z")
            // invalid) as $identity |
          if $identity.repo == "." or $identity.repo == ".."
            or $identity.number != (.number|tostring) then invalid
          else "\($identity.owner|ascii_downcase)/\($identity.repo|ascii_downcase)#\(.number)" end
        end
      ) | if length != (unique|length) then invalid else join("\n") end'
  else
    text=$(gh issue view "$num" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} 2>/dev/null) || return 1
    # Missing metadata is unknown. Never match a dependency-looking body line.
    # gh truncates linked issues at 50; legacy text has no count to resolve it.
    printf '%s\n' "$text" | jq -eRrs --arg repo "$REPO" '
      def invalid: error("uncheckable legacy blocked-by metadata");
      split("\n") | .[0:(index("--") // length)] |
      map(select(test("^(Blocked by:|blocked-by:)"))) |
      if length != 1 then invalid else .[0] end |
      sub("^[^:]*:[ \t]*";"") | sub("[ \t]+$";"") |
      if . == "" then []
      elif test("^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[1-9][0-9]*([, \t]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[1-9][0-9]*)*$")
      then [splits("[, \t]+") | if startswith("#") then $repo + . else . end | ascii_downcase]
      else invalid end |
      if length >= 50 or length != (unique|length) then invalid else join("\n") end'
  fi
}

# Parallel indexed arrays work on Bash 3.2. Call in the parent shell so writes
# survive; STATE is the result, not stdout from a cache-losing subshell.
CACHE_KEYS=()
CACHE_STATES=()
blocker_state() {
  local ref="$1" i
  for ((i=0; i<${#CACHE_KEYS[@]}; i++)); do
    if [[ "${CACHE_KEYS[$i]}" == "$ref" ]]; then STATE="${CACHE_STATES[$i]}"; return; fi
  done
  STATE=$(gh issue view "${ref##*#}" --repo "${ref%%#*}" --json state -q .state 2>/dev/null) \
    || die "Task #$num: blocker $ref state read failed"
  [[ "$STATE" == CLOSED || "$STATE" == OPEN ]] || die "Task #$num: blocker $ref has unknown state"
  CACHE_KEYS+=("$ref")
  CACHE_STATES+=("$STATE")
}

# Guard empty-array expansion for Bash 3.2 with set -u.
CANDIDATES=$(gh issue list \
  ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --state open --label "type:task" \
  --label "ai:ready" --limit 200 \
  --json number,title \
  --template '{{range .}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}') \
  || die "candidate list read failed"

if [[ -z "$CANDIDATES" ]]; then
  echo "No open Task issues labeled ai:ready."
  exit 0
fi

REPO="${REPO_ARGS[1]:-}"
if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die "candidate repository resolution failed"
fi
REPO=$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')
[[ "$REPO" =~ ^[a-z0-9_.-]+/[a-z0-9_.-]+$ ]] || die "invalid candidate repository identity"
READY_REPORT=""
BLOCKED_REPORT=""
while IFS= read -r line; do
  num="${line%%$'\t'*}"
  title="${line#*$'\t'}"
  [[ "$line" == *$'\t'* && "$num" =~ ^[1-9][0-9]*$ && -n "$title" ]] \
    || die "invalid candidate row: $line"
  refs=$(blockers_of "$num") || die "Task #$num: dependency discovery failed or incomplete"
  open_blockers=""
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    blocker_state "$ref"
    if [[ "$STATE" == OPEN ]]; then
      [[ "${ref%%#*}" != "$REPO" ]] || ref="${ref##*#}"
      open_blockers+="${open_blockers:+, }${ref}"
    fi
  done <<< "$refs"

  if [[ -z "$open_blockers" ]]; then
    READY_REPORT+=$(printf '#%s\t%s' "$num" "$title")
    READY_REPORT+=$'\n'
  else
    BLOCKED_REPORT+=$(printf '#%s\t%s\t(waiting on: %s)\n' "$num" "$title" "$open_blockers")
    BLOCKED_REPORT+=$'\n'
  fi
done <<< "$CANDIDATES"

echo "== Actionable frontier (open, type:task + ai:ready, no open blockers) =="
printf '%s' "$READY_REPORT"
if $SHOW_ALL && [[ -n "$BLOCKED_REPORT" ]]; then
  echo
  echo "== Blocked (ai:ready but waiting on open blockers) =="
  printf '%s' "$BLOCKED_REPORT"
fi
