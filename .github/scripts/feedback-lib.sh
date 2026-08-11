#!/usr/bin/env bash
# feedback-lib.sh — consent-gated adopter feedback helper (ADR-0002).
#
# Sourced (never executed) by the interactive scaffold scripts — the
# installer and the setup-* set. When the sourcing script fails on an
# unguarded command in an interactive run, the exit path *offers* to file
# an upstream issue via the adopter's own `gh issue create`. Everything
# about the offer fails closed:
#
#   - fires only for unguarded failures (recorded by an ERR trap), never
#     for a script's own deliberate `exit` remediations, and never in CI
#     (`CI` / `GITHUB_ACTIONS` set) or non-interactive runs (stdin and
#     stderr must both be TTYs); gh must be installed;
#   - the filing target and scaffold version come exclusively from the
#     scaffold-version marker in SCAFFOLD-CHANGELOG.md (read contract at
#     the write site in scaffold-init.sh). No parseable marker with a
#     valid repo field means no offer — the target is never guessed;
#   - the payload is the fixed allowlist of
#     docs/context/feedback-loop/privacy-posture.md (a development
#     record in the scaffold repository, not installed): script name
#     (fixed enum below, never $0), failing line number (never
#     $BASH_COMMAND), exit code, uname -s/-m, bash/gh/jq versions, and the
#     marker sha. Every value is charset- and length-validated and must be
#     a single line; a value that fails validation is reported as
#     "unknown", never raw;
#   - nothing is sent without an explicit `y` on a previewed, exact body;
#     the default answer is no. Declining or any gate closing leaves the
#     failure path byte-identical to an unwired script, exit code intact.
#
# Entry point: feedback_arm <script-name>. The name must be one of the
# fixed enum (scaffold-init, setup-labels, setup-project, setup-ruleset,
# setup-sources); any other value leaves the script unarmed. Arming sets
# `set -o errtrace` (bash 3.2 does not fire ERR inside functions without
# it) and chains any pre-existing single-quoted EXIT trap — the
# installer's workdir cleanup — running it before the consent prompt so an
# interrupted prompt cannot leak temp state.
#
# No environment knobs: behavior cannot be altered from the environment
# (the ERR-seen state is re-initialized at arm time, and the marker is
# read only from SCAFFOLD-CHANGELOG.md in the current directory or at the
# git toplevel). The guard-test harness simulates a terminal by
# overriding the _fb_isatty function in its own fixture scripts after
# sourcing this file — a code-level seam unavailable to callers.

FEEDBACK_SCRIPT=""

feedback_arm() {
  case "${1:-}" in
    scaffold-init|setup-labels|setup-project|setup-ruleset|setup-sources)
      FEEDBACK_SCRIPT="$1"
      ;;
    *)
      return 0
      ;;
  esac
  set -o errtrace
  # Explicit re-initialization: an inherited environment variable must
  # never be able to pre-arm the offer (deliberate exits stay silent).
  FEEDBACK_ERR_SEEN=""
  FEEDBACK_ERR_LINE=""
  # Record only — the exit path decides. $LINENO expands when the trap
  # fires: the failing line, a scaffold-owned code location.
  trap 'FEEDBACK_ERR_SEEN=1 FEEDBACK_ERR_LINE=$LINENO' ERR
  FEEDBACK_PREV_EXIT=""
  _fb_prev="$(trap -p EXIT 2>/dev/null || true)"
  case "$_fb_prev" in
    "trap -- '"*"' EXIT")
      _fb_prev="${_fb_prev#trap -- \'}"
      FEEDBACK_PREV_EXIT="${_fb_prev%\' EXIT}"
      ;;
  esac
  unset _fb_prev
  trap '_fb_on_exit "$?"' EXIT
  return 0
}

_fb_on_exit() {
  _fb_rc="$1"
  # Snapshot before anything else: the chained cleanup below must not be
  # able to flip the unguarded-failure flag (its own guarded failures
  # would otherwise re-arm it) or be mistaken for the script's failure.
  _fb_seen="${FEEDBACK_ERR_SEEN:-}"
  _fb_recline="${FEEDBACK_ERR_LINE:-}"
  trap - ERR
  set +e
  if [ -n "${FEEDBACK_PREV_EXIT:-}" ]; then
    # Chained cleanup (the installer's workdir removal) runs first, so an
    # interrupted consent prompt can never leak temp state. Subshelled so
    # it cannot disturb this function's variables.
    ( eval "$FEEDBACK_PREV_EXIT" ) || true
  fi
  if [ "$_fb_rc" != "0" ] && [ -n "$_fb_seen" ]; then
    _fb_offer "$_fb_rc" "$_fb_recline" || true
  fi
  return 0
}

# _fb_field <value> <anchored-ere> <max-len> — print the value when it is
# a single line matching both bounds, "unknown" otherwise. The newline
# guard is load-bearing: grep matches per line, so without it a crafted
# multi-line value whose first line matches would pass through verbatim.
_fb_field() {
  case "$1" in
    *$'\n'*|*$'\r'*)
      printf 'unknown'
      return 0
      ;;
  esac
  if [ "${#1}" -le "$3" ] && printf '%s' "$1" | LC_ALL=C grep -Eq "$2"; then
    printf '%s' "$1"
  else
    printf 'unknown'
  fi
}

# _fb_isatty — interactivity gate: stdin and stderr must both be TTYs.
# The guard-test harness overrides this function in its fixtures; there
# is deliberately no environment variable that can bypass it.
_fb_isatty() {
  [ -t 0 ] && [ -t 2 ]
}

_fb_offer() {
  _fb_exit="$1"
  _fb_fline="$2"

  # Gates — each one fails closed to byte-identical silence.
  [ -z "${CI:-}" ] || return 0
  [ -z "${GITHUB_ACTIONS:-}" ] || return 0
  _fb_isatty || return 0
  command -v gh >/dev/null 2>&1 || return 0

  _fb_file="SCAFFOLD-CHANGELOG.md"
  if [ ! -r "$_fb_file" ]; then
    _fb_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -z "$_fb_top" ] || [ ! -r "$_fb_top/SCAFFOLD-CHANGELOG.md" ]; then
      return 0
    fi
    _fb_file="$_fb_top/SCAFFOLD-CHANGELOG.md"
  fi
  _fb_mline="$(LC_ALL=C grep -m1 '^<!-- scaffold-version: ' "$_fb_file" 2>/dev/null || true)"
  [ -n "$_fb_mline" ] || return 0
  _fb_sed='s/^<!-- scaffold-version: repo=\([^ ]*\) sha=\([^ ]*\) date=\([^ ]*\) -->$/'
  _fb_repo="$(printf '%s\n' "$_fb_mline" | sed -n "${_fb_sed}\\1/p")"
  _fb_sha="$(printf '%s\n' "$_fb_mline" | sed -n "${_fb_sed}\\2/p")"
  # The filing target is never guessed: an invalid repo field (including
  # the literal "unknown") means no offer at all.
  printf '%s' "$_fb_repo" \
    | LC_ALL=C grep -Eq '^[A-Za-z0-9._-]{1,64}/[A-Za-z0-9._-]{1,64}$' || return 0
  _fb_sha="$(_fb_field "$_fb_sha" '^[0-9a-f]{40}$' 40)"

  _fb_script="$(_fb_field "${FEEDBACK_SCRIPT:-}" '^[a-z-]{1,32}$' 32)"
  _fb_exit="$(_fb_field "$_fb_exit" '^[0-9]{1,3}$' 3)"
  _fb_fline="$(_fb_field "$_fb_fline" '^[0-9]{1,6}$' 6)"
  _fb_os="$(_fb_field "$(uname -s 2>/dev/null || true)" '^[A-Za-z0-9._-]{1,32}$' 32)"
  _fb_arch="$(_fb_field "$(uname -m 2>/dev/null || true)" '^[A-Za-z0-9._-]{1,32}$' 32)"
  _fb_vre='^[0-9A-Za-z. ()_-]{1,40}$'
  _fb_bash="$(_fb_field "${BASH_VERSION:-}" "$_fb_vre" 40)"
  _fb_gh="$(_fb_field "$(gh --version 2>/dev/null | head -n1 | awk '{print $3}' || true)" "$_fb_vre" 40)"
  _fb_jq="unknown"
  if command -v jq >/dev/null 2>&1; then
    _fb_jq="$(_fb_field "$(jq --version 2>/dev/null | head -n1 || true)" "$_fb_vre" 40)"
  fi

  _fb_title="[adopter-feedback] $_fb_script failed (exit $_fb_exit)"
  _fb_body="<!-- adopter-feedback:v1 -->

Consent-gated failure report from a scaffold script (ADR-0002). Every
value comes from the fixed allowlist in privacy-posture.md — no logs,
paths, repository identity, or environment data are collected.

| Field | Value |
|---|---|
| Script | $_fb_script |
| Failing line | $_fb_fline |
| Exit code | $_fb_exit |
| OS / arch | $_fb_os / $_fb_arch |
| bash version | $_fb_bash |
| gh version | $_fb_gh |
| jq version | $_fb_jq |
| Scaffold version (marker sha) | $_fb_sha |"

  {
    echo
    echo '=================================================================='
    printf ' %s failed (exit %s).\n' "$_fb_script" "$_fb_exit"
    echo ' You can report this failure to the scaffold maintainers.'
    printf ' Filing creates a PUBLIC issue on github.com/%s\n' "$_fb_repo"
    echo ' under YOUR GitHub account (your gh login). Exactly the text'
    echo ' below - nothing more - would be sent:'
    echo '------------------------------------------------------------------'
    printf ' Title: %s\n\n' "$_fb_title"
    printf '%s\n' "$_fb_body"
    echo '------------------------------------------------------------------'
    printf ' File this report upstream? [y/N] '
  } >&2
  IFS= read -r _fb_ans || _fb_ans=""
  case "$_fb_ans" in
    y|Y) ;;
    *)
      echo ' Not sent.' >&2
      return 0
      ;;
  esac
  if _fb_url="$(gh issue create --repo "$_fb_repo" --title "$_fb_title" --body "$_fb_body" 2>/dev/null)"; then
    printf ' Report filed: %s\n' "$_fb_url" >&2
  else
    echo ' gh could not create the issue - nothing was filed.' >&2
  fi
  return 0
}
