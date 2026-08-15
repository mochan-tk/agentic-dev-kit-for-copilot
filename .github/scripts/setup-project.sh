#!/usr/bin/env bash
# setup-project.sh — bootstrap a GitHub Projects (v2) roadmap board, add
# Task/Epic issues, and set dates only when real schedule spans exist.
#
# Idempotent: `init` reuses an open project with the same title, skips
# date fields that already exist, and re-links safely; `add` and `dates`
# reuse the project item when the issue is already on the board.
#
# Usage:
#   setup-project.sh init  [--owner <login>] [--title <title>] [-R owner/repo]
#   setup-project.sh add   --project <number> --issue <n>
#                          [--owner <login>] [-R owner/repo]
#   setup-project.sh dates --project <number> --issue <n>
#                          --start YYYY-MM-DD --target YYYY-MM-DD
#                          [--owner <login>] [-R owner/repo]
#   setup-project.sh --help
#
# Subcommands:
#   init   Create (or reuse) a Projects v2 board titled "<repo> roadmap" by
#          default, add DATE fields `Start date` and `Target date` and a
#          SINGLE_SELECT field `Kind` (options Epic, Task) if missing, create
#          the `Roadmap`, `Kanban` and `Backlog` views if missing, link
#          the project to the repository, and print the project number and
#          URL. Re-running is a no-op. Projects v2 boards are always
#          user/org-owned (repo-owned boards no longer exist); the repo
#          link makes the board show up in the repository's Projects tab.
#   add    Add issue <n> to project <number> without inventing dates. Also
#          sets `Kind` from `type:epic` / `type:task` when available.
#   dates  Add issue <n> to project <number> (reusing the item when already
#          present) and set both date fields. Dates must be YYYY-MM-DD; a
#          target date earlier than the start date is rejected. Also sets
#          the `Kind` field from the issue's labels (`type:epic` -> Epic,
#          `type:task` -> Task) when the field and a matching label exist.
#
# Options:
#   --owner <login>          Project owner login (user or org). Default: the
#                            owner of the target repository.
#   --title <title>          init: board title. Default: "<repo> roadmap".
#   --project <number>       add/dates: project number (printed by init).
#   --issue <n>              add/dates: issue number to add or schedule.
#   --start <YYYY-MM-DD>     dates: start date.
#   --target <YYYY-MM-DD>    dates: target date (not earlier than start).
#   -R, --repo <owner/repo>  Target repository. Default: the repository the
#                            current directory belongs to (via `gh repo view`).
#   -h, --help               Show this help and exit.
#
# Views are created by name (`Roadmap`, `Kanban`, `Backlog`) and matched by
# name on re-runs, so an adopter's own views are never renamed or removed.
# What stays manual: `createProjectV2View` takes only a name and a layout —
# its `configuration` input carries `visibleFieldIds` alone — so the Roadmap
# view's date fields and "Group by: Kind" must be set once in the UI.
#
# Requires: gh >= 2.45 (`gh project link`) authenticated with the `project`
# scope, and jq.
# Compatible with bash 3.2 (macOS /bin/bash).

set -euo pipefail

# Consent-gated adopter feedback (ADR-0002): on an unguarded failure in an
# interactive run, offer - default no, full preview, allowlist-only - to
# file the failure upstream. Lib absent or any gate closed: byte-identical.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" ]; then
  # shellcheck source=/dev/null
  if . "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" 2>/dev/null; then
    feedback_arm setup-project || true
  fi
fi

# Print the header comment above (everything from line 2 to the first blank
# line), stripped of the leading `# ` — same self-documenting pattern as the
# other .github/scripts/ bootstrap scripts.
usage() { sed -n '2,/^$/{s/^# \{0,1\}//p;}' "$0"; }

fail() { echo "error: $*" >&2; exit 1; }

usage_error() {
  echo "error: $*" >&2
  echo "Run '$(basename "$0") --help' for usage." >&2
  exit 2
}

require_tools() {
  command -v gh >/dev/null 2>&1 || fail "gh CLI not found on PATH"
  command -v jq >/dev/null 2>&1 || fail "jq not found on PATH"
  # Probe the token, not just the binary: an unauthenticated gh otherwise
  # fails later inside a project API call, where the error names the call
  # rather than the cause. Same probe and wording as the sibling setup
  # scripts.
  gh api user --jq .login >/dev/null 2>&1 \
    || fail "gh is not authenticated
  fix: run: gh auth login"
}

REPO=""
REPO_NAME=""
REPO_OWNER=""

resolve_repo() {
  if [[ -z "$REPO" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  fi
  [[ "$REPO" == */* ]] || usage_error "repository must be owner/repo, got: $REPO"
  REPO_NAME="${REPO##*/}"
  REPO_OWNER="${REPO%%/*}"
}

# Print the ID of the field named "$3" in project "$1" of owner "$2", or
# nothing when the field does not exist.
# `$name` below is a jq variable, not a shell expansion.
# shellcheck disable=SC2016
field_id() {
  gh project field-list "$1" --owner "$2" --limit 100 --format json \
    | jq -r --arg name "$3" \
        '[.fields[] | select(.name == $name) | .id] | first // empty'
}

# Print the ID of option "$4" of the single-select field named "$3" in
# project "$1" of owner "$2", or nothing when field or option is missing.
# `$name`/`$opt` below are jq variables, not shell expansions.
# shellcheck disable=SC2016
option_id() {
  gh project field-list "$1" --owner "$2" --limit 100 --format json \
    | jq -r --arg name "$3" --arg opt "$4" \
        '[.fields[] | select(.name == $name) | .options[]?
          | select(.name == $opt) | .id] | first // empty'
}

# Shared context for `add` and `dates`. Bash 3.2 has no namerefs, so these
# values are deliberately scoped with a prefix rather than returned through
# caller-owned variables.
PROJECT_NODE_ID=""
PROJECT_ITEM_ID=""
PROJECT_ISSUE_URL=""
PROJECT_ISSUE_LABELS=""

load_project_issue() {
  local project="$1" owner="$2" issue="$3" issue_json
  # Resolving the URL via the API also fails fast when the issue is missing.
  issue_json="$(gh issue view "$issue" --repo "$REPO" --json url,labels)"
  PROJECT_ISSUE_URL="$(jq -r '.url' <<<"$issue_json")"
  PROJECT_ISSUE_LABELS="$(jq -r '.labels[].name' <<<"$issue_json")"
  PROJECT_NODE_ID="$(gh project view "$project" --owner "$owner" \
    --format json --jq '.id')"
}

ensure_project_item() {
  local project="$1" owner="$2"
  # item-add is idempotent: when the issue is already on the board it
  # returns the existing item's ID instead of failing or duplicating.
  PROJECT_ITEM_ID="$(gh project item-add "$project" --owner "$owner" \
    --url "$PROJECT_ISSUE_URL" --format json --jq '.id')"
}

apply_kind() {
  local project="$1" owner="$2" issue="$3" kind=""
  if printf '%s\n' "$PROJECT_ISSUE_LABELS" | grep -Fxq "type:epic"; then
    kind="Epic"
  elif printf '%s\n' "$PROJECT_ISSUE_LABELS" | grep -Fxq "type:task"; then
    kind="Task"
  fi
  if [[ -z "$kind" ]]; then
    echo "Note: issue #$issue has neither 'type:epic' nor 'type:task' label;" \
      "leaving 'Kind' unset."
    return 0
  fi

  # Older boards (init run before the Kind field existed) stay usable:
  # setting Kind is best-effort, with a pointer to re-run init.
  local kind_field_id kind_option_id
  kind_field_id="$(field_id "$project" "$owner" "Kind")"
  if [[ -z "$kind_field_id" ]]; then
    echo "Note: project #$project has no 'Kind' field;" \
      "re-run 'setup-project.sh init' to add it."
    return 0
  fi
  kind_option_id="$(option_id "$project" "$owner" "Kind" "$kind")"
  [[ -n "$kind_option_id" ]] \
    || fail "field 'Kind' on project #$project has no '$kind' option"

  gh project item-edit --id "$PROJECT_ITEM_ID" \
    --project-id "$PROJECT_NODE_ID" --field-id "$kind_field_id" \
    --single-select-option-id "$kind_option_id" >/dev/null
  echo "Set Kind = $kind for issue #$issue."
}

cmd_init() {
  local owner="" title=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner)
        [[ -n "${2:-}" ]] || usage_error "--owner requires a login argument"
        owner="$2"; shift 2 ;;
      --title)
        [[ -n "${2:-}" ]] || usage_error "--title requires a value"
        title="$2"; shift 2 ;;
      -R|--repo)
        [[ -n "${2:-}" ]] || usage_error "$1 requires an owner/repo argument"
        REPO="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage_error "unknown argument for init: $1" ;;
    esac
  done
  require_tools
  resolve_repo
  # Projects v2 boards are user/org-owned, so default to the repo owner to
  # keep the board next to the repository it visualizes.
  [[ -n "$owner" ]] || owner="$REPO_OWNER"
  [[ -n "$title" ]] || title="$REPO_NAME roadmap"

  # Select strictly by exact title match among the owner's open projects, so
  # the script never touches a project it did not create or select itself.
  # `$title` is a jq variable, not a shell expansion.
  local number
  # shellcheck disable=SC2016
  number="$(gh project list --owner "$owner" --limit 100 --format json \
    | jq -r --arg title "$title" \
        '[.projects[] | select(.title == $title) | .number] | first // empty')"

  if [[ -n "$number" ]]; then
    echo "Reusing project #$number ('$title') owned by $owner."
  else
    # `gh project list` hides closed projects, so a same-title board that
    # was closed would otherwise be recreated as a duplicate (or, where the
    # org refuses API creation, dead-end). Detect it and instruct instead:
    # reopening a board a human deliberately closed is not this script's
    # call to make.
    local closed_number
    # shellcheck disable=SC2016
    closed_number="$(gh project list --owner "$owner" --closed --limit 100 \
      --format json | jq -r --arg title "$title" \
        '[.projects[] | select(.title == $title and .closed == true) | .number] | first // empty')"
    if [[ "$closed_number" =~ ^[1-9][0-9]*$ ]]; then
      fail "project '$title' owned by '$owner' exists but is closed \
(#$closed_number); reopen it with 'gh project close $closed_number --owner \
$owner --undo' and re-run init"
    fi
    number="$(gh project create --owner "$owner" --title "$title" \
      --format json --jq '.number')"
    # gh unmarshals API responses into Go structs, so a number missing from
    # a degraded response surfaces as Go's zero value 0 instead of an error
    # — and gh's project commands treat 0 as "no number supplied". The
    # create above just guaranteed a project with this exact title exists,
    # so re-resolve by title instead of trusting an unusable answer.
    if ! [[ "$number" =~ ^[1-9][0-9]*$ ]]; then
      # shellcheck disable=SC2016
      number="$(gh project list --owner "$owner" --limit 100 --format json \
        | jq -r --arg title "$title" \
            '[.projects[] | select(.title == $title) | .number] | first // empty')"
    fi
    echo "Created project #$number ('$title') owned by $owner."
  fi

  # Both paths above parse gh output; never hand follow-up commands a
  # number that cannot address a project.
  [[ "$number" =~ ^[1-9][0-9]*$ ]] || fail "could not determine the number \
of project '$title' owned by '$owner'. Inspect 'gh project list --owner \
$owner --closed'. Some orgs/enterprises silently refuse API project \
creation while the web UI works — in that case create (or rename) a \
board titled exactly '$title' in the web UI and re-run init; init will \
reuse it and complete the fields and the repository link"

  # Creating a field whose name is taken fails, so check before creating.
  local existing_fields field_name
  existing_fields="$(gh project field-list "$number" --owner "$owner" \
    --limit 100 --format json | jq -r '.fields[].name')"
  for field_name in "Start date" "Target date"; do
    if printf '%s\n' "$existing_fields" | grep -Fxq "$field_name"; then
      echo "Field '$field_name' already exists; skipping."
    else
      gh project field-create "$number" --owner "$owner" \
        --name "$field_name" --data-type DATE >/dev/null
      echo "Created DATE field '$field_name'."
    fi
  done

  # Single-select field distinguishing Epics from Tasks on the board.
  if printf '%s\n' "$existing_fields" | grep -Fxq "Kind"; then
    echo "Field 'Kind' already exists; skipping."
  else
    gh project field-create "$number" --owner "$owner" \
      --name "Kind" --data-type SINGLE_SELECT \
      --single-select-options "Epic,Task" >/dev/null
    echo "Created SINGLE_SELECT field 'Kind' (Epic, Task)."
  fi

  # Working views. `createProjectV2View` takes a name and a layout; its
  # `configuration` input carries only `visibleFieldIds`, so grouping and the
  # roadmap's date fields cannot be set through the API and stay manual.
  # Matched by name, so an adopter's own views are never renamed or removed.
  local project_id existing_views view_spec view_name view_layout
  project_id="$(gh project view "$number" --owner "$owner" --format json --jq '.id')"
  # shellcheck disable=SC2016  # $id is a GraphQL variable, not a shell expansion
  existing_views="$(gh api graphql -f query='
    query($id: ID!) {
      node(id: $id) { ... on ProjectV2 { views(first: 50) { nodes { name } } } }
    }' -f id="$project_id" --jq '.data.node.views.nodes[].name' 2>/dev/null || true)"

  for view_spec in "Roadmap:ROADMAP_LAYOUT" "Kanban:BOARD_LAYOUT" "Backlog:TABLE_LAYOUT"; do
    view_name="${view_spec%%:*}"
    view_layout="${view_spec##*:}"
    if printf '%s\n' "$existing_views" | grep -Fxq "$view_name"; then
      echo "View '$view_name' already exists; skipping."
      continue
    fi
    # A board still sets up without its views: Projects permissions vary by
    # account and organization, so a refusal here warns rather than aborts.
    # shellcheck disable=SC2016  # $p/$n/$l are GraphQL variables, not shell expansions
    if gh api graphql -f query='
      mutation($p: ID!, $n: String!, $l: ProjectV2ViewLayout!) {
        createProjectV2View(input: {projectId: $p, name: $n, layout: $l}) {
          projectV2View { id }
        }
      }' -f p="$project_id" -f n="$view_name" -f l="$view_layout" >/dev/null 2>&1; then
      echo "Created '$view_name' view ($view_layout)."
    else
      echo "warning: could not create the '$view_name' view; add it in the"
      echo "         project UI (New view -> ${view_layout%%_*} layout)."
    fi
  done

  # Safe to repeat: linking an already-linked repository succeeds silently.
  gh project link "$number" --owner "$owner" --repo "$REPO"
  echo "Linked project #$number to $REPO."
  echo "The board is owned by '$owner' (Projects v2 boards are always"
  echo "user/org-owned) and, via this link, is visible in the repository's"
  echo "Projects tab: https://github.com/$REPO/projects"

  local url
  url="$(gh project view "$number" --owner "$owner" --format json --jq '.url')"
  echo "Project number: $number"
  echo "Project URL:    $url"
  echo "Remaining manual step: open the Roadmap view and pick 'Start date' /"
  echo "'Target date' as its date fields, then set 'Group by' to 'Kind' to"
  echo "separate Epics from Tasks — the API creates views but cannot configure"
  echo "grouping or date fields."
}

cmd_add() {
  local owner="" project="" issue=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner)
        [[ -n "${2:-}" ]] || usage_error "--owner requires a login argument"
        owner="$2"; shift 2 ;;
      --project)
        [[ -n "${2:-}" ]] || usage_error "--project requires a project number"
        project="$2"; shift 2 ;;
      --issue)
        [[ -n "${2:-}" ]] || usage_error "--issue requires an issue number"
        issue="$2"; shift 2 ;;
      -R|--repo)
        [[ -n "${2:-}" ]] || usage_error "$1 requires an owner/repo argument"
        REPO="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage_error "unknown argument for add: $1" ;;
    esac
  done
  [[ -n "$project" && -n "$issue" ]] \
    || usage_error "add requires --project and --issue"

  local num_re='^[0-9]+$'
  [[ "$project" =~ $num_re ]] \
    || usage_error "--project must be a number, got: $project"
  [[ "$issue" =~ $num_re ]] \
    || usage_error "--issue must be a number, got: $issue"

  require_tools
  resolve_repo
  [[ -n "$owner" ]] || owner="$REPO_OWNER"

  load_project_issue "$project" "$owner" "$issue"
  ensure_project_item "$project" "$owner"
  echo "Added/reused issue #$issue ($REPO) on project #$project."
  apply_kind "$project" "$owner" "$issue"
}

cmd_dates() {
  local owner="" project="" issue="" start="" target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner)
        [[ -n "${2:-}" ]] || usage_error "--owner requires a login argument"
        owner="$2"; shift 2 ;;
      --project)
        [[ -n "${2:-}" ]] || usage_error "--project requires a project number"
        project="$2"; shift 2 ;;
      --issue)
        [[ -n "${2:-}" ]] || usage_error "--issue requires an issue number"
        issue="$2"; shift 2 ;;
      --start)
        [[ -n "${2:-}" ]] || usage_error "--start requires a YYYY-MM-DD date"
        start="$2"; shift 2 ;;
      --target)
        [[ -n "${2:-}" ]] || usage_error "--target requires a YYYY-MM-DD date"
        target="$2"; shift 2 ;;
      -R|--repo)
        [[ -n "${2:-}" ]] || usage_error "$1 requires an owner/repo argument"
        REPO="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage_error "unknown argument for dates: $1" ;;
    esac
  done
  [[ -n "$project" && -n "$issue" && -n "$start" && -n "$target" ]] \
    || usage_error "dates requires --project, --issue, --start and --target"

  # Patterns live in variables: quoted regexes break on bash 3.2.
  local num_re='^[0-9]+$' date_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  [[ "$project" =~ $num_re ]] || usage_error "--project must be a number, got: $project"
  [[ "$issue" =~ $num_re ]] || usage_error "--issue must be a number, got: $issue"
  [[ "$start" =~ $date_re ]] || usage_error "--start must be YYYY-MM-DD, got: $start"
  [[ "$target" =~ $date_re ]] || usage_error "--target must be YYYY-MM-DD, got: $target"
  # ISO dates order correctly as strings, so [[ < ]] compares dates.
  if [[ "$target" < "$start" ]]; then
    usage_error "--target ($target) is earlier than --start ($start)"
  fi

  require_tools
  resolve_repo
  [[ -n "$owner" ]] || owner="$REPO_OWNER"

  local start_field_id target_field_id
  load_project_issue "$project" "$owner" "$issue"
  start_field_id="$(field_id "$project" "$owner" "Start date")"
  target_field_id="$(field_id "$project" "$owner" "Target date")"
  [[ -n "$start_field_id" && -n "$target_field_id" ]] \
    || fail "project #$project has no 'Start date'/'Target date' fields — run 'setup-project.sh init' first"

  ensure_project_item "$project" "$owner"

  gh project item-edit --id "$PROJECT_ITEM_ID" --project-id "$PROJECT_NODE_ID" \
    --field-id "$start_field_id" --date "$start" >/dev/null
  gh project item-edit --id "$PROJECT_ITEM_ID" --project-id "$PROJECT_NODE_ID" \
    --field-id "$target_field_id" --date "$target" >/dev/null

  echo "Scheduled issue #$issue ($REPO) on project #$project:" \
    "Start date $start, Target date $target."

  apply_kind "$project" "$owner" "$issue"
}

case "${1:-}" in
  init)      shift; cmd_init "$@" ;;
  add)       shift; cmd_add "$@" ;;
  dates)     shift; cmd_dates "$@" ;;
  -h|--help) usage; exit 0 ;;
  "")        usage_error "missing subcommand (init, add or dates)" ;;
  *)         usage_error "unknown subcommand: $1" ;;
esac
