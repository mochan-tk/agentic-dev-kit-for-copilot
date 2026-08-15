#!/usr/bin/env bash
# test-setup-project.sh — regression tests for .github/scripts/setup-project.sh.
#
# Scope here: the working views `init` ensures and the item paths shared by
# `add` / `dates`. The script talks to GitHub through `gh project …`,
# `gh issue …`, and `gh api graphql`; the shim below answers all three, so no
# network, auth, or Projects permissions are needed.
#
# Why views are worth a guard: `createProjectV2View` accepts only a name and
# a layout, and the board is created once per adopting repository, so a
# silent regression here is invisible until an adopter opens the board.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SCRIPT="$REPO_ROOT/.github/scripts/setup-project.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/projtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# A `gh` stand-in for the project surface. Existing views come from
# $VIEWS_FIXTURE (one name per line); every createProjectV2View call appends
# its arguments to $CREATED_LOG. CREATE_FAILS=1 makes creation refuse, which
# models an account without Projects write access.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  project)
    case "${2:-}" in
      list)  printf '{"projects":[{"number":6,"title":"r roadmap","closed":false}]}\n' ;;
      view)
        case "$*" in
          *".url"*) printf 'https://github.com/orgs/o/projects/6\n' ;;
          *)        printf 'PVT_test\n' ;;
        esac
        ;;
      field-list)
        printf '%s\n' '{"fields":[{"id":"F_START","name":"Start date"},{"id":"F_TARGET","name":"Target date"},{"id":"F_KIND","name":"Kind","options":[{"id":"O_EPIC","name":"Epic"},{"id":"O_TASK","name":"Task"}]}]}'
        ;;
      item-add)
        printf '%s\n' "$*" >> "$ITEM_ADD_LOG"
        # The real command carries `--jq .id`, so emit the projected value,
        # not the pre-jq JSON object.
        printf 'PVTI_existing\n'
        ;;
      item-edit)
        printf '%s\n' "$*" >> "$ITEM_EDIT_LOG"
        ;;
      link)  : ;;
      *)     : ;;
    esac
    ;;
  api)
    # `$*` still holds the leading `api`, so match on the path that follows.
    args="$*"
    case "$args" in
      "api user"*)
        # The auth preflight probes `gh api user`. AUTHED=0 models an
        # unauthenticated gh, which the real CLI reports as a failed call.
        [ "${AUTHED:-1}" = "1" ] || exit 1
        printf 'octocat\n'
        ;;
      *createProjectV2View*)
        [ "${CREATE_FAILS:-0}" = "1" ] && exit 1
        printf '%s\n' "$args" >> "$CREATED_LOG"
        printf '{"data":{"createProjectV2View":{"projectV2View":{"id":"PVTV_x"}}}}\n'
        ;;
      *views*)
        # --jq '.data.node.views.nodes[].name' is applied by real gh; the
        # shim emits the already-projected list the script consumes.
        cat "$VIEWS_FIXTURE"
        ;;
      *) : ;;
    esac
    ;;
  repo) printf 'o/r\n' ;;
  issue)
    printf '{"url":"https://github.com/o/r/issues/%s","labels":%s}\n' \
      "${3:-42}" "${ISSUE_LABELS_JSON:-[]}"
    ;;
  *) : ;;
esac
SHIM
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

run_init() {
  VIEWS_FIXTURE="$1" CREATED_LOG="$2" CREATE_FAILS="${3:-0}" AUTHED="${AUTHED:-1}" \
    bash "$SCRIPT" init --owner o -R o/r 2>&1
}

run_add() {
  ITEM_ADD_LOG="$1" ITEM_EDIT_LOG="$2" ISSUE_LABELS_JSON="$3" \
    bash "$SCRIPT" add --owner o --project 6 --issue 42 -R o/r 2>&1
}

run_dates() {
  ITEM_ADD_LOG="$1" ITEM_EDIT_LOG="$2" ISSUE_LABELS_JSON="$3" \
    bash "$SCRIPT" dates --owner o --project 6 --issue 42 \
      --start 2026-08-01 --target 2026-08-05 -R o/r 2>&1
}

# --- an empty board gains all three views ---------------------------------
: > "$WORK/views-none.txt"
: > "$WORK/created-none.log"
out=$(run_init "$WORK/views-none.txt" "$WORK/created-none.log")
missing=""
for v in Roadmap Kanban Backlog; do
  grep -q "$v" "$WORK/created-none.log" || missing="$missing $v"
done
if [ -z "$missing" ]; then
  t_ok "init creates Roadmap, Kanban and Backlog on a bare board"
else
  t_fail "init creates Roadmap, Kanban and Backlog on a bare board (missing:$missing)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# Each view must ask for its own layout, or the board looks right and reads wrong.
layouts_ok=1
grep -q 'Roadmap.*ROADMAP_LAYOUT\|ROADMAP_LAYOUT.*Roadmap' "$WORK/created-none.log" || layouts_ok=0
grep -q 'Kanban.*BOARD_LAYOUT\|BOARD_LAYOUT.*Kanban' "$WORK/created-none.log" || layouts_ok=0
grep -q 'Backlog.*TABLE_LAYOUT\|TABLE_LAYOUT.*Backlog' "$WORK/created-none.log" || layouts_ok=0
if [ "$layouts_ok" = "1" ]; then
  t_ok "each view is created with its own layout"
else
  t_fail "each view is created with its own layout"
  sed 's/^/    # /' "$WORK/created-none.log"
fi

# --- re-running creates nothing -------------------------------------------
printf 'Roadmap\nKanban\nBacklog\n' > "$WORK/views-all.txt"
: > "$WORK/created-all.log"
run_init "$WORK/views-all.txt" "$WORK/created-all.log" >/dev/null
if [ ! -s "$WORK/created-all.log" ]; then
  t_ok "re-running an already-viewed board creates nothing"
else
  t_fail "re-running an already-viewed board creates nothing"
  sed 's/^/    # /' "$WORK/created-all.log"
fi

# --- a partially built board gains only what is missing -------------------
# An adopter who made a Kanban view by hand keeps it; the other two appear.
printf 'Kanban\n' > "$WORK/views-partial.txt"
: > "$WORK/created-partial.log"
run_init "$WORK/views-partial.txt" "$WORK/created-partial.log" >/dev/null
if grep -q 'Roadmap' "$WORK/created-partial.log" \
   && grep -q 'Backlog' "$WORK/created-partial.log" \
   && ! grep -q '"Kanban"' "$WORK/created-partial.log"; then
  t_ok "a partially built board gains only the missing views"
else
  t_fail "a partially built board gains only the missing views"
  sed 's/^/    # /' "$WORK/created-partial.log"
fi

# --- refused creation warns but does not abort setup ----------------------
# Projects write access varies by account; losing the views must not cost
# the adopter the board and its fields.
: > "$WORK/views-fail.txt"
: > "$WORK/created-fail.log"
out=$(run_init "$WORK/views-fail.txt" "$WORK/created-fail.log" 1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'warning: could not create'; then
  t_ok "a refused view creation warns and setup still completes"
else
  t_fail "a refused view creation warns and setup still completes (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- unauthenticated gh stops the run at the preflight ---------------------
# Without this guard the script proceeds and fails later inside a project API
# call, where the error names the call rather than the cause. The three
# sibling setup scripts have had this probe all along.
: > "$WORK/views-auth.txt"
: > "$WORK/created-auth.log"
out=$(AUTHED=0 run_init "$WORK/views-auth.txt" "$WORK/created-auth.log")
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'gh is not authenticated'; then
  t_ok "unauthenticated gh fails at the preflight"
else
  t_fail "unauthenticated gh fails at the preflight (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi
if printf '%s\n' "$out" | grep -q 'gh auth login'; then
  t_ok "the preflight names the fix"
else
  t_fail "the preflight names the fix"
fi
# Stopping *before* any project call is the point: a guard that fires after
# the board is half-built is not a preflight.
if [ ! -s "$WORK/created-auth.log" ] \
   && ! printf '%s\n' "$out" | grep -q 'Reusing project\|Created DATE field'; then
  t_ok "the preflight stops before touching the project"
else
  t_fail "the preflight stops before touching the project"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- add places an undated Epic and sets Kind ------------------------------
: > "$WORK/item-add-epic.log"
: > "$WORK/item-edit-epic.log"
out=$(run_add "$WORK/item-add-epic.log" "$WORK/item-edit-epic.log" \
  '[{"name":"type:epic"}]')
rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q 'item-add.*--url https://github.com/o/r/issues/42' \
      "$WORK/item-add-epic.log" \
   && grep -q -- '--single-select-option-id O_EPIC' \
      "$WORK/item-edit-epic.log"; then
  t_ok "add places an undated Epic and sets Kind"
else
  t_fail "add places an undated Epic and sets Kind (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi
if grep -q -- '--date' "$WORK/item-edit-epic.log"; then
  t_fail "add does not write dates"
else
  t_ok "add does not write dates"
fi

# --- add derives Task Kind through the same helper -------------------------
: > "$WORK/item-add-task.log"
: > "$WORK/item-edit-task.log"
run_add "$WORK/item-add-task.log" "$WORK/item-edit-task.log" \
  '[{"name":"type:task"}]' >/dev/null
if grep -q -- '--single-select-option-id O_TASK' "$WORK/item-edit-task.log"; then
  t_ok "add derives Task Kind from the issue label"
else
  t_fail "add derives Task Kind from the issue label"
fi

# --- re-adding reuses the item ID returned by GitHub -----------------------
: > "$WORK/item-add-twice.log"
: > "$WORK/item-edit-twice.log"
run_add "$WORK/item-add-twice.log" "$WORK/item-edit-twice.log" \
  '[{"name":"type:epic"}]' >/dev/null
run_add "$WORK/item-add-twice.log" "$WORK/item-edit-twice.log" \
  '[{"name":"type:epic"}]' >/dev/null
if [ "$(grep -c -- '--id PVTI_existing' "$WORK/item-edit-twice.log")" -eq 2 ]; then
  t_ok "re-adding reuses the existing project item ID"
else
  t_fail "re-adding reuses the existing project item ID"
fi

# --- dates still writes two dates and applies Kind -------------------------
: > "$WORK/item-add-dates.log"
: > "$WORK/item-edit-dates.log"
run_dates "$WORK/item-add-dates.log" "$WORK/item-edit-dates.log" \
  '[{"name":"type:task"}]' >/dev/null
date_edits=$(grep -c -- '--date 2026-08-' "$WORK/item-edit-dates.log")
if [ "$date_edits" -eq 2 ] \
   && grep -q -- '--single-select-option-id O_TASK' \
      "$WORK/item-edit-dates.log"; then
  t_ok "dates writes the real span and shares Kind handling"
else
  t_fail "dates writes the real span and shares Kind handling"
fi

t_summary
