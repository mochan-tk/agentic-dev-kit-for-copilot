# scaffold-init.ps1 - Windows bootstrap for the agentic-dev scaffold installer.
#
# Thin shim only: locates Git Bash and re-executes the canonical bash
# installer (scaffold-init.sh) through it. All install logic - SHA-pinned
# fetch, collision refusal, symlink safety - lives in the bash script;
# this file must never duplicate any of it.
#
# One-liner (PowerShell, at the root of a new or existing git repository):
#   irm https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.ps1 | iex
#
# One-liner with arguments (iex cannot forward flags - $args is empty in
# evaluated text; a script block invocation populates it):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.ps1))) --upgrade
#
# Saved-file form forwards the installer's arguments:
#   .\scaffold-init.ps1 [--force|--upgrade] [--dry-run] [--help] [target-dir]
#
# Prerequisite: Git for Windows (https://gitforwindows.org) - its bash.exe
# runs the installer. The WSL launcher (System32\bash.exe) is deliberately
# skipped: it requires a configured distro and sees a different filesystem.
# Environment: SCAFFOLD_REPO / SCAFFOLD_REF / SCAFFOLD_SOURCE_DIR flow
# through to the bash installer unchanged.
# Exit codes: those of scaffold-init.sh (0 ok, 1 collision/symlink/target,
# 2 usage, 3 fetch); bootstrap failures (bash.exe missing, download error)
# raise a terminating error instead.

$ErrorActionPreference = 'Stop'

$installerUrl = 'https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.sh'

function Find-GitBash {
    # Standard Git for Windows locations first, then PATH.
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LocalAppData\Programs\Git\bin\bash.exe"
    ) | Where-Object { $_ -match '^[A-Za-z]:\\' }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    $sys32 = Join-Path $env:SystemRoot 'System32'
    $onPath = @(Get-Command bash.exe -All -CommandType Application -ErrorAction SilentlyContinue) |
        Where-Object { $_.Source -and -not $_.Source.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($onPath) { return $onPath.Source }
    return $null
}

$bash = Find-GitBash
if (-not $bash) {
    throw ('Git for Windows is required but bash.exe was not found ' +
        '(standard install locations and PATH were searched). Install it from ' +
        'https://gitforwindows.org and re-run. All scaffold scripts run inside ' +
        'Git Bash (or WSL).')
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('scaffold-init-' + [System.IO.Path]::GetRandomFileName() + '.sh')
$code = 1
try {
    try {
        # Windows PowerShell 5.1 may default to a TLS version GitHub rejects.
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $installerUrl -OutFile $tmp
    } catch {
        throw "Failed to download the scaffold installer from $installerUrl : $($_.Exception.Message)"
    }

    $forward = @()
    if ($null -ne $args) { $forward = @($args | ForEach-Object { "$_" }) }
    # Forward slashes so MSYS bash accepts the Windows temp path.
    & $bash ($tmp -replace '\\', '/') @forward
    $code = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

if ($MyInvocation.MyCommand.Path) {
    # Saved-file form: propagate the installer's exit code.
    exit $code
} elseif ($code -ne 0) {
    # Piped to iex: never exit the caller's session; surface the failure
    # and leave $LASTEXITCODE readable.
    Write-Error "scaffold-init.sh exited with code $code." -ErrorAction Continue
}
