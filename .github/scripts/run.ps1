# run.ps1 - Windows launcher for the scaffold's bash scripts.
#
# Why this exists: on Windows, typing `bash` does not reach Git Bash on a
# correctly configured machine. The Git for Windows installer's recommended
# PATH option adds only `...\Git\cmd` (which holds git.exe); bash.exe lives
# in `...\Git\bin`, left off PATH on purpose to avoid DLL conflicts. What is
# on PATH is `C:\Windows\System32\bash.exe`, the WSL launcher - which needs a
# configured distro and sees a different filesystem than the app's worktrees.
# So `bash .github/scripts/tuning-status.sh` reaches WSL with nothing
# misconfigured. This launcher resolves the real interpreter instead.
#
# Thin shim only. It resolves bash, forwards arguments, and returns the
# script's exit code. It parses no output, interprets no exit code, and
# knows nothing about what any script decides - every judgement stays in the
# one canonical .sh, so there is no second implementation to drift (#49).
#
# Usage (from the repository root):
#   pwsh .github/scripts/run.ps1 tuning-status.sh --quiet
#   pwsh .github/scripts/run.ps1 tests/run-tests.sh
# The script name is relative to .github/scripts/; an absolute path or a
# path to anywhere else in the repository also works.
#
# Prerequisite: Git for Windows (https://gitforwindows.org). The GitHub
# Copilot app already requires Git, and this is the bash that ships with it.
# Exit codes: whatever the invoked script returns. Failure to resolve bash,
# or a missing script, raises a terminating error instead - "could not run"
# must never be mistaken for a result.

$ErrorActionPreference = 'Stop'

function Find-GitBash {
    # Standard Git for Windows locations first, then PATH. System32 is
    # excluded throughout: that bash.exe is the WSL launcher.
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LocalAppData\Programs\Git\bin\bash.exe"
    ) | Where-Object { $_ -match '^[A-Za-z]:\\' }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    # PATH second, with the WSL launcher excluded: that bash.exe is not
    # Git Bash. Built by string concatenation rather than Join-Path, which
    # resolves the drive and therefore only works on Windows - this line has
    # to be evaluable anywhere so the search can be exercised in tests.
    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) { $systemRoot = 'C:\Windows' }
    $sys32 = $systemRoot.TrimEnd('\') + '\System32'
    $onPath = @(Get-Command bash.exe -All -CommandType Application -ErrorAction SilentlyContinue) |
        Where-Object { $_.Source -and -not $_.Source.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($onPath) { return $onPath.Source }
    return $null
}

if ($args.Count -lt 1) {
    throw ('Usage: run.ps1 <script.sh> [arguments]  -  for example, ' +
        'run.ps1 tuning-status.sh --quiet')
}

$scriptArg = "$($args[0])"
$forward = @()
if ($args.Count -gt 1) { $forward = @($args[1..($args.Count - 1)] | ForEach-Object { "$_" }) }

# Resolve relative to .github/scripts/ first, then as given, so both
# `run.ps1 tuning-status.sh` and `run.ps1 .github/scripts/tuning-status.sh`
# work from the repository root.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = $null
foreach ($candidate in @((Join-Path $here $scriptArg), $scriptArg)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $target = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (-not $target) {
    throw "Script not found: $scriptArg (looked in $here and as given)."
}

$bash = Find-GitBash
if (-not $bash) {
    throw ('Git for Windows is required but bash.exe was not found ' +
        '(standard install locations and PATH were searched; the WSL ' +
        'launcher in System32 is skipped deliberately). Install it from ' +
        'https://gitforwindows.org and re-run. The GitHub Copilot app ' +
        'already requires Git; this is the bash that ships with it.')
}

# Forward slashes so MSYS bash accepts the Windows path.
& $bash ($target -replace '\\', '/') @forward
exit $LASTEXITCODE
