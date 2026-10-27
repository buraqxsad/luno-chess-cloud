param([string]$Destination = 'qa/source-audit/luno-flutter-source-clean.zip')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'v217_android_archive_policy.ps1')
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Output = [IO.Path]::GetFullPath((Join-Path $Root $Destination))
if (-not $Output.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source export destination must stay inside this project.'
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Test-LunoSourceExportPath([string]$Relative) {
    $Path = $Relative.Replace('\', '/')
    if ($Path -match '(^|/)keystore\.properties(?:\.(?!example$).*)?$' -or
        $Path -match '\.(jks|keystore|p12|pfx)(?:\..*)?$') { return $false }
    return Test-LunoSourceArchivePath $Path
}
function Get-SourceFiles([string]$Directory) {
    foreach ($Item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $Relative = [IO.Path]::GetRelativePath($Root, $Item.FullName).Replace('\', '/')
        if ($Item.PSIsContainer) {
            if (Test-LunoSourceExportPath $Relative) { Get-SourceFiles $Item.FullName }
        } elseif (Test-LunoSourceExportPath $Relative) { $Item }
    }
}
$Files = @(Get-SourceFiles $Root | Sort-Object FullName)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output)) | Out-Null
$Temporary = $Output + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
try {
    $Stream = [IO.File]::Open($Temporary, [IO.FileMode]::CreateNew)
    $Archive = [IO.Compression.ZipArchive]::new($Stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($File in $Files) {
            $Name = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
            $Input = [IO.File]::Open($File.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                Assert-LunoNoPrivateMaterial $Input
                $Input.Position = 0
                $Entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
                $Entry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
                $Target = $Entry.Open()
                try { $Input.CopyTo($Target) } finally { $Target.Dispose() }
            } finally { $Input.Dispose() }
        }
    } finally { $Archive.Dispose(); $Stream.Dispose() }
    $Read = [IO.Compression.ZipFile]::OpenRead($Temporary)
    try {
        $Forbidden = @($Read.Entries | Where-Object { -not (Test-LunoSourceExportPath $_.FullName) })
        if ($Forbidden.Count -ne 0 -or $Read.Entries.Count -ne $Files.Count) {
            throw 'Forbidden or missing source-package entry found.'
        }
        $FileCount = $Read.Entries.Count
    } finally { $Read.Dispose() }
    [IO.File]::Move($Temporary, $Output, $true)
    $Report = Join-Path $Root 'qa/source-audit/package-check.json'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Report)) | Out-Null
    [PSCustomObject]@{ files = $FileCount; forbidden = 0; bytes = (Get-Item -LiteralPath $Output).Length; sha256 = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash } |
        ConvertTo-Json | Set-Content -LiteralPath $Report
} finally {
    if ([IO.File]::Exists($Temporary)) { [IO.File]::Delete($Temporary) }
}
Write-Output 'Clean deterministic source export created; credentials and local caches excluded.'
