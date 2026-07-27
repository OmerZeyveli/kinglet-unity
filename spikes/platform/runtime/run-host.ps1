#Requires -Version 7.0
<#
.SYNOPSIS
    Native Windows host runner for the 0R runtime bake-off.

.DESCRIPTION
    The Windows counterpart of run-host.sh. For each of the four runtime candidates
    (python, go, rust, dotnet) it:

      1. builds the candidate at its pinned toolchain,
      2. copies ONLY the distributable into a clean exec directory,
      3. runs the packaged artifact with the toolchain directories REMOVED from the
         child PATH (proving the artifact is self-contained),
      4. runs the black-box conformance harness
         (python -m tools.kinglet_spike.runtime_contract) and requires 18/18,
      5. captures the candidate's own result.json,
      6. calls measure.ps1 for cold-start / peak-RSS / artifact-size samples,
      7. assembles a kinglet.spike.evidence/v1 record via build-record.py
         (shared with the POSIX runner — record assembly is platform-neutral), and
      8. publishes it via python -m tools.kinglet_spike publish.

    Host gate: Get-CimInstance Win32_OperatingSystem. Only 'Microsoft Windows 10' and
    'Microsoft Windows 11' captions are accepted; Server, 8.1 and anything else is
    refused. Running under WSL ($env:WSL_DISTRO_NAME set) is refused. The exact
    detected build (Version + BuildNumber + UBR) is recorded in the evidence
    toolchain array rather than hardcoded, and environment.release is derived from
    the caption major plus the registry DisplayVersion (e.g. '11-25H2').

    -DryRun (alias -WhatIf) prints the planned commands and mutates nothing outside
    .kinglet\local\.

    -LibraryOnly defines the functions and returns without gating the host or running
    anything, so the pure helpers can be dot-sourced and tested from any platform:

        . ./run-host.ps1 -LibraryOnly
        Get-DotnetRid -Architecture 'AMD64'         # -> win-x64
        Test-LockedWindowsCaption -Caption '...'    # -> $true / $false

    Conventions (repo CLAUDE.md): -LiteralPath everywhere so a '[' in a Windows path
    is not read as a wildcard; argument ARRAYS to Start-Process and to native calls,
    never a string-evaluated command line; UTF8Encoding($false) for any file write —
    .NET's default UTF8 encoding object emits a BOM, and a BOM on a text file has
    already broken create-project.ps1 in this repo; no bash, no wsl, no absolute
    machine paths.
#>
[CmdletBinding()]
param(
    [Alias('WhatIf')]
    [switch] $DryRun,
    [switch] $LibraryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Set-StrictMode makes an unset $LASTEXITCODE an error, and Invoke-Native reads it
# immediately after the first native call.
$global:LASTEXITCODE = 0

$script:Candidates = @('python', 'go', 'rust', 'dotnet')
$script:ContractDir = 'spikes/platform/runtime/contract'
$script:RuntimeDir = 'spikes/platform/runtime'
$script:DistributableName = 'kinglet-host-probe.exe'
# Commands whose containing directories are stripped from the child PATH before the
# packaged artifact runs. Resolved at runtime — never a hardcoded machine path.
$script:ToolchainCommands = @('go', 'cargo', 'rustc', 'dotnet', 'uv', 'pyinstaller')

# ---------------------------------------------------------------------------
# 1. Pure helpers (testable in isolation via -LibraryOnly)
# ---------------------------------------------------------------------------

function Test-LockedWindowsCaption {
    <#
      The locked Windows hosts are Windows 10 22H2 and Windows 11 25H2, so both the
      10 and the 11 caption are accepted. Windows Server, Windows 8.1 and anything
      else is refused: a non-locked host must produce no record at all.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Caption
    )
    return [bool]($Caption -match '^Microsoft Windows (10|11)(\s|$)')
}

function Get-WindowsMajor {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Caption
    )
    if ($Caption -match '^Microsoft Windows (10|11)(\s|$)') {
        return $Matches[1]
    }
    return ''
}

function Get-WindowsRelease {
    <#
      environment.release must match a matrix cell exactly ('10-22H2', '11-25H2'),
      so it is composed from the detected caption major and the detected registry
      DisplayVersion. Nothing here is hardcoded to one build.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Caption,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $DisplayVersion
    )
    $major = Get-WindowsMajor -Caption $Caption
    if ([string]::IsNullOrWhiteSpace($major) -or [string]::IsNullOrWhiteSpace($DisplayVersion)) {
        return ''
    }
    return ('{0}-{1}' -f $major, $DisplayVersion.Trim().ToUpperInvariant())
}

function Get-DotnetRid {
    <#
      The locked Windows hosts are x64; ARM64 is mapped rather than guessed, and
      anything else is refused instead of silently publishing a wrong RID.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Architecture
    )
    switch ($Architecture.Trim().ToUpperInvariant()) {
        'AMD64' { return 'win-x64' }
        'X64'   { return 'win-x64' }
        'X86_64' { return 'win-x64' }
        'ARM64' { return 'win-arm64' }
        default { return 'unsupported' }
    }
}

function Get-RecordArch {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Architecture
    )
    switch ($Architecture.Trim().ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'X64'   { return 'x64' }
        'X86_64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { return 'unsupported' }
    }
}

function ConvertTo-Slug {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )
    return ([regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9.-]', '-'))
}

function Get-HostSlug {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Release,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Arch
    )
    return (ConvertTo-Slug -Value ('windows-{0}-{1}' -f $Release, $Arch))
}

function Get-StrippedPath {
    <#
      Remove every toolchain directory from a PATH string. Windows path comparison
      is case-insensitive and a trailing separator is not significant, so both are
      normalised before comparing. Empty entries are dropped.

      The separator is the literal Windows ';' rather than
      [System.IO.Path]::PathSeparator, so the function is exercisable from a
      non-Windows test host (where PathSeparator would be ':').
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ToolchainDirectory,
        [char] $Separator = ';'
    )
    $normalise = {
        param([string] $Value)
        return $Value.Trim().TrimEnd('\', '/').ToLowerInvariant()
    }
    $blocked = New-Object System.Collections.Generic.HashSet[string]
    foreach ($dir in $ToolchainDirectory) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $null = $blocked.Add((& $normalise $dir))
    }
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Path.Split($Separator)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ($blocked.Contains((& $normalise $entry))) { continue }
        $kept.Add($entry.Trim())
    }
    return ($kept -join $Separator)
}

function Get-RunId {
    param(
        [Parameter(Mandatory)] [string] $Stamp,
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [string] $HostSlug
    )
    return ('{0}-runtime-{1}-{2}-01' -f $Stamp, $Candidate, $HostSlug)
}

function Get-CandidateVersion {
    param([Parameter(Mandatory)] [string] $Candidate)
    switch ($Candidate) {
        'python' { return '3.14.6' }
        'go'     { return '1.26.5' }
        'rust'   { return '1.97.1' }
        'dotnet' { return '10.0.10' }
        default  { throw "unknown candidate: $Candidate" }
    }
}

function Get-CandidateDependencyCount {
    param([Parameter(Mandatory)] [string] $Candidate)
    switch ($Candidate) {
        'python' { return 12 }
        'go'     { return 0 }
        'rust'   { return 55 }
        'dotnet' { return 4 }
        default  { throw "unknown candidate: $Candidate" }
    }
}

function Get-CandidateVersionArg {
    param([Parameter(Mandatory)] [string] $Candidate)
    if ($Candidate -eq 'python') { return 'version' }
    return '--version'
}

function Get-CandidateDistributable {
    param(
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [string] $DotnetRid
    )
    switch ($Candidate) {
        'python' { return "$script:RuntimeDir/python/dist/$script:DistributableName" }
        'go'     { return "$script:RuntimeDir/go/dist/$script:DistributableName" }
        'rust'   { return "$script:RuntimeDir/rust/target/release/$script:DistributableName" }
        'dotnet' { return "$script:RuntimeDir/dotnet/bin/Release/net10.0/$DotnetRid/publish/$script:DistributableName" }
        default  { throw "unknown candidate: $Candidate" }
    }
}

function Get-CandidateToolchainLine {
    param([Parameter(Mandatory)] [string] $Candidate)
    switch ($Candidate) {
        'python' { return @('python=3.14.6', 'pyinstaller=6.21.0') }
        'go'     { return @('go=1.26.5') }
        'rust'   { return @('rustc=1.97.1', 'cargo=1.97.1') }
        'dotnet' { return @('dotnet-sdk=10.0.302', 'dotnet-runtime=10.0.10', 'nsec.cryptography=26.4.0') }
        default  { throw "unknown candidate: $Candidate" }
    }
}

function Get-CandidateSource {
    param([Parameter(Mandatory)] [string] $Candidate)
    switch ($Candidate) {
        'python' {
            return @(
                'Python 3.14.6|https://www.python.org/downloads/release/python-3146/',
                'PyInstaller 6.21.0|https://pyinstaller.org/en/stable/CHANGES.html'
            )
        }
        'go' { return @('Go 1.26.5|https://go.dev/dl/') }
        'rust' { return @('Rust 1.97.1|https://forge.rust-lang.org/infra/other-installation-methods.html') }
        'dotnet' {
            return @(
                '.NET 10.0.10 runtime|https://dotnet.microsoft.com/en-us/download/dotnet/10.0',
                'NSec.Cryptography 26.4.0|https://nsec.rocks/'
            )
        }
        default { throw "unknown candidate: $Candidate" }
    }
}

function Format-WindowsHostLine {
    <#
      The exact detected host, recorded verbatim in the evidence toolchain array.
      No build number is hardcoded anywhere in this script.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Caption,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Version,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $BuildNumber,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $DisplayVersion,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Architecture
    )
    return ('host={0} (version={1}; build={2}; display-version={3}; arch={4})' -f
        $Caption, $Version, $BuildNumber, $DisplayVersion, $Architecture)
}

# ---------------------------------------------------------------------------
# 2. Host gate and environment discovery
# ---------------------------------------------------------------------------

function Write-Log {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Message)
    [Console]::Error.WriteLine("[run-host] $Message")
}

function Assert-NotWsl {
    if (-not [string]::IsNullOrWhiteSpace($env:WSL_DISTRO_NAME)) {
        throw "run-host.ps1: refusing to run under WSL (WSL_DISTRO_NAME=$($env:WSL_DISTRO_NAME))"
    }
}

function Get-WindowsDisplayVersion {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    try {
        $item = Get-ItemProperty -LiteralPath $key -Name 'DisplayVersion' -ErrorAction Stop
        return [string]$item.DisplayVersion
    } catch {
        return ''
    }
}

function Get-WindowsUpdateBuildRevision {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    try {
        $item = Get-ItemProperty -LiteralPath $key -Name 'UBR' -ErrorAction Stop
        return [string]$item.UBR
    } catch {
        return ''
    }
}

function Resolve-HostEnvironment {
    <#
      Refuses the host rather than proceeding. Never fabricates a pass: a caption
      that is not Windows 10/11, a missing DisplayVersion, or an unsupported
      architecture all abort before anything is built.
    #>
    Assert-NotWsl

    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $caption = [string]$osInfo.Caption
    if (-not (Test-LockedWindowsCaption -Caption $caption)) {
        throw "run-host.ps1: host not accepted (caption='$caption'); accept only 'Microsoft Windows 10' or 'Microsoft Windows 11'"
    }

    $displayVersion = Get-WindowsDisplayVersion
    $release = Get-WindowsRelease -Caption $caption -DisplayVersion $displayVersion
    if ([string]::IsNullOrWhiteSpace($release)) {
        throw "run-host.ps1: could not derive environment.release (caption='$caption'; DisplayVersion='$displayVersion')"
    }

    $architecture = [string]$env:PROCESSOR_ARCHITECTURE
    $arch = Get-RecordArch -Architecture $architecture
    $rid = Get-DotnetRid -Architecture $architecture
    if ($arch -eq 'unsupported' -or $rid -eq 'unsupported') {
        throw "run-host.ps1: unsupported architecture: $architecture"
    }

    $ubr = Get-WindowsUpdateBuildRevision
    $buildNumber = [string]$osInfo.BuildNumber
    if (-not [string]::IsNullOrWhiteSpace($ubr)) {
        $buildNumber = "$buildNumber.$ubr"
    }

    return [pscustomobject]@{
        Caption        = $caption
        Version        = [string]$osInfo.Version
        BuildNumber    = $buildNumber
        DisplayVersion = $displayVersion
        Architecture   = $architecture
        RecordOs       = 'windows'
        RecordRelease  = $release
        RecordArch     = $arch
        DotnetRid      = $rid
        HostLine       = (Format-WindowsHostLine -Caption $caption -Version ([string]$osInfo.Version) `
                            -BuildNumber $buildNumber -DisplayVersion $displayVersion `
                            -Architecture $architecture)
        KernelLine     = ("kernel=Windows NT {0}" -f [string]$osInfo.Version)
        HostSlug       = (Get-HostSlug -Release $release -Arch $arch)
    }
}

function Get-ToolchainDirectory {
    <#
      The directories that actually provide the build toolchains on this host,
      resolved from the command table. Nothing is hardcoded, so no machine path
      or user name is committed to the repository.
    #>
    param([Parameter(Mandatory)] [string[]] $CommandName)
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($name in $CommandName) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $command) { continue }
        $parent = Split-Path -Parent $command.Source
        if (-not [string]::IsNullOrWhiteSpace($parent)) { $dirs.Add($parent) }
    }
    return ($dirs | Sort-Object -Unique)
}

function Resolve-PythonCommand {
    foreach ($name in @('python3', 'python', 'py')) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    throw 'run-host.ps1: no python interpreter found (tried python3, python, py)'
}

function Invoke-Native {
    <#
      Native calls always take an argument ARRAY, never a string command line, and
      a non-zero exit is an error: PowerShell does not raise on native failure.
    #>
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ArgumentList,
        [string] $WorkingDirectory
    )
    $previous = $null
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $previous = (Get-Location).ProviderPath
        Set-Location -LiteralPath $WorkingDirectory
    }
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "run-host.ps1: command failed (exit $LASTEXITCODE): $FilePath $($ArgumentList -join ' ')"
        }
    } finally {
        if ($null -ne $previous) { Set-Location -LiteralPath $previous }
    }
}

# ---------------------------------------------------------------------------
# 3. Build step per candidate
# ---------------------------------------------------------------------------

function Build-Candidate {
    param(
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [string] $DotnetRid,
        [Parameter(Mandatory)] [string] $RepoRoot
    )
    switch ($Candidate) {
        'python' {
            # The PyInstaller onefile is platform-specific: the Linux artifact cannot
            # be reused, so it is built here from the pinned lock with uv.
            Write-Log 'python: uv run pyinstaller --clean kinglet-host-probe.spec'
            Invoke-Native -FilePath 'uv' -ArgumentList @(
                'sync', '--project', "$script:RuntimeDir/python", '--frozen', '--python', '3.14.6'
            ) -WorkingDirectory $RepoRoot
            Invoke-Native -FilePath 'uv' -ArgumentList @(
                'run', '--project', "$script:RuntimeDir/python",
                'pyinstaller', '--clean', '--distpath', "$script:RuntimeDir/python/dist",
                "$script:RuntimeDir/python/kinglet-host-probe.spec"
            ) -WorkingDirectory $RepoRoot
        }
        'go' {
            Write-Log 'go: go build -trimpath -ldflags="-s -w"'
            $env:GOTOOLCHAIN = 'local'
            Invoke-Native -FilePath 'go' -ArgumentList @(
                'build', '-trimpath', '-ldflags=-s -w', '-o', "dist/$script:DistributableName", '.'
            ) -WorkingDirectory (Join-Path -Path $RepoRoot -ChildPath "$script:RuntimeDir/go")
        }
        'rust' {
            Write-Log 'rust: cargo build --locked --release'
            Invoke-Native -FilePath 'cargo' -ArgumentList @(
                'build', '--locked', '--release'
            ) -WorkingDirectory (Join-Path -Path $RepoRoot -ChildPath "$script:RuntimeDir/rust")
        }
        'dotnet' {
            # IncludeNativeLibrariesForSelfExtract embeds NSec's libsodium.dll into the
            # bundle so the single binary is relocatable (see the Linux runner's finding).
            Write-Log "dotnet: dotnet publish -r $DotnetRid --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true"
            Invoke-Native -FilePath 'dotnet' -ArgumentList @(
                'publish', 'Kinglet.HostProbe.csproj', '-c', 'Release', '-r', $DotnetRid,
                '--self-contained', 'true',
                '-p:PublishSingleFile=true',
                '-p:IncludeNativeLibrariesForSelfExtract=true',
                '-p:RestoreLockedMode=false'
            ) -WorkingDirectory (Join-Path -Path $RepoRoot -ChildPath "$script:RuntimeDir/dotnet")
        }
        default { throw "unknown candidate: $Candidate" }
    }
}

# ---------------------------------------------------------------------------
# 4. Per-candidate driver
# ---------------------------------------------------------------------------

function Invoke-CandidateCell {
    param(
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [psobject] $HostEnvironment,
        [Parameter(Mandatory)] [string] $Stamp,
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $RunPath,
        [Parameter(Mandatory)] [string] $PythonCommand,
        [switch] $DryRun
    )
    $version = Get-CandidateVersion -Candidate $Candidate
    $dependencyCount = Get-CandidateDependencyCount -Candidate $Candidate
    $versionArg = Get-CandidateVersionArg -Candidate $Candidate
    $dist = Get-CandidateDistributable -Candidate $Candidate -DotnetRid $HostEnvironment.DotnetRid
    $runId = Get-RunId -Stamp $Stamp -Candidate $Candidate -HostSlug $HostEnvironment.HostSlug

    $runRoot = ".kinglet/local/spikes/$runId"
    $execDir = "$runRoot/exec"
    $workspace = "$runRoot/workspace"
    $artifactRel = "artifacts/runtime/$Candidate/$runId/result.json"
    $resultFile = "$runRoot/publish/$artifactRel"
    $recordFile = "$runRoot/record.json"
    $exe = "$execDir/$script:DistributableName"

    if ($DryRun) {
        Write-Log "DRY-RUN ${Candidate}:"
        Write-Log "  build: Build-Candidate $Candidate (rid=$($HostEnvironment.DotnetRid))"
        Write-Log "  mkdir empty run dir: $runRoot"
        Write-Log "  copy distributable: $dist -> $exe"
        Write-Log "  run packaged (PATH without toolchains): $exe run --contract $script:ContractDir/host-probe-v1.json --workspace $workspace --result <result>"
        Write-Log "  conformance: PATH=<stripped> python -m tools.kinglet_spike.runtime_contract --executable $exe --contract-dir $script:ContractDir"
        Write-Log "  measure: pwsh $script:RuntimeDir/measure.ps1 -Exe $exe -DependencyCount $dependencyCount -VersionArg $versionArg"
        Write-Log "  assemble record -> $recordFile (run_id=$runId; os=$($HostEnvironment.RecordOs); release=$($HostEnvironment.RecordRelease); arch=$($HostEnvironment.RecordArch))"
        Write-Log "  publish: python -m tools.kinglet_spike publish $recordFile --repo-root ."
        return
    }

    Write-Log "=== candidate: $Candidate (run_id=$runId) ==="

    Build-Candidate -Candidate $Candidate -DotnetRid $HostEnvironment.DotnetRid -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $dist)) {
        throw "run-host.ps1: $Candidate distributable missing after build: $dist"
    }

    # Require an empty run dir (fail if it already has content).
    if (Test-Path -LiteralPath $runRoot) {
        $existing = @(Get-ChildItem -LiteralPath $runRoot -Force)
        if ($existing.Count -gt 0) {
            throw "run-host.ps1: run dir is not empty: $runRoot"
        }
    }
    $null = New-Item -ItemType Directory -Force -Path $execDir
    $null = New-Item -ItemType Directory -Force -Path $workspace
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resultFile)

    # Copy ONLY the distributable into the clean exec dir. No toolchain, no source,
    # no build tree. The .NET publish embeds its native libraries, so there are no
    # sidecars on any platform.
    Copy-Item -LiteralPath $dist -Destination $exe -Force

    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Log "${Candidate}: distributable sha256=$hash"

    $startedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    # (a) Run the packaged artifact with the toolchain dirs REMOVED from the child
    #     PATH (self-contained proof).
    Write-Log "${Candidate}: running packaged artifact with toolchain-stripped PATH"
    $savedPath = $env:PATH
    try {
        $env:PATH = $RunPath
        Invoke-Native -FilePath (Resolve-Path -LiteralPath $exe).ProviderPath -ArgumentList @(
            'run',
            '--contract', (Join-Path -Path $RepoRoot -ChildPath "$script:ContractDir/host-probe-v1.json"),
            '--workspace', (Join-Path -Path $RepoRoot -ChildPath $workspace),
            '--result', (Join-Path -Path $RepoRoot -ChildPath $resultFile)
        )

        # (b) Independent black-box conformance verification (18/18), also with a
        #     toolchain-stripped PATH.
        Write-Log "${Candidate}: black-box conformance (runtime_contract)"
        Invoke-Native -FilePath $PythonCommand -ArgumentList @(
            '-m', 'tools.kinglet_spike.runtime_contract',
            '--executable', $exe,
            '--contract-dir', $script:ContractDir
        )
    } finally {
        $env:PATH = $savedPath
    }

    if (-not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
        throw "run-host.ps1: $Candidate did not write result.json: $resultFile"
    }

    # (c) Measure.
    Write-Log "${Candidate}: measuring cold-start / peak-rss / artifact-size"
    $measureScript = Join-Path -Path $RepoRoot -ChildPath "$script:RuntimeDir/measure.ps1"
    $measureJson = & $measureScript -Exe $exe -DependencyCount $dependencyCount -VersionArg $versionArg
    if ($measureJson -is [array]) { $measureJson = ($measureJson -join '') }
    $measureJson = [string]$measureJson

    $endedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    # (d) Assemble the evidence record with the shared, platform-neutral builder.
    #     The command array uses RELATIVE paths only — no user home, no drive letter.
    $commandData = @(
        "$script:RuntimeDir/measure.ps1",
        $exe,
        'run',
        '--contract',
        "$script:ContractDir/host-probe-v1.json",
        '--workspace',
        '<clean-workspace>',
        '--result',
        '<result.json>'
    ) -join "`n"

    $toolchainData = (Get-CandidateToolchainLine -Candidate $Candidate) -join "`n"
    $sourcesData = (Get-CandidateSource -Candidate $Candidate) -join "`n"

    Write-Log "${Candidate}: assembling record"
    Invoke-Native -FilePath $PythonCommand -ArgumentList @(
        (Join-Path -Path $RepoRoot -ChildPath "$script:RuntimeDir/build-record.py"),
        '--candidate', $Candidate,
        '--version', $version,
        '--run-id', $runId,
        '--started-at', $startedAt,
        '--ended-at', $endedAt,
        '--artifact-rel', $artifactRel,
        '--result-file', $resultFile,
        '--measure-json', $measureJson,
        '--os', $HostEnvironment.RecordOs,
        '--release', $HostEnvironment.RecordRelease,
        '--arch', $HostEnvironment.RecordArch,
        '--host-line', $HostEnvironment.HostLine,
        '--kernel-line', $HostEnvironment.KernelLine,
        '--toolchain-data', $toolchainData,
        '--sources-data', $sourcesData,
        '--command-data', $commandData,
        '--out', $recordFile
    )

    # (e) Publish.
    Write-Log "${Candidate}: publishing"
    Invoke-Native -FilePath $PythonCommand -ArgumentList @(
        '-m', 'tools.kinglet_spike', 'publish', $recordFile, '--repo-root', '.'
    )
    Write-Log "${Candidate}: published OK"
}

# ---------------------------------------------------------------------------
# 5. Entry point
# ---------------------------------------------------------------------------

function Invoke-RunHost {
    param([switch] $DryRun)

    $repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).ProviderPath
    Set-Location -LiteralPath $repoRoot

    $hostEnvironment = Resolve-HostEnvironment
    Write-Log ("host accepted: {0} (version={1}; build={2}; release={3}; arch={4}; rid={5})" -f
        $hostEnvironment.Caption, $hostEnvironment.Version, $hostEnvironment.BuildNumber,
        $hostEnvironment.RecordRelease, $hostEnvironment.RecordArch, $hostEnvironment.DotnetRid)

    $toolchainDirs = @(Get-ToolchainDirectory -CommandName $script:ToolchainCommands)
    $runPath = Get-StrippedPath -Path $env:PATH -ToolchainDirectory $toolchainDirs
    Write-Log ("toolchain dirs stripped from child PATH: {0}" -f ($toolchainDirs.Count))

    $pythonCommand = Resolve-PythonCommand
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')

    foreach ($candidate in $script:Candidates) {
        Invoke-CandidateCell -Candidate $candidate -HostEnvironment $hostEnvironment `
            -Stamp $stamp -RepoRoot $repoRoot -RunPath $runPath `
            -PythonCommand $pythonCommand -DryRun:$DryRun
    }

    if ($DryRun) {
        Write-Log 'dry-run complete; nothing published'
    } else {
        Write-Log 'all four candidates published'
    }
}

if ($LibraryOnly) { return }

Invoke-RunHost -DryRun:$DryRun
