#!/usr/bin/env bash
# Offline discovery, failure atomicity, and per-invocation call budgets.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"
SENSOR="$ROOT/.github/skills/plan-management/scripts/frontier.sh"
printf '# interpreter: BASH=%s BASH_VERSION=%s; all frontier children use this executable\n' "$BASH" "$BASH_VERSION"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/frontier-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/fixtures"
cat > "$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FIXTURES/calls"
unexpected() {
  printf '%s\n' "$*" >> "$FIXTURES/unexpected"
  echo "unexpected gh command: $*" >&2
  exit 64
}
if [[ "$*" == "repo view --json nameWithOwner --jq .nameWithOwner" ]]; then
  cat "$FIXTURES/repo"; exit
fi
[[ "${1:-} ${2:-}" == "issue list" || "${1:-} ${2:-}" == "issue view" ]] || unexpected "$@"
kind="$2"; shift 2
if [[ "$kind" == view ]]; then num="$1"; shift; fi
repo=""
if [[ "${1:-}" == --repo ]]; then repo="$2"; shift 2; fi
if [[ "$kind" == list ]]; then
  [[ "$repo" == "$EXPECTED_REPO" && "$*" == '--state open --label type:task --label ai:ready --limit 200 --json number,title --template {{range .}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}' ]] || unexpected list "$@"
  [[ ! -f "$FIXTURES/list.fail" ]] || exit 1
  cat "$FIXTURES/list"; exit
fi
repo="${repo:-fixture/repo}"
key="${repo//\//_}-$num"
case "$*" in
  "--json blockedBy") file="$FIXTURES/$key.json" ;;
  "") file="$FIXTURES/$key.text" ;;
  "--json state -q .state") file="$FIXTURES/$key.state" ;;
  *) unexpected view "$@" ;;
esac
[[ ! -f "$file.fail" ]] || exit 1
[[ -f "$file" ]] || unexpected "missing fixture $key $*"
cat "$file"
MOCK
chmod +x "$WORK/bin/gh"

setup() {
  find "$WORK/fixtures" -type f -delete
  printf 'fixture/repo\n' > "$WORK/fixtures/repo"
  printf '1\tTask 1\n' > "$WORK/fixtures/list"
  printf '{"blockedBy":{"nodes":[],"totalCount":0}}\n' > "$WORK/fixtures/fixture_repo-1.json"
  : > "$WORK/fixtures/calls"
}
dependencies() {
  local task="$1"; shift
  jq -n --args '{blockedBy:{nodes:[$ARGS.positional[] | split("#") |
    {number:(.[1]|tonumber),repository:{nameWithOwner:.[0]}}],
    totalCount:($ARGS.positional|length)}}' "$@" > "$WORK/fixtures/fixture_repo-$task.json"
}
run() {
  local expected_repo=fixture/repo
  [[ "${1:-}" != default ]] || { expected_repo=""; shift; }
  RC=0
  env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" GH_CONFIG_DIR="$WORK/home" \
    FIXTURES="$WORK/fixtures" EXPECTED_REPO="$expected_repo" \
    "$BASH" "$SENSOR" "$@" > "$WORK/out" 2> "$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  CALLS="$(wc -l < "$WORK/fixtures/calls" | tr -d ' ')"
  if [[ -f "$WORK/fixtures/unexpected" ]]; then
    t_fail "mock rejects unexpected commands"
    cat "$WORK/fixtures/unexpected"
  fi
}
assert() {
  local name="$1"; shift
  if "$@"; then t_ok "$name"; else
    t_fail "$name (rc=$RC calls=$CALLS)"
    cat "$WORK/out" "$WORK/err" | sed 's/^/    # /'
  fi
}
failure() {
  local name="$1" identity="$2"
  run -R fixture/repo --all
  assert "$name exits nonzero" test "$RC" -ne 0
  assert "$name emits no partial output" test ! -s "$WORK/out"
  assert "$name identifies failure" grep -Eq "$identity" "$WORK/err"
}

setup
touch "$WORK/fixtures/list.fail"
failure "list failure" '[Cc]andidate|[Ll]ist'
setup
: > "$WORK/fixtures/list"
run -R fixture/repo
assert "genuinely empty list succeeds" test "$RC" -eq 0
assert "empty-list message retained" test "$OUT" = 'No open Task issues labeled ai:ready.'
setup
printf 'invalid candidate\n' > "$WORK/fixtures/list"
failure "malformed candidate" '[Cc]andidate|[Ll]ist'

for bad in '{}' 'not-json' '{"blockedBy":[]}' \
  '{"blockedBy":{"nodes":[],"totalCount":1}}' \
  '{"blockedBy":{"nodes":[],"totalCount":"0"}}' \
  '{"blockedBy":{"nodes":[{"number":7}],"totalCount":1}}' \
  '{"blockedBy":{"nodes":[null],"totalCount":1}}' \
  '{"blockedBy":{"nodes":[{"number":7,"repository":{"nameWithOwner":"bad"}}],"totalCount":1}}' \
  '{"blockedBy":{"nodes":[{"number":0,"repository":{"nameWithOwner":"a/repo"}}],"totalCount":1}}' \
  '{"blockedBy":{"nodes":[],"totalCount":0}} {}'; do
  setup
  printf '%s\n' "$bad" > "$WORK/fixtures/fixture_repo-1.json"
  failure "invalid/incomplete dependency $bad" '#1'
done
setup
touch "$WORK/fixtures/fixture_repo-1.json.fail" "$WORK/fixtures/fixture_repo-1.text.fail"
failure "both dependency reads fail" '#1'
printf '# baseline-compatible failure probe: rc=%s calls=%s\n' "$RC" "$CALLS"
for text in 'garbage' 'Blocked by: #7, ???' 'title: test'; do
  setup
  touch "$WORK/fixtures/fixture_repo-1.json.fail"
  printf '%s\n' "$text" > "$WORK/fixtures/fixture_repo-1.text"
  failure "invalid fallback $text" '#1'
done
for state in UNKNOWN '' failure; do
  setup
  dependencies 1 fixture/repo#7
  printf '%s\n' "$state" > "$WORK/fixtures/fixture_repo-7.state"
  [[ "$state" != failure ]] || touch "$WORK/fixtures/fixture_repo-7.state.fail"
  failure "unknown/failed blocker state $state" '#1.*#7'
done
setup
printf '2\tTask 2\n' >> "$WORK/fixtures/list"
dependencies 2 fixture/repo#7 fixture/repo#8
printf 'OPEN\n' > "$WORK/fixtures/fixture_repo-7.state"
printf 'UNKNOWN\n' > "$WORK/fixtures/fixture_repo-8.state"
failure "late unknown after ready Task and OPEN blocker" '#2.*#8'

setup
run -R fixture/repo
assert "no dependencies succeeds" test "$RC" -eq 0
assert "ready row retained" grep -qx $'#1\tTask 1' "$WORK/out"
setup
dependencies 1 fixture/repo#7
printf 'CLOSED\n' > "$WORK/fixtures/fixture_repo-7.state"
run --repo fixture/repo
assert "--repo all CLOSED succeeds" test "$RC" -eq 0
assert "CLOSED blocker yields ready row" grep -qx $'#1\tTask 1' "$WORK/out"
printf 'OPEN\n' > "$WORK/fixtures/fixture_repo-7.state"
run -R fixture/repo
assert "next invocation observes OPEN" test "$RC" -eq 0
assert "OPEN not ready by default" test "$(grep -c '^#1' "$WORK/out")" -eq 0
run -R fixture/repo --all
assert "--all includes OPEN blocker" grep -qx $'#1\tTask 1\t(waiting on: 7)' "$WORK/out"
setup
dependencies 1 fixture/repo#7
printf 'CLOSED\n' > "$WORK/fixtures/fixture_repo-7.state"
run default
assert "default repo context succeeds" test "$RC" -eq 0
assert "default context retains ready row" grep -qx $'#1\tTask 1' "$WORK/out"

for text in 'Blocked by: #7, b/repo#7' 'blocked-by: fixture/repo#7, b/repo#7'; do
  setup
  touch "$WORK/fixtures/fixture_repo-1.json.fail"
  printf '%s\n--\nBlocked by: #999\n' "$text" > "$WORK/fixtures/fixture_repo-1.text"
  printf 'CLOSED\n' > "$WORK/fixtures/fixture_repo-7.state"
  printf 'OPEN\n' > "$WORK/fixtures/b_repo-7.state"
  run -R fixture/repo --all
  assert "validated text fallback succeeds" test "$RC" -eq 0
  assert "fallback preserves cross-repo blocker, ignores body" grep -qx $'#1\tTask 1\t(waiting on: b/repo#7)' "$WORK/out"
done
setup
touch "$WORK/fixtures/fixture_repo-1.json.fail"
printf 'blocked-by:\t\n--\n' > "$WORK/fixtures/fixture_repo-1.text"
run -R fixture/repo
assert "explicit empty legacy dependency row succeeds" test "$RC" -eq 0
assert "empty legacy row yields ready Task" grep -qx $'#1\tTask 1' "$WORK/out"
setup
dependencies 1 a/repo#7 b/repo#7
printf '2\tTask 2\n' >> "$WORK/fixtures/list"
dependencies 2 a/repo#7
printf 'CLOSED\n' > "$WORK/fixtures/a_repo-7.state"
printf 'OPEN\n' > "$WORK/fixtures/b_repo-7.state"
run -R fixture/repo --all
assert "cross-repo JSON identity preserved" grep -qx $'#1\tTask 1\t(waiting on: b/repo#7)' "$WORK/out"
assert "a/repo#7 state read once" test "$(grep -c 'view 7 --repo a/repo --json state' "$WORK/fixtures/calls")" -eq 1
assert "b/repo#7 state read once" test "$(grep -c 'view 7 --repo b/repo --json state' "$WORK/fixtures/calls")" -eq 1
setup
dependencies 1 a/repo#7 a/repo#7
failure "duplicate nodes cannot establish completeness" '#1'
setup
touch "$WORK/fixtures/fixture_repo-1.json.fail"
{
  printf 'Blocked by:'
  for ((i=1; i<=50; i++)); do printf ' #%s' "$i"; done
  printf '\n'
} > "$WORK/fixtures/fixture_repo-1.text"
failure "legacy truncation boundary is unresolved" '#1'
setup
printf '2\tTask 2\n' >> "$WORK/fixtures/list"
printf '{}\n' > "$WORK/fixtures/fixture_repo-2.json"
failure "late dependency failure suppresses earlier ready Task" '#2'

setup
: > "$WORK/fixtures/list"
for ((i=1; i<=50; i++)); do
  printf '%s\tTask %s\n' "$i" "$i" >> "$WORK/fixtures/list"
  dependencies "$i" fixture/repo#1001 fixture/repo#1002
done
printf 'CLOSED\n' > "$WORK/fixtures/fixture_repo-1001.state"
printf 'CLOSED\n' > "$WORK/fixtures/fixture_repo-1002.state"
run -R fixture/repo
sed 's/^/#/' "$WORK/fixtures/list" > "$WORK/expected"
grep '^#' "$WORK/out" > "$WORK/actual"
assert "shared-blocker fixture succeeds" test "$RC" -eq 0
assert "exactly the same 50 rows" cmp -s "$WORK/expected" "$WORK/actual"
assert "at most 53 TOTAL gh invocations" test "$CALLS" -le 53
for blocker in 1001 1002; do
  count="$(grep -c "view $blocker --repo fixture/repo --json state" "$WORK/fixtures/calls")"
  assert "blocker $blocker read exactly once" test "$count" -eq 1
  printf '# shared fixture blocker %s: state reads=%s\n' "$blocker" "$count"
done
printf '# shared fixture: rc=%s rows=%s total gh calls=%s\n' "$RC" "$(wc -l < "$WORK/actual" | tr -d ' ')" "$CALLS"
t_summary
