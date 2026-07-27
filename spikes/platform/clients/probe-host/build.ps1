#Requires -Version 5.1
# Build the native kinglet-client-probe.exe for native Windows only.
#
# Validates that the host is Windows and never cross-builds: the artifact
# reflects the host's own GOOS/GOARCH so what is reported as executed is what
# actually ran here.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$isWindowsHost = $false
if (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) {
    $isWindowsHost = $IsWindows
} else {
    # Windows PowerShell 5.1 has no $IsWindows; it only runs on Windows.
    $isWindowsHost = $true
}

if (-not $isWindowsHost) {
    Write-Error "build.ps1: unsupported host; this script builds only on native Windows. Use build.sh on Darwin/Linux."
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$goos = (& go env GOHOSTOS).Trim()
$goarch = (& go env GOHOSTARCH).Trim()

if ($goos -ne 'windows') {
    Write-Error "build.ps1: GOHOSTOS is '$goos', expected 'windows'; refusing to cross-build."
    exit 1
}

$outDir = Join-Path $scriptDir 'dist\win-x64'
$outBin = Join-Path $outDir 'kinglet-client-probe.exe'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "build.ps1: building $goos/$goarch -> $outBin"

Push-Location $scriptDir
try {
    $env:GOOS = $goos
    $env:GOARCH = $goarch
    $env:GOTOOLCHAIN = 'local'
    & go build -trimpath -o $outBin .
    if ($LASTEXITCODE -ne 0) {
        Write-Error "build.ps1: go build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}

Write-Host "build.ps1: done"
