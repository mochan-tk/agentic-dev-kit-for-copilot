#!/usr/bin/env bash
# new-task.sh — create a Task issue wired into the plan graph in one step.
#
# Usage:
#   new-task.sh -t "Title" -b body.md -p <epic-number> -e <cloud|app|cli|ide> \
#               [-d "14,15"] [-R owner/repo] [--ready]
#
#   -t  Task title (required)
#   -b  Path to a body file following .github/ISSUE_TEMPLATE/ai-task.yml
#       sections (required; start from ../templates/task-body.md)
#   -p  Parent Epic issue number (required)
#   -e  Execution surface -> adds label exec:<value> (required)
#   -d  Comma-separated issue numbers this task is blocked by (optional)
#   -R  Target repository (optional; defaults to current repo)
#   --ready  Also add the ai:ready label (only when the brief is complete)
#
# Requires: GitHub CLI (gh) >= 2.94 for --parent and --blocked-by.

set -euo pipefail

TITLE="" BODY="" PARENT="" EXEC="" DEPS="" READY=false
REPO_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) TITLE="$2"; shift 2 ;;
    -b) BODY="$2"; shift 2 ;;
    -p) PARENT="$2"; shift 2 ;;
    -e) EXEC="$2"; shift 2 ;;
    -d) DEPS="$2"; shift 2 ;;
    -R) REPO_ARGS=(--repo "$2"); shift 2 ;;
    --ready) READY=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TITLE" && -n "$BODY" && -n "$PARENT" && -n "$EXEC" ]] || {
  echo "error: -t, -b, -p and -e are required (see --help)" >&2; exit 2; }
[[ -f "$BODY" ]] || { echo "error: body file not found: $BODY" >&2; exit 2; }
case "$EXEC" in cloud|app|cli|ide) ;; *)
  echo "error: -e must be one of: cloud, app, cli, ide" >&2; exit 2 ;; esac
command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }

LABELS="type:task,exec:${EXEC}"
$READY && LABELS+=",ai:ready"

# One creation call wires parent, labels, and dependencies atomically —
# a create-then-edit sequence could leak an unwired task into the frontier
# if the edit step failed.
CREATE_ARGS=(--title "$TITLE" --body-file "$BODY" \
  --label "$LABELS" --parent "$PARENT")
if [[ -n "$DEPS" ]]; then
  CREATE_ARGS+=(--blocked-by "$DEPS")
fi

# ${arr[@]+...} guards the empty-array expansion that aborts under `set -u`
# on macOS bash 3.2 (same idiom as .github/scripts/tuning-status.sh).
URL=$(gh issue create ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "${CREATE_ARGS[@]}")
NUM="${URL##*/}"
echo "Created task #${NUM} under epic #${PARENT}: ${URL}"

if [[ -n "$DEPS" ]]; then
  echo "Wired dependencies: #${NUM} blocked by ${DEPS}"
fi

echo "Next: verify the brief, then dispatch when it appears in frontier.sh output."
