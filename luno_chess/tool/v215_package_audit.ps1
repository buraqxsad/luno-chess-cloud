param(
  [Parameter(Mandatory = $true)][string[]]$Packages,
  [string]$Output = 'qa/v215/package-analysis.json',
  [string]$Inventory = 'qa/v215/assets/inventory.json'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot 'v217_android_archive_policy.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$inventoryPath = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Inventory)) { $Inventory } else { Join-Path $root $Inventory }))
if (-not $inventoryPath.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Inventory must remain inside the project.'
}
$inventoryData = Get-Content -Raw -LiteralPath $inventoryPath | ConvertFrom-Json
$outputPath = [IO.Path]::GetFullPath((Join-Path $root $Output))
if (-not $outputPath.StartsWith((Join-Path $root 'qa') + [IO.Path]::DirectorySeparatorChar)) {
  throw 'Analysis output must remain inside workspace qa.'
}
$records = foreach ($package in $Packages) {
  $path = [IO.Path]::GetFullPath((Join-Path $root $package))
  if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar)) {
    throw 'Only workspace packages may be inspected.'
  }
  $archive = [IO.Compression.ZipFile]::OpenRead($path)
  try {
    $undeclared = @($inventoryData.undeclared.path)
    $expected = @($inventoryData.entries | Where-Object { $_.path -notin $undeclared })
    if ($expected.Count -lt 1 -or $expected.Count -ne $inventoryData.declaredAssetFiles) {
      throw 'Expected asset inventory is incomplete or inconsistent.'
    }
    $missing = @()
    $changed = @()
    $verified = 0
    $prefix = if ($package.EndsWith('.aab')) { 'base/assets/flutter_assets/' } else { 'assets/flutter_assets/' }
    foreach ($asset in $expected) {
      $entry = $archive.GetEntry($prefix + $asset.path)
      if ($null -eq $entry) { $missing += $asset.path; continue }
      $stream = $entry.Open()
      $hasher = [Security.Cryptography.SHA256]::Create()
      try { $hash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
      finally { $hasher.Dispose(); $stream.Dispose() }
      if ($hash -ne $asset.sha256) { $changed += $asset.path } else { $verified++ }
    }
    $references = @('assets/luno-chess.html', 'assets/native_art.zip') | Where-Object { $null -ne $archive.GetEntry($prefix + $_) }
    $forbiddenEntries = @($archive.Entries | Where-Object { Test-LunoExcludedPackagePath $_.FullName })
    $credentialContentCount = 0
    foreach ($candidate in $archive.Entries | Where-Object { $_.FullName -match '\.(json|properties|yaml|yml|txt)$' }) {
      $candidateStream = $candidate.Open()
      try {
        try { Assert-LunoNoPrivateMaterial $candidateStream }
        catch { $credentialContentCount++ }
      } finally { $candidateStream.Dispose() }
    }
    $runtimeMissing = @('AssetManifest.bin', 'FontManifest.json', 'fonts/MaterialIcons-Regular.otf') | Where-Object {
      $entry = $archive.GetEntry($prefix + $_)
      $null -eq $entry -or $entry.Length -eq 0
    }
    $fontFamilies = @()
    $fontEntry = $archive.GetEntry($prefix + 'FontManifest.json')
    if ($null -ne $fontEntry) {
      $fontStream = $fontEntry.Open()
      $reader = [IO.StreamReader]::new($fontStream)
      try { $fontFamilies = @(($reader.ReadToEnd() | ConvertFrom-Json).family) }
      finally { $reader.Dispose(); $fontStream.Dispose() }
    }
    $missingFamilies = @('Nunito', 'Cinzel', 'CinzelTurkish', 'Spectral', 'SpectralTurkish') | Where-Object { $_ -notin $fontFamilies }
    $entries = @($archive.Entries | Where-Object { $_.Name -ne '' } | ForEach-Object {
      $category = if ($_.FullName -match '(^|/)assets/flutter_assets/') { 'Flutter assets' }
      elseif ($_.FullName -match '/libapp\.so$') { 'Dart AOT' }
      elseif ($_.FullName -match '/libflutter\.so$') { 'Flutter engine' }
      elseif ($_.FullName -match '\.so$') { 'Other native' }
      elseif ($_.FullName -match '(^|/)(classes[0-9]*\.dex|dex/.*\.dex)$') { 'Android bytecode' }
      elseif ($_.FullName -match '(^|/)(res/|resources\.)') { 'Android resources' }
      else { 'Metadata and other' }
      [pscustomobject]@{ Path = $_.FullName; Category = $category; Bytes = $_.Length; CompressedBytes = $_.CompressedLength }
    })
    $categories = @($entries | Group-Object Category | ForEach-Object {
      [pscustomobject]@{
        Category = $_.Name
        Files = $_.Count
        Bytes = ($_.Group | Measure-Object Bytes -Sum).Sum
        CompressedBytes = ($_.Group | Measure-Object CompressedBytes -Sum).Sum
      }
    })
    $abis = @($entries.Path | ForEach-Object {
      if ($_ -match '(^|/)lib/([^/]+)/[^/]+\.so$') { $Matches[2] }
    } | Sort-Object -Unique)
    $runtimeAbis = @($entries.Path | ForEach-Object {
      if ($_ -match '(^|/)lib/([^/]+)/libflutter\.so$') { $Matches[2] }
    } | Sort-Object -Unique)
    $dartAbis = @($entries.Path | ForEach-Object {
      if ($_ -match '(^|/)lib/([^/]+)/libapp\.so$') { $Matches[2] }
    } | Sort-Object -Unique)
    [pscustomobject]@{
      Path = $package.Replace('\', '/')
      AnalysisOnly = $true
      PackageBytes = (Get-Item -LiteralPath $path).Length
      SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
      ABIs = $abis
      FlutterRuntimeABIs = $runtimeAbis
      DartABIs = $dartAbis
      NativeRuntimePass = ($runtimeAbis.Count -gt 0 -and ($runtimeAbis -join ',') -eq ($dartAbis -join ','))
      SecretExclusion = [pscustomobject]@{
        ForbiddenEntryCount = $forbiddenEntries.Count
        CredentialContentCandidateCount = $credentialContentCount
        Pass = ($forbiddenEntries.Count -eq 0 -and $credentialContentCount -eq 0)
      }
      RuntimeMetadata = [pscustomobject]@{
        Missing = @($runtimeMissing); FontFamilies = $fontFamilies
        MissingFontFamilies = @($missingFamilies)
        Pass = (@($runtimeMissing).Count -eq 0 -and @($missingFamilies).Count -eq 0)
      }
      AssetIntegrity = [pscustomobject]@{
        Expected = $expected.Count; Verified = $verified; Missing = @($missing)
        Changed = @($changed); ForbiddenReferences = @($references)
        Pass = ($missing.Count -eq 0 -and $changed.Count -eq 0 -and @($references).Count -eq 0)
      }
      Files = $entries.Count
      UncompressedBytes = ($entries | Measure-Object Bytes -Sum).Sum
      EntryCompressedBytes = ($entries | Measure-Object CompressedBytes -Sum).Sum
      Categories = $categories
      LargestEntries = @($entries | Sort-Object Bytes -Descending | Select-Object -First 15)
    }
  } finally {
    $archive.Dispose()
  }
}
[pscustomobject]@{
  RecordedAt = [DateTime]::UtcNow.ToString('o')
  InventoryPath = [IO.Path]::GetRelativePath($root, $inventoryPath).Replace('\', '/')
  InventorySHA256 = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash
  Method = 'ZIP entry compressed/uncompressed lengths and SHA-256. Not a Play download-size or runtime RAM measurement.'
  Packages = @($records)
} | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $outputPath -Encoding UTF8
$records | Select-Object Path, PackageBytes, ABIs, SHA256 | Format-List
if (@($records | Where-Object { -not $_.AssetIntegrity.Pass -or -not $_.NativeRuntimePass -or -not $_.RuntimeMetadata.Pass -or -not $_.SecretExclusion.Pass }).Count) {
  throw 'Package rejected: forbidden entries, assets, font/runtime metadata or Dart/Flutter ABI libraries are missing/changed. See analysis JSON.'
}
