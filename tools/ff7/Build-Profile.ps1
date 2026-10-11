param(
    [Parameter(Mandatory=$true)][string]$OriginalArchive,
    [Parameter(Mandatory=$true)][string]$OutputArchive
)
$ErrorActionPreference = 'Stop'
$repoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$profilePath = Join-Path $repoPath 'profiles/ff7remake_'
$manifest = Get-Content -LiteralPath (Join-Path $profilePath 'upstream-manifest.json') -Raw | ConvertFrom-Json
$outputPath = [IO.Path]::GetFullPath($OutputArchive)
if ($outputPath.StartsWith($repoPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime ZIP must be written outside the source repository.'
}
if (Test-Path -LiteralPath $outputPath) { throw 'Output already exists; choose a new filename.' }
if ((Get-FileHash -LiteralPath $OriginalArchive -Algorithm SHA256).Hash -ne $manifest.archiveSha256) {
    throw 'Original archive hash mismatch.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$original = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $OriginalArchive).Path)
$output = $null
try {
    $entry = $original.GetEntry('plugins/ff7remake_.dll')
    if ($null -eq $entry) { throw 'Original plugin is missing.' }
    $stream = $entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
    finally { $stream.Dispose(); $sha.Dispose() }
    if ($hash -ne $manifest.pluginSha256) { throw 'Original plugin hash mismatch.' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
    $output = [IO.Compression.ZipFile]::Open($outputPath, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($name in @('config.txt','cvars_data.txt','cvars_standard.txt')) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($output, (Join-Path $profilePath $name), $name) | Out-Null
    }
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($output, (Join-Path $profilePath 'upstream/revision.txt'), 'revision.txt') | Out-Null
    $destination = $output.CreateEntry('plugins/ff7remake_.dll')
    $inputStream = $entry.Open()
    $outputStream = $destination.Open()
    try { $inputStream.CopyTo($outputStream) }
    finally { $inputStream.Dispose(); $outputStream.Dispose() }
} finally {
    if ($null -ne $output) { $output.Dispose() }
    $original.Dispose()
}
Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
