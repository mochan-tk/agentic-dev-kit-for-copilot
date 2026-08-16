#!/usr/bin/env bash
# test-governance-drift.sh — local governance-control drift regression tests.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SENSOR="$ROOT/.github/scripts/governance-drift.sh"
MANIFEST="$ROOT/.github/scripts/governance-controls.tsv"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/governance-drift-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

run_sensor() {
  bash "$SENSOR" --root "$1" --manifest "$2" ${3:+"$3"}
}

out="$(bash "$SENSOR" --root "$ROOT" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(printf '%s\n' "$out" | grep -c '^ACTIVE ')" -eq 5 ] \
   && ! printf '%s\n' "$out" | grep -Eq '^(MISSING|WAIVED) '; then
  t_ok "current template reports exactly five ACTIVE controls"
else
  t_fail "current template reports exactly five ACTIVE controls (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi
expect_rc_grep 0 '^ACTIVE ci-windows-launcher ' \
  "strict mode passes on the current template" \
  bash "$SENSOR" --root "$ROOT" --strict

OLD="$WORK/822fdda"
mkdir -p "$OLD/.github/workflows"
grep -v 'pwsh \.github/scripts/run\.ps1 tuning-status\.sh --quiet' \
  "$ROOT/.github/workflows/ci.yml" > "$OLD/.github/workflows/ci.yml"
out="$(run_sensor "$OLD" "$MANIFEST" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(printf '%s\n' "$out" | grep -c '^ACTIVE ')" -eq 4 ] \
   && [ "$(printf '%s\n' "$out" | grep -c '^MISSING ci-windows-launcher ')" -eq 1 ] \
   && printf '%s\n' "$out" | grep -q '^MISSING ci-windows-launcher .*remediation=#51 waiver=.github/docs/agreements/governance-control-waivers.tsv$'; then
  t_ok "822fdda shape reports only the Windows launcher missing"
else
  t_fail "822fdda shape reports only the Windows launcher missing (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi
expect_rc_grep 1 '^MISSING ci-windows-launcher .*remediation=#51 waiver=' \
  "strict mode fails with actionable output for an unwaived control" \
  run_sensor "$OLD" "$MANIFEST" --strict

FALSE="$WORK/false-positive"
mkdir -p "$FALSE/.github/workflows" "$FALSE/elsewhere"
printf '%s\n' \
  '#         run: bash .github/scripts/check-action-pins.sh' \
  'prefix         run: bash .github/scripts/check-action-pins.sh suffix' \
  > "$FALSE/.github/workflows/ci.yml"
printf '%s\n' '        run: bash .github/scripts/check-action-pins.sh' \
  > "$FALSE/elsewhere/ci.yml"
ONE="$WORK/one.tsv"
grep '^ci-action-pins	' "$MANIFEST" > "$ONE"
expect_rc_grep 0 '^MISSING ci-action-pins ' \
  "comments, substrings, and other files cannot activate a control" \
  run_sensor "$FALSE" "$ONE"
rm "$FALSE/.github/workflows/ci.yml"
expect_rc_grep 0 '^MISSING ci-action-pins ' \
  "a missing declared target is MISSING" run_sensor "$FALSE" "$ONE"

BAD="$WORK/bad.tsv"
printf 'empty\t.github/workflows/ci.yml\t\t#1\tfix\n' > "$BAD"
expect_rc 2 "empty manifest fields are schema errors" run_sensor "$ROOT" "$BAD"
printf 'dup\t.github/workflows/ci.yml\t^x$\t#1\tfix\ndup\t.github/workflows/ci.yml\t^y$\t#2\tfix\n' > "$BAD"
expect_rc 2 "duplicate control IDs are schema errors" run_sensor "$ROOT" "$BAD"
printf 'unsafe\t../outside\t^x$\t#1\tfix\n' > "$BAD"
expect_rc 2 "unsafe target traversal is a schema error" run_sensor "$ROOT" "$BAD"
printf 'loose\t.github/workflows/ci.yml\tx\t#1\tfix\n' > "$BAD"
expect_rc 2 "unanchored signatures are schema errors" run_sensor "$ROOT" "$BAD"
printf 'regex\t.github/workflows/ci.yml\t^[$\t#1\tfix\n' > "$BAD"
expect_rc 2 "malformed regex data is a schema error" run_sensor "$ROOT" "$BAD"

WAIVERS="$WORK/waivers.tsv"
printf 'ci-windows-launcher\tLegacy runner migration is scheduled\n' > "$WAIVERS"
out="$(bash "$SENSOR" --root "$OLD" --manifest "$MANIFEST" --waivers "$WAIVERS" --strict 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s\n' "$out" | grep -q '^WAIVED ci-windows-launcher .* reason=Legacy runner migration is scheduled$'; then
  t_ok "a known reasoned waiver is visible and passes strict mode"
else
  t_fail "a known reasoned waiver is visible and passes strict mode (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi
printf 'ci-windows-launcher\tNo longer needed\n' > "$WAIVERS"
expect_rc_grep 0 '^ACTIVE ci-windows-launcher ' \
  "an active control remains ACTIVE even when a waiver exists" \
  bash "$SENSOR" --root "$ROOT" --waivers "$WAIVERS" --strict
printf 'unknown-control\tReason\n' > "$WAIVERS"
expect_rc 2 "unknown waiver IDs are schema errors" \
  bash "$SENSOR" --root "$OLD" --manifest "$MANIFEST" --waivers "$WAIVERS"
printf 'ci-windows-launcher\t\n' > "$WAIVERS"
expect_rc 2 "empty waiver reasons are schema errors" \
  bash "$SENSOR" --root "$OLD" --manifest "$MANIFEST" --waivers "$WAIVERS"
printf 'ci-windows-launcher\tOne\nci-windows-launcher\tTwo\n' > "$WAIVERS"
expect_rc 2 "duplicate waiver IDs are schema errors" \
  bash "$SENSOR" --root "$OLD" --manifest "$MANIFEST" --waivers "$WAIVERS"

printf 'ci-windows-launcher\tKeep this exception visible\n' > "$WAIVERS"
before="$(git hash-object "$OLD/.github/workflows/ci.yml" "$MANIFEST" "$WAIVERS")"
bash "$SENSOR" --root "$OLD" --manifest "$MANIFEST" --waivers "$WAIVERS" >/dev/null
after="$(git hash-object "$OLD/.github/workflows/ci.yml" "$MANIFEST" "$WAIVERS")"
if [ "$before" = "$after" ]; then
  t_ok "the detector leaves targets, manifest, and waivers byte-identical"
else
  t_fail "the detector leaves targets, manifest, and waivers byte-identical"
fi

t_summary
