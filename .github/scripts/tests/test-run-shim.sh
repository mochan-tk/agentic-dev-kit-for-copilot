#!/usr/bin/env bash
# test-run-shim.sh — regression tests for .github/scripts/run.ps1.
#
# The shim exists because `bash` on Windows reaches the WSL launcher, not
# Git Bash: the Git for Windows installer leaves `...\Git\bin` off PATH on
# purpose, while `System32\bash.exe` is on it by default (#49).
#
# Two layers, because this repository's CI runs on Linux:
#   * structural assertions, which run everywhere — they protect the two
#     properties that make the shim correct (System32 excluded, install
#     locations preferred) and the rule that keeps it honest (no judgement
#     of its own);
#   * behavioural assertions, which need a PowerShell interpreter and are
#     reported as skipped when there is none. A skip is printed, never
#     silently passed — an untested claim is the thing this scaffold keeps
#     being bitten by.
#
# Even with pwsh present, this only proves the shim's non-Windows paths.
# Resolving a real Git Bash can be checked on Windows and nowhere else.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

SHIM="$REPO_ROOT/.github/scripts/run.ps1"

# --- structural: the shim exists and is wired to the scripts directory ----
if [ -r "$SHIM" ]; then
  t_ok "run.ps1 is present"
else
  t_fail "run.ps1 is missing — the documented Windows invocation cannot work"
  t_summary; exit
fi

# --- structural: the WSL launcher must stay excluded ----------------------
if grep -q 'System32' "$SHIM" && grep -qi 'StartsWith' "$SHIM"; then
  t_ok "the search excludes System32 (the WSL launcher)"
else
  t_fail "the System32 exclusion is gone — bare PATH lookup finds WSL first"
fi

# --- structural: install locations are searched before PATH ---------------
if awk '/ProgramFiles/ { pf = NR } /Get-Command bash.exe/ { gc = NR }
        END { exit !(pf && gc && pf < gc) }' "$SHIM"; then
  t_ok "standard install locations are searched before PATH"
else
  t_fail "PATH is consulted before the install locations, or one is missing"
fi

# --- structural: drive-qualified paths must not go through Join-Path ------
# Join-Path resolves the drive, so 'C:\Windows' fails anywhere without a C:
# drive — which is every machine this test runs on.
if grep -q "Join-Path .*systemRoot" "$SHIM"; then
  t_fail "SystemRoot is joined with Join-Path — unevaluable off Windows"
else
  t_ok "the System32 prefix is built without drive resolution"
fi

# --- structural: the shim must not decide anything ------------------------
if grep -qE 'CUSTOMIZE|FINDINGS|-eq 0.*tuned|not onboarded' "$SHIM"; then
  t_fail "run.ps1 interprets a script's result — judgement belongs in the .sh"
else
  t_ok "the shim carries no judgement of its own"
fi

# --- behavioural: needs an interpreter ------------------------------------
PWSH=""
for candidate in pwsh powershell /tmp/pwsh/pwsh; do
  if command -v "$candidate" >/dev/null 2>&1; then PWSH="$candidate"; break; fi
  if [ -x "$candidate" ]; then PWSH="$candidate"; break; fi
done

if [ -z "$PWSH" ]; then
  echo "# skip - no PowerShell interpreter; run.ps1's behaviour was not executed."
  echo "#        Structural assertions above still ran. Install PowerShell to"
  echo "#        exercise the argument, resolution and missing-bash paths."
  t_summary; exit
fi

run_shim() {
  ( cd "$REPO_ROOT" && "$PWSH" -NoProfile -File "$SHIM" "$@" 2>&1 )
}

# The file must parse: a syntax error would ship a shim that cannot start.
parse_out=$("$PWSH" -NoProfile -Command "
  \$errors = \$null
  [System.Management.Automation.Language.Parser]::ParseFile('$SHIM', [ref]\$null, [ref]\$errors) | Out-Null
  if (\$errors) { \$errors | ForEach-Object { \$_.Message } } else { 'parse OK' }" 2>&1)
case "$parse_out" in
  *"parse OK"*) t_ok "run.ps1 parses" ;;
  *) t_fail "run.ps1 has a parse error: $parse_out" ;;
esac

# No arguments is a usage error, not a silent success.
out=$(run_shim); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'Usage: run.ps1'; then
  t_ok "no arguments fails with usage"
else
  t_fail "no arguments should fail with usage (rc=$rc)"
fi

# A missing script is named, not silently skipped.
out=$(run_shim no-such-script.sh); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'Script not found'; then
  t_ok "a missing script fails by name"
else
  t_fail "a missing script should fail by name (rc=$rc)"
fi

# Off Windows there is no Git Bash, so the resolution failure must be the
# actionable message — the same path a Windows machine without Git takes.
out=$(run_shim tuning-status.sh --quiet); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'Git for Windows is required'; then
  t_ok "an unresolvable bash fails with the Git for Windows message"
else
  t_fail "expected the Git for Windows message (rc=$rc): $(printf '%s' "$out" | head -2)"
fi

t_summary
