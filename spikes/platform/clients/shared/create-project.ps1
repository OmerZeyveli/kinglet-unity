#Requires -Version 5.1
# create-project.ps1 — Create a disposable Kinglet client-probe project (native Windows only).
#
# Usage:
#   .\create-project.ps1 -Destination <path> [-Executable <path>]
#
# Parameters:
#   Destination   Path where the project will be created. Must not already exist.
#   Executable    (optional) Absolute path to kinglet-client-probe.exe.
#                 Defaults to the KINGLET_PROBE_EXECUTABLE env var if set, then
#                 to probe-host\dist\win-x64\kinglet-client-probe.exe relative to
#                 this script's parent repo.
#
# Refuses non-Windows hosts and a destination that already exists.
# Never copies a user profile or credentials.
#
# NOTE: This script is authored for native Windows and cannot be exercised on Linux/macOS.
# It has been reviewed for correctness but is unexecuted on non-Windows hosts.
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Destination,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Executable = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Platform guard — native Windows only
# ---------------------------------------------------------------------------
$isWindowsHost = $false
if (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) {
    $isWindowsHost = $IsWindows
} else {
    # Windows PowerShell 5.1 — only runs on Windows.
    $isWindowsHost = $true
}

if (-not $isWindowsHost) {
    [Console]::Error.WriteLine("create-project.ps1: unsupported host; this script runs only on native Windows. Use create-project.sh on Darwin/Linux.")
    exit 1
}

# ---------------------------------------------------------------------------
# Resolve the executable path
# ---------------------------------------------------------------------------
if ($Executable -eq "") {
    if ($env:KINGLET_PROBE_EXECUTABLE -ne $null -and $env:KINGLET_PROBE_EXECUTABLE -ne "") {
        $Executable = $env:KINGLET_PROBE_EXECUTABLE
    } else {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptDir)))
        $Executable = Join-Path $repoRoot 'spikes\platform\clients\probe-host\dist\win-x64\kinglet-client-probe.exe'
    }
}

# ---------------------------------------------------------------------------
# Destination existence guard
# ---------------------------------------------------------------------------
if (Test-Path $Destination) {
    [Console]::Error.WriteLine("create-project.ps1: destination already exists: $Destination. Delete it first or choose a different path.")
    exit 1
}

# ---------------------------------------------------------------------------
# Executable existence check
# ---------------------------------------------------------------------------
if (-not (Test-Path $Executable)) {
    [Console]::Error.WriteLine("create-project.ps1: executable not found: $Executable. Build it with: .\spikes\platform\clients\probe-host\build.ps1")
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# Create the project tree
# ---------------------------------------------------------------------------
Write-Host "create-project.ps1: creating project at $Destination"

$null = New-Item -ItemType Directory -Force -Path (Join-Path $Destination 'ProjectSettings')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Destination 'Assets')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Destination '.kinglet-probe\receipts')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Destination '.kinglet-probe\bin')

# ProjectSettings/ProjectVersion.txt
$projectVersionContent = "m_EditorVersion: 6000.3.11f1`r`nm_EditorVersionWithRevision: 6000.3.11f1 (3f0e1d94bd20)`r`n"
[System.IO.File]::WriteAllText(
    (Join-Path $Destination 'ProjectSettings/ProjectVersion.txt'),
    $projectVersionContent,
    (New-Object System.Text.UTF8Encoding($false))
)

# .kinglet-probe/project-marker.txt — exact marker, no trailing newline
[System.IO.File]::WriteAllText(
    (Join-Path $Destination '.kinglet-probe/project-marker.txt'),
    'KINGLET_CLIENT_PROBE_PROJECT',
    (New-Object System.Text.UTF8Encoding($false))
)

# Assets/Protected.txt
[System.IO.File]::WriteAllText(
    (Join-Path $Destination 'Assets/Protected.txt'),
    "PROTECTED`r`n",
    (New-Object System.Text.UTF8Encoding($false))
)

# CLAUDE.md — project-level instructions for the instructions.project case.
# Claude Code loads this file automatically when starting a session in this directory.
$ruleContent = [System.IO.File]::ReadAllText(
    (Join-Path $scriptDir 'rules\kinglet-capability-probe.md'),
    (New-Object System.Text.UTF8Encoding($false))
)
[System.IO.File]::WriteAllText(
    (Join-Path $Destination 'CLAUDE.md'),
    $ruleContent,
    (New-Object System.Text.UTF8Encoding($false))
)

# ---------------------------------------------------------------------------
# Copy the native executable
# ---------------------------------------------------------------------------
$destExe = Join-Path $Destination '.kinglet-probe\bin\kinglet-client-probe.exe'
Copy-Item -Path $Executable -Destination $destExe -Force

# ---------------------------------------------------------------------------
# Compute SHA-256 of the copied executable
# ---------------------------------------------------------------------------
$sha256Bytes = (Get-FileHash -Path $destExe -Algorithm SHA256).Hash.ToLower()

# ---------------------------------------------------------------------------
# Write .kinglet-probe/expected.json
# ---------------------------------------------------------------------------
$expectedJson = @"
{
  "schema": "kinglet.client-probe.expected/v1",
  "executable": ".kinglet-probe/bin/kinglet-client-probe.exe",
  "sha256": "$sha256Bytes"
}
"@
[System.IO.File]::WriteAllText(
    (Join-Path $Destination '.kinglet-probe\expected.json'),
    $expectedJson,
    (New-Object System.Text.UTF8Encoding($false))
)

# ---------------------------------------------------------------------------
# Install MCP config — replace executable token with the absolute path
# ---------------------------------------------------------------------------
$mcpTemplate = [System.IO.File]::ReadAllText(
    (Join-Path $scriptDir 'mcp.json'),
    (New-Object System.Text.UTF8Encoding($false))
)
$absBinPath = (Resolve-Path $destExe).Path
# The substituted value is a JSON string value, so backslash and double-quote must be
# escaped at the JSON layer before substitution.  Windows paths always contain '\',
# which without escaping would produce invalid JSON (e.g. \U, \k are invalid escapes).
#   1. Escape backslash: \ → \\
#   2. Escape double-quote: " → \"
# Using String.Replace (not -replace) avoids regex interpretation of the replacement.
$absBinJsonEscaped = $absBinPath.Replace('\', '\\').Replace('"', '\"')
$mcpContent = $mcpTemplate.Replace('__KINGLET_PROBE_EXECUTABLE__', $absBinJsonEscaped)
[System.IO.File]::WriteAllText(
    (Join-Path $Destination '.kinglet-probe\mcp.json'),
    $mcpContent,
    (New-Object System.Text.UTF8Encoding($false))
)

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host "create-project.ps1: project created"
Write-Host "create-project.ps1: executable sha256 = $sha256Bytes"
Write-Host "create-project.ps1: smoke-test: $destExe exec --project $Destination --output $Destination\.kinglet-probe\receipts\workflow.json"
