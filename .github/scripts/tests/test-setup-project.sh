#!/usr/bin/env bash
# test-setup-project.sh — regression tests for .github/scripts/setup-project.sh.
#
# Scope here: the working views `init` ensures on the roadmap board. The
# script talks to GitHub through `gh project …` and `gh api graphql`; the
# shim below answers both from per-case fixtures, so no network, no auth and
# no Projects permissions are needed.
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
      view)  printf '{"id":"PVT_test","url":"https://github.com/orgs/o/projects/6"}\n' ;;
      field-list) printf '{"fields":[{"name":"Start date"},{"name":"Target date"},{"name":"Kind"}]}\n' ;;
      link)  : ;;
      *)     : ;;
    esac
    ;;
  api)
    # The only GraphQL reads/writes the script makes on the project surface.
    args="$*"
    case "$args" in
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
  *) : ;;
esac
SHIM
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

run_init() {
  VIEWS_FIXTURE="$1" CREATED_LOG="$2" CREATE_FAILS="${3:-0}" \
    bash "$SCRIPT" init --owner o -R o/r 2>&1
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

t_summary
