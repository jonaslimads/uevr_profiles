[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateRange(5, 3600)][int]$Seconds = 120,
    [string]$ProcessName = 'SWGR-Win64-Shipping',
    [ValidateSet('idle', 'shader-compilation', 'flat-screen', 'vr-menu', 'vr-racing')]
    [string]$Phase = 'vr-racing',
    [switch]$IncludeThreads
)

$ErrorActionPreference = 'Stop'
$destination = [IO.Path]::GetFullPath($OutputDirectory)
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($destination.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $destination.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose an output directory outside this repository for raw diagnostics.'
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$runDirectory = Join-Path $destination ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $Phase)
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$gpuCommand = Get-Command nvidia-smi.exe -ErrorAction Stop
$cpuInfo = @(Get-CimInstance Win32_Processor)
$start = Get-Date
[pscustomobject]@{
    Started = $start.ToString('o')
    Phase = $Phase
    ProcessName = $ProcessName
    RequestedSeconds = $Seconds
    CPU = @($cpuInfo | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors)
    IncludeThreads = [bool]$IncludeThreads
    Notes = 'CPU counters are system-wide per logical processor. GameCPUPercent sums process counters and can exceed 100. GPU samples are device-wide. Thread collection adds overhead. Mark track/camera/settings and loading transitions separately.'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDirectory 'run.json') -Encoding UTF8

$gpuFields = 'timestamp,utilization.gpu,utilization.memory,power.draw,power.limit,clocks.gr,clocks.mem,temperature.gpu'
& $gpuCommand.Source '--query-gpu=timestamp,name,driver_version,power.limit' '--format=csv' |
    Set-Content -LiteralPath (Join-Path $runDirectory 'gpu-info.csv') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw 'GPU identification failed.' }
Write-Host "Recording $Phase for $Seconds seconds: $runDirectory"
$timer = [Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
    $sampleTimer = [Diagnostics.Stopwatch]::StartNew()
    $sampleTime = (Get-Date).ToString('o')
    $gpuLines = @(& $gpuCommand.Source "--query-gpu=$gpuFields" '--format=csv,noheader')
    if ($LASTEXITCODE -ne 0) { throw 'GPU sampling failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $runDirectory 'gpu.csv'))) {
        'timestamp, utilization.gpu [%], utilization.memory [%], power.draw [W], power.limit [W], clocks.current.graphics [MHz], clocks.current.memory [MHz], temperature.gpu' |
            Set-Content -LiteralPath (Join-Path $runDirectory 'gpu.csv') -Encoding UTF8
    }
    $gpuLines | Add-Content -LiteralPath (Join-Path $runDirectory 'gpu.csv') -Encoding UTF8
    $gameSamples = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
        Where-Object { $_.Name -eq $ProcessName -or $_.Name -like "$ProcessName#*" })
    $gameCPU = ($gameSamples | Measure-Object PercentProcessorTime -Sum).Sum
    if ($null -eq $gameCPU) { $gameCPU = 0 }
    Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | ForEach-Object {
        [pscustomobject]@{
            Timestamp = $sampleTime
            Core = $_.Name
            CPUPercent = $_.PercentProcessorTime
            GameCPUPercent = $gameCPU
            GameProcessCount = $gameSamples.Count
        }
    } | Export-Csv -LiteralPath (Join-Path $runDirectory 'cpu.csv') -Append -NoTypeInformation
    if ($IncludeThreads) {
        foreach ($gameSample in $gameSamples) {
            Get-CimInstance Win32_PerfFormattedData_PerfProc_Thread -Filter "IDProcess = $($gameSample.IDProcess)" |
                ForEach-Object {
                    [pscustomobject]@{
                        Timestamp = $sampleTime
                        PID = $_.IDProcess
                        TID = $_.IDThread
                        CPUPercent = $_.PercentProcessorTime
                        ThreadState = $_.ThreadState
                        ThreadWaitReason = $_.ThreadWaitReason
                    }
                } | Export-Csv -LiteralPath (Join-Path $runDirectory 'threads.csv') -Append -NoTypeInformation
        }
    }
    $remainingMilliseconds = 1000 - [int]$sampleTimer.Elapsed.TotalMilliseconds
    if ($remainingMilliseconds -gt 0) { Start-Sleep -Milliseconds $remainingMilliseconds }
}
$profileLog = Join-Path $env:APPDATA ("UnrealVRMod/$ProcessName/log.txt")
if (Test-Path -LiteralPath $profileLog) {
    Copy-Item -LiteralPath $profileLog -Destination (Join-Path $runDirectory 'uevr.log')
}
Write-Host "Capture complete: $runDirectory"
