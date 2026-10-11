[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateRange(5, 3600)][int]$Seconds = 120,
    [string]$ProcessName = 'SWGR-Win64-Shipping',
    [ValidateSet('idle', 'shader-compilation', 'flat-screen', 'vr-menu', 'vr-racing')]
    [string]$Phase = 'vr-racing',
    [switch]$IncludeThreads,
    [switch]$UseProcessCounters
)

$ErrorActionPreference = 'Stop'
if ($IncludeThreads -and -not ('UEVRPerformance.ThreadNames' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace UEVRPerformance {
    public static class ThreadNames {
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern IntPtr OpenThread(uint access, bool inherit, uint threadId);
        [DllImport("kernel32.dll")]
        static extern int GetThreadDescription(IntPtr thread, out IntPtr description);
        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);
        public static string Read(uint threadId, out int error) {
            error = 0;
            IntPtr handle = OpenThread(0x0800, false, threadId);
            if (handle == IntPtr.Zero) { error = Marshal.GetLastWin32Error(); return ""; }
            IntPtr description = IntPtr.Zero;
            try {
                int result = GetThreadDescription(handle, out description);
                if (result < 0) { error = result; return ""; }
                return description == IntPtr.Zero ? "" : Marshal.PtrToStringUni(description);
            } finally {
                if (description != IntPtr.Zero) LocalFree(description);
                CloseHandle(handle);
            }
        }
    }
}
'@
}
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
$cpuInfo = if ($UseProcessCounters) {
    @([pscustomobject]@{Name='Not queried (process counter mode)'; NumberOfCores=$null; NumberOfLogicalProcessors=[Environment]::ProcessorCount})
} else { @(Get-CimInstance Win32_Processor) }
$previousProcessCPU = @{}
$previousThreadCPU = @{}
$start = Get-Date
[pscustomobject]@{
    Started = $start.ToString('o')
    Phase = $Phase
    ProcessName = $ProcessName
    RequestedSeconds = $Seconds
    CPU = @($cpuInfo | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors)
    IncludeThreads = [bool]$IncludeThreads
    UseProcessCounters = [bool]$UseProcessCounters
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
    if ($UseProcessCounters) {
        $elapsedSample = $timer.Elapsed.TotalSeconds
        foreach ($gameProcess in @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {
            $processKey = "$($gameProcess.Id):$($gameProcess.StartTime.Ticks)"
            $processCPUSeconds = $gameProcess.TotalProcessorTime.TotalSeconds
            $priorCPU = $previousProcessCPU[$processKey]
            $processPercent = if ($null -ne $priorCPU -and $elapsedSample -gt $priorCPU.Time) {
                100 * ($processCPUSeconds - $priorCPU.CPU) / ($elapsedSample - $priorCPU.Time)
            } else { $null }
            $previousProcessCPU[$processKey] = @{CPU=$processCPUSeconds; Time=$elapsedSample}
            [pscustomobject]@{Timestamp=$sampleTime; PID=$gameProcess.Id; GameCPUPercent=$processPercent; LogicalProcessors=[Environment]::ProcessorCount} |
                Export-Csv -LiteralPath (Join-Path $runDirectory 'process-cpu.csv') -Append -NoTypeInformation
            if ($IncludeThreads) {
                foreach ($processThread in $gameProcess.Threads) {
                    $threadNameError = 0
                    $threadDescription = [UEVRPerformance.ThreadNames]::Read([uint32]$processThread.Id, [ref]$threadNameError)
                    $counterError = ''
                    $threadPercent = $null
                    try {
                        $threadKey = "$processKey`:$($processThread.Id):$($processThread.StartTime.Ticks)"
                        $threadCPUSeconds = $processThread.TotalProcessorTime.TotalSeconds
                        $priorThreadCPU = $previousThreadCPU[$threadKey]
                        if ($null -ne $priorThreadCPU -and $elapsedSample -gt $priorThreadCPU.Time) {
                            $threadPercent = 100 * ($threadCPUSeconds - $priorThreadCPU.CPU) / ($elapsedSample - $priorThreadCPU.Time)
                        }
                        $previousThreadCPU[$threadKey] = @{CPU=$threadCPUSeconds; Time=$elapsedSample}
                    } catch { $counterError = $_.Exception.Message }
                    [pscustomobject]@{Timestamp=$sampleTime; PID=$gameProcess.Id; TID=$processThread.Id; Description=$threadDescription; DescriptionError=$threadNameError; CPUPercent=$threadPercent; CounterError=$counterError} |
                        Export-Csv -LiteralPath (Join-Path $runDirectory 'threads.csv') -Append -NoTypeInformation
                }
            }
        }
    } else {
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
                    $threadNameError = 0
                    $threadDescription = [UEVRPerformance.ThreadNames]::Read([uint32]$_.IDThread, [ref]$threadNameError)
                    [pscustomobject]@{
                        Timestamp = $sampleTime
                        PID = $_.IDProcess
                        TID = $_.IDThread
                        Description = $threadDescription
                        DescriptionError = $threadNameError
                        CPUPercent = $_.PercentProcessorTime
                        ThreadState = $_.ThreadState
                        ThreadWaitReason = $_.ThreadWaitReason
                    }
                } | Export-Csv -LiteralPath (Join-Path $runDirectory 'threads.csv') -Append -NoTypeInformation
        }
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
