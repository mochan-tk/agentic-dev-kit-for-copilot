#!/usr/bin/env bash
# test-action-pins.sh — regression tests for .github/scripts/check-action-pins.sh.
#
# Each case builds a throwaway git repo, copies the guard into it (the
# guard resolves its repo root from its own location), stages workflow
# fixtures, and asserts the exit code.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SANDBOX_N=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# new_case — build a fresh sandbox repo with the guard installed; sets CASE.
new_case() {
  SANDBOX_N=$((SANDBOX_N + 1))
  CASE="$WORK/case$SANDBOX_N"
  init_sandbox_repo "$CASE"
  mkdir -p "$CASE/.github/scripts" "$CASE/.github/workflows"
  cp "$REPO_ROOT/.github/scripts/check-action-pins.sh" "$CASE/.github/scripts/"
}

# --- pinned references (plus a local action) pass -------------------------
new_case
cat > "$CASE/.github/workflows/good.yml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/setup-node@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v4.0.2
      - uses: ./.github/actions/local-thing
EOF
stage_all "$CASE"
expect_rc 0 "pinned refs and local action pass" bash "$CASE/.github/scripts/check-action-pins.sh"

# --- tag reference fails ----------------------------------------------------
new_case
cat > "$CASE/.github/workflows/tag.yml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
EOF
stage_all "$CASE"
expect_rc 1 "tag-pinned reference fails" bash "$CASE/.github/scripts/check-action-pins.sh"

# --- full SHA without the version comment fails -----------------------------
new_case
cat > "$CASE/.github/workflows/nocomment.yml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
EOF
stage_all "$CASE"
expect_rc 1 "SHA without version comment fails" bash "$CASE/.github/scripts/check-action-pins.sh"

# --- short SHA fails ---------------------------------------------------------
new_case
cat > "$CASE/.github/workflows/short.yml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@3d3c42e # v7.0.1
EOF
stage_all "$CASE"
expect_rc 1 "short SHA fails" bash "$CASE/.github/scripts/check-action-pins.sh"

# --- non-list uses: line (composite-action style) is still scanned ----------
new_case
cat > "$CASE/.github/workflows/bare.yml" <<'EOF'
jobs:
  build:
    steps:
      - name: wrapped
        uses: actions/cache@v3
EOF
stage_all "$CASE"
expect_rc 1 "bare uses: line with tag fails" bash "$CASE/.github/scripts/check-action-pins.sh"

# --- one bad file among good ones still fails --------------------------------
new_case
cat > "$CASE/.github/workflows/good.yml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
EOF
cat > "$CASE/.github/workflows/bad.yaml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@main
EOF
stage_all "$CASE"
expect_rc 1 "one unpinned file among pinned ones fails" bash "$CASE/.github/scripts/check-action-pins.sh"

# --- no workflow files at all passes -----------------------------------------
new_case
rmdir "$CASE/.github/workflows"
stage_all "$CASE"
expect_rc 0 "repo without workflow files passes" bash "$CASE/.github/scripts/check-action-pins.sh"

t_summary
