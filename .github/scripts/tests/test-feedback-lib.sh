#!/usr/bin/env bash
# test-feedback-lib.sh — regression tests for .github/scripts/feedback-lib.sh
# (consent-gated adopter feedback, ADR-0002).
#
# Hermetic: gh is a PATH stub that records its argv and never touches the
# network; each case runs in its own sandbox directory whose
# SCAFFOLD-CHANGELOG.md (or absence) is the fixture, so the real
# repository's marker can never leak in; CI variables are cleared per case
# (the harness itself runs inside GitHub Actions). The production lib has
# no environment knobs — interactivity is simulated by overriding the
# _fb_isatty function inside the test-owned fixture scripts (the FB_TTY
# variable below is read by fixture code only, never by the lib).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fbtest.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

LIB="$REPO_ROOT/.github/scripts/feedback-lib.sh"
INIT="$REPO_ROOT/.github/scripts/scaffold-init.sh"

# --- stub gh: records `issue create` argv, serves --version ----------------
STUB="$WORK/stub-bin"
mkdir -p "$STUB"
GH_LOG="$WORK/gh-args.log"
cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
  echo "gh version 9.9.9 (stub)"
  exit 0
fi
{ printf '%s\n' "\$@"; printf -- '---\n'; } >> "$GH_LOG"
echo "https://github.com/stub-owner/stub-upstream/issues/1"
EOF
chmod +x "$STUB/gh"

gh_calls() {
  if [ -e "$GH_LOG" ]; then grep -c -- '^---$' "$GH_LOG"; else echo 0; fi
}

assert_gh_calls() { # <want> <name>
  local n
  n=$(gh_calls) || true
  if [ "$n" = "$1" ]; then t_ok "$2"; else t_fail "$2 (gh create calls=$n, want $1)"; fi
}

# expect_silent <want-rc> <name> <cmd...> — the command must exit with the
# expected code and its combined output must carry no trace of the offer.
expect_silent() {
  local want="$1" name="$2" rc=0 out
  shift 2
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" -eq "$want" ] && ! printf '%s\n' "$out" | grep -Eq 'adopter-feedback|File this report'; then
    t_ok "$name"
  else
    t_fail "$name (rc=$rc, want $want)"
    printf '%s\n' "$out" | sed 's/^/    # /'
  fi
}

# --- sandbox dirs: the cwd changelog is the marker fixture ------------------
GOODSHA="0123456789abcdef0123456789abcdef01234567"
D_GOOD="$WORK/d-good"
mkdir -p "$D_GOOD"
cat > "$D_GOOD/SCAFFOLD-CHANGELOG.md" <<EOF
# Fixture changelog

<!-- scaffold-version: repo=stub-owner/stub-upstream sha=$GOODSHA date=2026-08-08 -->
**Scaffold version adopted by this instance:** fixture
EOF
D_UNKNOWN="$WORK/d-unknown"
mkdir -p "$D_UNKNOWN"
cat > "$D_UNKNOWN/SCAFFOLD-CHANGELOG.md" <<'EOF'
<!-- scaffold-version: repo=stub-owner/stub-upstream sha=unknown date=unknown -->
EOF
D_BADREPO="$WORK/d-badrepo"
mkdir -p "$D_BADREPO"
cat > "$D_BADREPO/SCAFFOLD-CHANGELOG.md" <<'EOF'
<!-- scaffold-version: repo=unknown sha=unknown date=unknown -->
EOF
D_MALFORMED="$WORK/d-malformed"
mkdir -p "$D_MALFORMED"
cat > "$D_MALFORMED/SCAFFOLD-CHANGELOG.md" <<'EOF'
<!-- scaffold-version: repo=stub-owner/stub-upstream -->
EOF
D_NONE="$WORK/d-none"
mkdir -p "$D_NONE"

# --- fixture scripts ---------------------------------------------------------
# FB_TTY=1 makes the *fixture* override _fb_isatty after sourcing — the
# test-owned stand-in for a real terminal. The lib itself has no knob.
FAIL_SH="$WORK/fail.sh"
cat > "$FAIL_SH" <<'EOF'
set -euo pipefail
# shellcheck source=/dev/null
. "$FB_LIB"
if [ "${FB_TTY:-}" = "1" ]; then _fb_isatty() { return 0; }; fi
feedback_arm "${FB_NAME:-setup-labels}"
false
EOF
PLAIN_SH="$WORK/plain.sh"
cat > "$PLAIN_SH" <<'EOF'
set -euo pipefail
echo before
false
EOF
ARMED_SH="$WORK/armed.sh"
cat > "$ARMED_SH" <<'EOF'
set -euo pipefail
# shellcheck source=/dev/null
. "$FB_LIB"
feedback_arm setup-labels
echo before
false
EOF
EXIT3_SH="$WORK/exit3.sh"
cat > "$EXIT3_SH" <<'EOF'
set -euo pipefail
# shellcheck source=/dev/null
. "$FB_LIB"
if [ "${FB_TTY:-}" = "1" ]; then _fb_isatty() { return 0; }; fi
feedback_arm setup-labels
exit 3
EOF
GUARD_SH="$WORK/guard.sh"
cat > "$GUARD_SH" <<'EOF'
set -euo pipefail
# shellcheck source=/dev/null
. "$FB_LIB"
if [ "${FB_TTY:-}" = "1" ]; then _fb_isatty() { return 0; }; fi
feedback_arm setup-labels
x=$(false) || x=""
exit 3
EOF
CHAIN_SH="$WORK/chain.sh"
cat > "$CHAIN_SH" <<'EOF'
set -euo pipefail
trap 'rm -rf "$FB_D"; echo CLEANUP >&2' EXIT
# shellcheck source=/dev/null
. "$FB_LIB"
feedback_arm setup-ruleset
false
EOF

# run_fb <fixture-script> <sandbox-dir> <stdin-answer> [ENV=VAL...] — run a
# fixture with CI vars cleared, the stub gh first on PATH, and cwd in the
# given sandbox (whose SCAFFOLD-CHANGELOG.md is the marker fixture). The
# answer is piped, so real stdin is never a TTY; pass FB_TTY=1 to make the
# fixture override the interactivity gate.
run_fb() {
  local script="$1" dir="$2" ans="$3"
  shift 3
  printf '%s\n' "$ans" | (
    cd "$dir" && env -u CI -u GITHUB_ACTIONS \
      PATH="$STUB:$PATH" FB_LIB="$LIB" "$@" bash "$script"
  )
}

# --- gating: never fire without a terminal or under CI ----------------------
rm -f "$GH_LOG"
expect_silent 1 "non-interactive failure stays silent, rc preserved" \
  run_fb "$FAIL_SH" "$D_GOOD" ""
expect_silent 1 "CI=1 silences the offer even when interactive" \
  run_fb "$FAIL_SH" "$D_GOOD" y FB_TTY=1 CI=1
expect_silent 1 "GITHUB_ACTIONS=1 silences the offer even when interactive" \
  run_fb "$FAIL_SH" "$D_GOOD" y FB_TTY=1 GITHUB_ACTIONS=1
assert_gh_calls 0 "no gh invocation from any gated run"

rc_plain=0
rc_armed=0
out_plain=$(run_fb "$PLAIN_SH" "$D_NONE" "" 2>&1) || rc_plain=$?
out_armed=$(run_fb "$ARMED_SH" "$D_NONE" "" 2>&1) || rc_armed=$?
if [ "$rc_plain" = "$rc_armed" ] && [ "$out_plain" = "$out_armed" ]; then
  t_ok "gated armed run is byte-identical to an unwired script"
else
  t_fail "gated armed run is byte-identical to an unwired script (rc $rc_plain vs $rc_armed)"
  printf '%s\n---\n%s\n' "$out_plain" "$out_armed" | sed 's/^/    # /'
fi

# gh absent: a PATH with only bash reaches the gh gate (builtins only
# before it) and must close silently even with consent standing by.
SAFE="$WORK/safe-bin"
mkdir -p "$SAFE"
ln -s "$(command -v bash)" "$SAFE/bash"
run_fb_nogh() {
  printf 'y\n' | (
    cd "$D_GOOD" && env -u CI -u GITHUB_ACTIONS \
      PATH="$SAFE" FB_LIB="$LIB" FB_TTY=1 bash "$FAIL_SH"
  )
}
expect_silent 1 "missing gh closes the gate silently" run_fb_nogh

# --- environment immunity: no knob can widen the blast radius ---------------
rm -f "$GH_LOG"
expect_silent 3 "env-injected FEEDBACK_ERR_SEEN cannot pre-arm the offer" \
  run_fb "$EXIT3_SH" "$D_GOOD" y FB_TTY=1 FEEDBACK_ERR_SEEN=1 FEEDBACK_ERR_LINE=42
expect_silent 1 "FEEDBACK_ASSUME_TTY has no effect (no TTY bypass knob)" \
  run_fb "$FAIL_SH" "$D_GOOD" y FEEDBACK_ASSUME_TTY=1
expect_silent 1 "FEEDBACK_CHANGELOG has no effect (no marker redirect knob)" \
  run_fb "$FAIL_SH" "$D_NONE" y FB_TTY=1 FEEDBACK_CHANGELOG="$D_GOOD/SCAFFOLD-CHANGELOG.md"
assert_gh_calls 0 "no gh invocation from environment-injection attempts"

# --- marker gate: no parseable target, no offer ------------------------------
rm -f "$GH_LOG"
expect_silent 1 "missing changelog means no offer" \
  run_fb "$FAIL_SH" "$D_NONE" y FB_TTY=1
expect_silent 1 "repo=unknown marker means no offer (target never guessed)" \
  run_fb "$FAIL_SH" "$D_BADREPO" y FB_TTY=1
expect_silent 1 "malformed marker line means no offer" \
  run_fb "$FAIL_SH" "$D_MALFORMED" y FB_TTY=1
assert_gh_calls 0 "no gh invocation without a valid marker"

# --- consent: default no, preview always shown -------------------------------
rm -f "$GH_LOG"
expect_rc_grep 1 'File this report upstream' "offer shows the preview and prompt" \
  run_fb "$FAIL_SH" "$D_GOOD" "" FB_TTY=1
expect_rc_grep 1 'Not sent' "empty answer defaults to no" \
  run_fb "$FAIL_SH" "$D_GOOD" "" FB_TTY=1
expect_rc_grep 1 'Not sent' "explicit n declines" \
  run_fb "$FAIL_SH" "$D_GOOD" n FB_TTY=1
assert_gh_calls 0 "declined consent never invokes gh"

# --- consent yes: exactly one create with the allowlist payload --------------
rm -f "$GH_LOG"
expect_rc_grep 1 'Report filed: https://github.com/stub-owner' \
  "consent y files the report and echoes the URL, rc preserved" \
  run_fb "$FAIL_SH" "$D_GOOD" y FB_TTY=1
assert_gh_calls 1 "consent y invokes gh issue create exactly once"
if grep -qFx -- '--repo' "$GH_LOG" && grep -qFx 'stub-owner/stub-upstream' "$GH_LOG"; then
  t_ok "filing target comes from the marker repo field"
else
  t_fail "filing target comes from the marker repo field"
fi
if grep -qFx '[adopter-feedback] setup-labels failed (exit 1)' "$GH_LOG"; then
  t_ok "title carries the fixed prefix, script enum, and exit code"
else
  t_fail "title carries the fixed prefix, script enum, and exit code"
fi
if grep -qFx '<!-- adopter-feedback:v1 -->' "$GH_LOG"; then
  t_ok "body starts with the fixed adopter-feedback:v1 marker"
else
  t_fail "body starts with the fixed adopter-feedback:v1 marker"
fi
if grep -qF "| Scaffold version (marker sha) | $GOODSHA |" "$GH_LOG"; then
  t_ok "body reports the marker sha verbatim"
else
  t_fail "body reports the marker sha verbatim"
fi
if ! grep -qiF 'marker date' "$GH_LOG"; then
  t_ok "body carries no field outside the ADR allowlist (no date row)"
else
  t_fail "body carries no field outside the ADR allowlist (no date row)"
fi

rm -f "$GH_LOG"
expect_rc_grep 1 'Report filed' "sha=unknown marker still files (version unknown)" \
  run_fb "$FAIL_SH" "$D_UNKNOWN" y FB_TTY=1
if grep -qF '| Scaffold version (marker sha) | unknown |' "$GH_LOG"; then
  t_ok "unvalidated sha is reported as unknown, never raw"
else
  t_fail "unvalidated sha is reported as unknown, never raw"
fi

# --- never fire for deliberate exits or guarded failures ---------------------
rm -f "$GH_LOG"
expect_silent 3 "deliberate exit stays silent with every gate open" \
  run_fb "$EXIT3_SH" "$D_GOOD" y FB_TTY=1
expect_silent 3 "guarded substitution failure never arms the offer" \
  run_fb "$GUARD_SH" "$D_GOOD" y FB_TTY=1
expect_silent 1 "non-enum script name leaves the script unarmed" \
  run_fb "$FAIL_SH" "$D_GOOD" y FB_TTY=1 FB_NAME=rm-rf-evil
assert_gh_calls 0 "no gh invocation from silent classes"

# --- EXIT chaining preserves a pre-existing cleanup trap ----------------------
CHAIN_D="$WORK/chain-dir"
mkdir -p "$CHAIN_D"
expect_rc_grep 1 'CLEANUP' "pre-existing EXIT trap still runs when armed" \
  run_fb "$CHAIN_SH" "$D_GOOD" "" FB_D="$CHAIN_D"
if [ ! -d "$CHAIN_D" ]; then
  t_ok "chained cleanup actually removed its directory"
else
  t_fail "chained cleanup actually removed its directory"
fi

# --- field hardening ---------------------------------------------------------
VRE='^[0-9A-Za-z. ()_-]{1,40}$'
v=$(bash -c '. "$1"; _fb_field "$2" "$3" "$4"' _ "$LIB" '3.2.57(1)-release' "$VRE" 40)
if [ "$v" = "3.2.57(1)-release" ]; then
  t_ok "valid version string passes _fb_field verbatim"
else
  t_fail "valid version string passes _fb_field verbatim (got: $v)"
fi
v=$(bash -c '. "$1"; _fb_field "$2" "$3" "$4"' _ "$LIB" '/etc/passwd;rm' "$VRE" 40)
if [ "$v" = "unknown" ]; then
  t_ok "bad charset is reported as unknown"
else
  t_fail "bad charset is reported as unknown (got: $v)"
fi
v=$(bash -c '. "$1"; _fb_field "$2" "$3" "$4"' _ "$LIB" 1234567 '^[0-9]{1,6}$' 6)
if [ "$v" = "unknown" ]; then
  t_ok "overlong value is reported as unknown"
else
  t_fail "overlong value is reported as unknown (got: $v)"
fi
v=$(bash -c '. "$1"; _fb_field "$(printf "1.2\n/etc/secret")" "$2" "$3"' _ "$LIB" "$VRE" 40)
if [ "$v" = "unknown" ]; then
  t_ok "multi-line value is rejected, not smuggled past line-wise grep"
else
  t_fail "multi-line value is rejected, not smuggled past line-wise grep (got: $v)"
fi
v=$(bash -c '. "$1"; _fb_field "$(printf "1.2\rX")" "$2" "$3"' _ "$LIB" "$VRE" 40)
if [ "$v" = "unknown" ]; then
  t_ok "carriage-return value is rejected"
else
  t_fail "carriage-return value is rejected (got: $v)"
fi

# --- installer wiring: non-interactive failure produces no offer output ------
FIXTURE="$WORK/template"
mkdir -p "$FIXTURE/.github/scripts"
echo "# fixture agents" > "$FIXTURE/AGENTS.md"
echo "# fixture changelog" > "$FIXTURE/SCAFFOLD-CHANGELOG.md"
echo "# fixture readme" > "$FIXTURE/README.md"
echo "fixture-ignore" > "$FIXTURE/.gitignore"
echo "echo guard" > "$FIXTURE/.github/scripts/some-guard.sh"
TARGET="$WORK/ro-target"
init_sandbox_repo "$TARGET"
chmod u-w "$TARGET"
run_init_ro() {
  (cd "$TARGET" && env -u CI -u GITHUB_ACTIONS SCAFFOLD_SOURCE_DIR="$FIXTURE" \
    bash "$INIT" </dev/null)
}
expect_silent 1 "non-interactive installer failure produces no offer output" \
  run_init_ro
chmod u+w "$TARGET"

t_summary
