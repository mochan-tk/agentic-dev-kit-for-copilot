#!/usr/bin/env bash
# test-connectors.sh — regression tests for
# .github/scripts/check-connectors.sh.
#
# Each case builds a throwaway directory tree with the guard copied in,
# writes connector fixtures, and asserts exit code plus the distinct
# error message. Offline only; the guard reads the filesystem, so no
# git staging or gh shim is needed.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SANDBOX_N=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# new_case — fresh sandbox with the guard installed and the two
# framework files present (individual cases delete them to test
# integrity failures).
new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  mkdir -p "$CASE/.github/scripts" "$CASE/.github/connectors"
  cp "$REPO_ROOT/.github/scripts/check-connectors.sh" "$CASE/.github/scripts/"
  echo "# Connectors" > "$CASE/.github/connectors/README.md"
  echo "# Template" > "$CASE/.github/connectors/CONNECTOR-TEMPLATE.md"
}

# write_valid_connector <name> — a minimal definition that conforms.
write_valid_connector() {
  cat > "$CASE/.github/connectors/$1.md" <<EOF
# Connector: $1

## Metadata

- name: $1
- access: in-repo files
- reach: repository only
- trust-default: draft
- status: core

## discover

How to find material.

## retrieve

How to fetch it.

## pin

How to pin it.

## verify

How to re-verify it.
EOF
}

# --- conforming sandbox passes -------------------------------------------------
new_case
write_valid_connector alpha
write_valid_connector beta
expect_rc_grep 0 'OK — 2 connector definition\(s\) conform: alpha, beta' \
  "two conforming connectors pass" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- missing metadata field fails ----------------------------------------------
new_case
write_valid_connector alpha
sed -e '/^- reach:/d' "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "missing metadata field '- reach:'" \
  "missing metadata field fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- invalid status value fails -------------------------------------------------
new_case
write_valid_connector alpha
sed -e 's/^- status: core$/- status: bespoke/' \
  "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "invalid status value 'bespoke'" \
  "invalid status value fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- missing operation section fails --------------------------------------------
new_case
write_valid_connector alpha
sed -e 's/^## pin$/## pinning/' \
  "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "missing operation section '## pin'" \
  "missing operation section fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- missing '## Metadata' heading fails -----------------------------------------
new_case
write_valid_connector alpha
sed -e 's/^## Metadata$/## About/' \
  "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "missing '## Metadata' section" \
  "missing Metadata heading fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- missing framework file fails ------------------------------------------------
new_case
write_valid_connector alpha
rm "$CASE/.github/connectors/CONNECTOR-TEMPLATE.md"
expect_rc_grep 1 'missing framework file: .*CONNECTOR-TEMPLATE\.md' \
  "missing framework file fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- empty connector set fails ---------------------------------------------------
new_case
expect_rc_grep 1 'no connector definitions found' \
  "framework files without definitions fail" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- one bad file among good ones still fails ------------------------------------
new_case
write_valid_connector alpha
write_valid_connector beta
sed -e '/^- trust-default:/d' "$CASE/.github/connectors/beta.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/beta.md"
expect_rc_grep 1 "beta\.md: missing metadata field '- trust-default:'" \
  "one non-conforming file among conforming ones fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- duplicated metadata field fails ----------------------------------------------
new_case
write_valid_connector alpha
printf -- '- status: experimental\n' >> "$CASE/tmp-dup"
sed -e '/^- status: core$/r '"$CASE/tmp-dup" \
  "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "metadata field '- status:' appears 2 times" \
  "duplicated metadata field fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- undeclared extra bullet in Metadata fails --------------------------------------
new_case
write_valid_connector alpha
printf -- '- flavor: vanilla\n' > "$CASE/tmp-extra"
sed -e '/^- status: core$/r '"$CASE/tmp-extra" \
  "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "undeclared bullet in '## Metadata': '- flavor: vanilla'" \
  "undeclared extra bullet fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- required field outside the Metadata section fails -------------------------------
new_case
write_valid_connector alpha
# Move '- access:' out of Metadata (delete there, append at file end,
# after '## verify'): a bullet outside the section must read as missing.
sed -e '/^- access:/d' \
  "$CASE/.github/connectors/alpha.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/alpha.md"
printf -- '\n- access: in-repo files\n' >> "$CASE/.github/connectors/alpha.md"
expect_rc_grep 1 "missing metadata field '- access:' in '## Metadata'" \
  "required field outside Metadata section fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- name not matching the filename fails --------------------------------------------
new_case
write_valid_connector foo
sed -e 's/^- name: foo$/- name: bar/' \
  "$CASE/.github/connectors/foo.md" > "$CASE/tmp.md"
mv "$CASE/tmp.md" "$CASE/.github/connectors/foo.md"
expect_rc_grep 1 "name 'bar' does not match filename stem 'foo'" \
  "name/filename mismatch fails" \
  bash "$CASE/.github/scripts/check-connectors.sh"

# --- the real tree conforms -------------------------------------------------------
expect_rc 0 "repository connectors directory passes the guard" \
  bash "$REPO_ROOT/.github/scripts/check-connectors.sh"

t_summary
