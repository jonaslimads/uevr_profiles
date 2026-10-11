[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [ValidateRange(5, 300)][int]$Seconds = 60,
    [string]$ProcessName = 'SWGR-Win64-Shipping',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$wprCommand = Get-Command wpr.exe -ErrorAction Stop
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdministrator = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$status = (& $wprCommand.Source -status 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "Cannot inspect WPR status: $status" }
$idle = $status -match 'WPR is not recording'
if ($CheckOnly) {
    [pscustomobject]@{WPR=$wprCommand.Source; IsAdministrator=$isAdministrator; NoExistingRecording=$idle; ReadyToRecord=($isAdministrator -and $idle)}
    return
}
if (-not $isAdministrator) { throw 'CPU stack recording requires an administrator terminal. No recording was started.' }
if (-not $idle) { throw 'WPR reports an existing or unrecognized recording state. Preserve that recording before starting this capture.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'Supply an output directory outside this repository.' }
$destination = [IO.Path]::GetFullPath($OutputDirectory)
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($destination.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $destination.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose an output directory outside this repository for raw traces.'
}
$gameProcesses = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
if ($gameProcesses.Count -ne 1) { throw 'Start exactly one target game process before recording CPU stacks.' }
$gameProcess = $gameProcesses[0]
$runDirectory = Join-Path $destination ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-cpu-stacks')
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$profileLog = Join-Path $env:APPDATA ("UnrealVRMod/$ProcessName/log.txt")
$modules = @($gameProcess.Modules | ForEach-Object {
    [pscustomobject]@{Name=$_.ModuleName; Path=$_.FileName; Base=('0x{0:x}' -f $_.BaseAddress.ToInt64()); Size=$_.ModuleMemorySize}
})
$modules | Export-Csv -LiteralPath (Join-Path $runDirectory 'modules.csv') -NoTypeInformation
$gameProcess.Threads | ForEach-Object {
    [pscustomobject]@{PID=$gameProcess.Id; TID=$_.Id}
} | Export-Csv -LiteralPath (Join-Path $runDirectory 'thread-ids.csv') -NoTypeInformation
$metadata = [ordered]@{Started=(Get-Date).ToString('o'); RequestedSeconds=$Seconds; ProcessName=$ProcessName; PID=$gameProcess.Id; ProcessStarted=$gameProcess.StartTime.ToString('o'); Profile='CPU'; RecordingSucceeded=$false; Notes='System-wide CPU/CSwitch/ReadyThread stack trace. Filter analysis to this PID and the actual racing interval. Keep raw ETL outside public repositories.'}
$startedHere = $false
try {
    & $wprCommand.Source -start CPU -filemode -recordtempto $runDirectory
    if ($LASTEXITCODE -ne 0) { throw 'WPR could not start CPU recording; no existing recording was cancelled.' }
    $startedHere = $true
    Write-Host "CPU stacks recording for $Seconds seconds. Keep the same racing scene: $runDirectory"
    Start-Sleep -Seconds $Seconds
} finally {
    if ($startedHere) {
        & $wprCommand.Source -stop (Join-Path $runDirectory 'cpu-stacks.etl') 'UEVR game render-thread CPU bottleneck' -skipPdbGen
        $metadata.RecordingSucceeded = $LASTEXITCODE -eq 0
        if (-not $metadata.RecordingSucceeded) { Write-Warning 'WPR stop failed. Inspect WPR status; temporary trace data may still be available.' }
    }
    $metadata['Finished'] = (Get-Date).ToString('o')
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDirectory 'run.json') -Encoding UTF8
    if (Test-Path -LiteralPath $profileLog) { Copy-Item -LiteralPath $profileLog -Destination (Join-Path $runDirectory 'uevr.log') }
}
if (-not $metadata.RecordingSucceeded) { throw 'CPU stack recording did not complete successfully.' }
Write-Host "CPU stack trace saved: $runDirectory"
