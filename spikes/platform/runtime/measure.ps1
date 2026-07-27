#Requires -Version 7.0
<#
.SYNOPSIS
    Collect performance measurements for one packaged host-probe artifact on Windows.

.DESCRIPTION
    The Windows counterpart of measure.sh. Emits a single JSON object on stdout:

        {"cold_start_ms":[<30 ints>],"peak_rss_kb":<int>,"artifact_bytes":<int>,"dependency_count":<int>}

    Cold-start: 30 wall-clock samples of the version invocation (Measure-Command),
                in integer milliseconds.
    Peak RSS:   Process.PeakWorkingSet64 reports BYTES; peak_rss_kb in the evidence
                record is KILOBYTES on every platform, so it is divided by 1024 here.
                Losing that divide would silently make Windows look 1024x worse than
                Linux and nothing downstream would catch it — Convert-BytesToKilobytes
                is asserted by a test.
    Artifact:   file size in bytes.

    -LibraryOnly defines the functions and returns without measuring anything, so the
    pure helpers can be dot-sourced and tested from any platform:

        . ./measure.ps1 -LibraryOnly
        Convert-BytesToKilobytes -Bytes 2097152   # -> 2048

    Conventions (repo CLAUDE.md): -LiteralPath everywhere so a '[' in a Windows path is
    not read as a wildcard; argument ARRAYS to Start-Process, never a string command
    line; no bash, no wsl; UTF8Encoding($false) for any file write (BOM-free).
#>
[CmdletBinding()]
param(
    [string] $Exe,
    [int] $DependencyCount = -1,
    [string] $VersionArg,
    [switch] $LibraryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ColdStartSampleCount = 30

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

function Convert-BytesToKilobytes {
    <#
      PeakWorkingSet64 and Get-Item Length are BYTES. The evidence record's
      peak_rss_kb field is KILOBYTES on every platform. 1 KB = 1024 bytes,
      rounded up so a non-zero measurement never reports as 0.
    #>
    param(
        [Parameter(Mandatory)]
        [long] $Bytes
    )
    if ($Bytes -le 0) { return [long]0 }
    return [long][math]::Ceiling($Bytes / 1024.0)
}

function Assert-NonZeroPeak {
    <#
      A real process cannot peak at 0 KB. Publishing 0 would be a placeholder in
      place of a real measurement, so this THROWS instead. Extracted as a pure
      function because the comparison itself is the invariant: inverting it in an
      inline `if` inside Main would silently make the guard unfireable, and a test
      that only asserts the message string exists would not notice.
    #>
    param(
        [Parameter(Mandatory)]
        [long] $PeakRssKb
    )
    if ($PeakRssKb -le 0) {
        throw 'measure.ps1: peak working set measured as 0 bytes; refusing to emit a fabricated measurement'
    }
}

function ConvertTo-SampleMilliseconds {
    <#
      A TimeSpan to a positive integer millisecond sample. A native binary can
      start in under a millisecond; the measurement schema requires positive ints,
      so anything below 1 is clamped to 1 (same rule as measure.sh).
    #>
    param(
        [Parameter(Mandatory)]
        [double] $TotalMilliseconds
    )
    $value = [int][math]::Round($TotalMilliseconds)
    if ($value -lt 1) { $value = 1 }
    return $value
}

function Format-MeasurementJson {
    <#
      Hand-formatted so the payload is byte-identical in shape to measure.sh's
      output and invariant of the host culture (a comma decimal separator would
      otherwise corrupt the JSON).
    #>
    param(
        [Parameter(Mandatory)] [int[]] $ColdStartMs,
        [Parameter(Mandatory)] [long] $PeakRssKb,
        [Parameter(Mandatory)] [long] $ArtifactBytes,
        [Parameter(Mandatory)] [int] $DependencyCount
    )
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $samples = ($ColdStartMs | ForEach-Object { $_.ToString($culture) }) -join ','
    return '{"cold_start_ms":[' + $samples + '],"peak_rss_kb":' + $PeakRssKb.ToString($culture) +
        ',"artifact_bytes":' + $ArtifactBytes.ToString($culture) +
        ',"dependency_count":' + $DependencyCount.ToString($culture) + '}'
}

# ---------------------------------------------------------------------------
# Measurement primitives
# ---------------------------------------------------------------------------

function Measure-ColdStartSamples {
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string] $VersionArg,
        [int] $SampleCount = $script:ColdStartSampleCount
    )
    $samples = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $SampleCount; $index++) {
        # Direct invocation with an argument array, matching measure.sh: Start-Process
        # would add its own launcher overhead to every sample and make the Windows
        # cold-start column incomparable with Linux/macOS.
        $elapsed = Measure-Command { & $Exe @($VersionArg) *> $null }
        $samples.Add((ConvertTo-SampleMilliseconds -TotalMilliseconds $elapsed.TotalMilliseconds))
    }
    return $samples.ToArray()
}

function Measure-PeakWorkingSetBytes {
    <#
      Poll PeakWorkingSet64 while the child runs, then read it once more after exit
      (on Windows the Process object keeps the handle open, so the post-exit read is
      the authoritative one; on other platforms it throws and the polled maximum is
      kept).

      THE SEAM. This is the only Windows-only step in Invoke-Measure, and it is a
      separate function so a test can redefine it with a canned byte count and then
      execute Invoke-Measure for real on a non-Windows box. Without that, the
      bytes -> kilobytes conversion at Invoke-Measure's call site is unexecutable
      here: deleting `Convert-BytesToKilobytes` there would publish BYTES in
      peak_rss_kb, make Windows look 1024x worse than Linux, and nothing downstream
      would catch it. Mirrors measure.sh's capture_time_output seam, which is what
      lets measure_peak_rss_kb's divide be driven from canned /usr/bin/time output.

      The child's stdout/stderr are redirected to temp files: with -NoNewWindow the
      child inherits this process's stdout, and the artifact's version banner would
      then be interleaved with the measurement JSON on stdout and corrupt it.
    #>
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string] $VersionArg
    )
    $peak = [long]0
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $Exe -ArgumentList @($VersionArg) `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        while (-not $process.HasExited) {
            try {
                $process.Refresh()
                if ($process.PeakWorkingSet64 -gt $peak) { $peak = [long]$process.PeakWorkingSet64 }
            } catch {
                break
            }
            Start-Sleep -Milliseconds 2
        }
        $process.WaitForExit()
        try {
            if ($process.PeakWorkingSet64 -gt $peak) { $peak = [long]$process.PeakWorkingSet64 }
        } catch {
            # Process already reaped on this platform; keep the polled maximum.
        }
    } finally {
        Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue
    }
    return $peak
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Invoke-Measure {
    <#
      Main, as a function, for the same reason run-host.ps1 has Invoke-RunHost: the
      call sites are the part worth testing. With Main inline below `if
      ($LibraryOnly) { return }` the units line
      (`Convert-BytesToKilobytes -Bytes $peakBytes`) was unreachable from any test
      on this platform, so dropping the conversion there was invisible even though
      the helper itself is covered. Dot-source with -LibraryOnly, redefine
      Measure-PeakWorkingSetBytes with a canned byte count, and this whole path runs.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Exe,
        [Parameter(Mandatory)] [int] $DependencyCount,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $VersionArg
    )

    # [Console]::Error.WriteLine rather than Write-Error: $ErrorActionPreference='Stop'
    # turns Write-Error into a TERMINATING error, so the `exit <n>` beneath it never
    # runs and the process exits 1 instead of the documented 2/3. measure.sh's exit
    # codes are part of the contract the runner reads.
    if ([string]::IsNullOrWhiteSpace($Exe) -or [string]::IsNullOrWhiteSpace($VersionArg) -or $DependencyCount -lt 0) {
        [Console]::Error.WriteLine('usage: measure.ps1 -Exe <path> -DependencyCount <int> -VersionArg <string>')
        exit 2
    }
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        [Console]::Error.WriteLine("measure.ps1: not a file: $Exe")
        exit 2
    }

    $exePath = (Resolve-Path -LiteralPath $Exe).ProviderPath

    $coldStart = Measure-ColdStartSamples -Exe $exePath -VersionArg $VersionArg
    $peakBytes = Measure-PeakWorkingSetBytes -Exe $exePath -VersionArg $VersionArg
    # BYTES -> KILOBYTES. peak_rss_kb is kilobytes on every platform; losing this
    # call publishes bytes under a kilobyte name.
    $peakRssKb = Convert-BytesToKilobytes -Bytes $peakBytes
    # (This fires when the script is run on a non-Windows host, where PeakWorkingSet64
    # is unavailable after exit.)
    try {
        Assert-NonZeroPeak -PeakRssKb $peakRssKb
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 3
    }
    $artifactBytes = [long](Get-Item -LiteralPath $exePath).Length

    return (Format-MeasurementJson -ColdStartMs $coldStart -PeakRssKb $peakRssKb `
        -ArtifactBytes $artifactBytes -DependencyCount $DependencyCount)
}

if ($LibraryOnly) { return }

Invoke-Measure -Exe $Exe -DependencyCount $DependencyCount -VersionArg $VersionArg
