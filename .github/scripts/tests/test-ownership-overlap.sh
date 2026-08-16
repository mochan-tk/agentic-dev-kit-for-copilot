#!/usr/bin/env bash
# test-ownership-overlap.sh — parser, overlap, and producer regression tests.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SENSOR="$ROOT/.github/scripts/ownership-overlap.sh"
PRODUCER="$ROOT/.github/skills/plan-management/scripts/new-task.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ownership-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fixtures"
export GH_CALLS="$WORK/gh-calls.log" GH_FIXTURES="$WORK/fixtures"

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$GH_CALLS"
case "${1:-} ${2:-}" in
  "auth status") [ "${GH_AUTH_FAIL:-0}" != 1 ] ;;
  "issue view")
    issue="${3:-}"
    [ "$issue" != "${GH_API_FAIL_ISSUE:-}" ] || exit 1
    cat "$GH_FIXTURES/$issue.body"
    ;;
  "issue create")
    printf 'https://github.com/o/r/issues/99\n'
    ;;
  *) echo "unsupported gh call: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
PATH="$WORK/bin:$PATH"
export PATH

body() {
  name="$1"
  shift
  printf '%s\n' "$@" > "$WORK/$name.md"
}

expect_valid() {
  name="$1"
  expect_rc_grep 0 '^VALID ' "$name" bash "$SENSOR" --validate-body "$WORK/$name.md"
}

expect_invalid() {
  name="$1"
  expect_rc_grep 3 '^UNCHECKABLE ' "$name" bash "$SENSOR" --validate-body "$WORK/$name.md"
}

body plain "## File ownership" "" "- src/auth/token.sh"
expect_valid plain
body code "### File ownership" "- \`.github/scripts/*.sh\`"
expect_valid code
body code_space "## File ownership" "- \`docs/path with spaces.md\`"
expect_valid code_space

body duplicate "## File ownership" "- src/a" "## Notes" "x" \
  "### File ownership" "- src/b"
body empty "## File ownership" ""
body nested "## File ownership" "  - src/a"
body qualified "## File ownership" "- src/a — generated files only"
body multi "## File ownership" "- src/a src/b"
body absolute "## File ownership" "- /tmp/a"
body traversal "## File ownership" "- src/../secret"
body prose "## File ownership" "Only these paths:" "- src/a"
for invalid in duplicate empty nested qualified multi absolute traversal prose; do
  expect_invalid "$invalid"
done

fixture() {
  number="$1"
  shift
  printf '%s\n' "## Objective" "fixture" "## File ownership" "$@" \
    "## Verification" '```bash' "true" '```' > "$GH_FIXTURES/$number.body"
}

fixture 1 "- src/auth/token.sh"
fixture 2 "- src/auth/token.sh"
fixture 3 "- src/auth/**"
fixture 4 "- docs/**"
fixture 5 "- scripts/**"
fixture 6 "- tests/**"
fixture 7 "- *"
fixture 8 "- src/other.sh"
fixture 74 "- SCAFFOLD-CHANGELOG.md"
fixture 76 "- SCAFFOLD-CHANGELOG.md"
printf '%s\n' "## File ownership" "prose" > "$GH_FIXTURES/72.body"

: > "$GH_CALLS"
expect_rc_grep 1 '#1 .*src/auth/token\.sh.*#2 .*src/auth/token\.sh' \
  "exact collision reports both Tasks and declarations" \
  bash "$SENSOR" -R o/r 1 2
expect_rc_grep 1 '#3 .*src/auth/\*\*.*#1 .*src/auth/token\.sh' \
  "broad literal-prefix collision is conservative" \
  bash "$SENSOR" -R o/r 3 1
expect_rc_grep 1 '#7 .*\*.*#8 .*src/other\.sh' \
  "empty literal prefix intersects everything" \
  bash "$SENSOR" -R o/r 7 8
expect_rc_grep 0 '^NO_OVERLAP tasks=3 declarations=3 pairs=3$' \
  "multiple clean Tasks produce a deterministic summary" \
  bash "$SENSOR" -R o/r 4 5 6
expect_rc_grep 1 '#74 .*#76 .*SCAFFOLD-CHANGELOG\.md' \
  "shared changelog ownership is never suppressed" \
  bash "$SENSOR" -R o/r 74 76

expect_rc_grep 2 'API request failed.*#9' \
  "API failure is an environment error" \
  env GH_API_FAIL_ISSUE=9 bash "$SENSOR" -R o/r 1 9
out="$(bash "$SENSOR" -R o/r 1 2 72 2>&1)"
rc=$?
if [ "$rc" -eq 3 ] \
   && printf '%s\n' "$out" | grep -q '#1 .*#2 ' \
   && printf '%s\n' "$out" | grep -q '^UNCHECKABLE #72'; then
  t_ok "UNCHECKABLE takes precedence after parseable overlaps are reported"
else
  t_fail "UNCHECKABLE takes precedence after parseable overlaps are reported (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

if grep -Ev '^(auth status|issue view )' "$GH_CALLS" | grep -q .; then
  t_fail "live sensor performs issue reads only"
  sed 's/^/    # /' "$GH_CALLS"
else
  t_ok "live sensor performs issue reads only"
fi

: > "$GH_CALLS"
expect_rc_grep 3 '^UNCHECKABLE ' \
  "ready producer rejects malformed ownership before creation" \
  bash "$PRODUCER" -t bad -b "$WORK/prose.md" -p 1 -e app -R o/r --ready
if grep -q '^issue create' "$GH_CALLS"; then
  t_fail "ready validation failure makes zero create calls"
else
  t_ok "ready validation failure makes zero create calls"
fi

: > "$GH_CALLS"
expect_rc_grep 0 'Created task #99' \
  "draft producer retains existing behavior for malformed ownership" \
  bash "$PRODUCER" -t draft -b "$WORK/prose.md" -p 1 -e app -R o/r
if grep -q '^issue create' "$GH_CALLS"; then
  t_ok "draft producer still creates without ownership validation"
else
  t_fail "draft producer still creates without ownership validation"
fi

t_summary
