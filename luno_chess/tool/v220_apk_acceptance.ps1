[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [string]$Sdk = 'C:\Users\Casper\AppData\Local\Android\Sdk',
    [string]$ExpectedVersion = '1.6.3',
    [ValidateRange(1, 999)][int]$ExpectedBuild = 17,
    [switch]$SplitPerAbi
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$path = [IO.Path]::GetFullPath((Join-Path $root $Apk))
if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Expected a local workspace APK' }
$name = [IO.Path]::GetFileNameWithoutExtension($path)
$output = Join-Path $root ('qa\v220\artifacts\' + $name)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$buildTools = Join-Path $Sdk 'build-tools\36.1.0'
$analyzer = Join-Path $Sdk 'cmdline-tools\latest\bin\apkanalyzer.bat'
$objdump = Join-Path $Sdk 'ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-objdump.exe'
$readelf = Join-Path $Sdk 'ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
foreach ($tool in @($analyzer, $objdump, $readelf, (Join-Path $buildTools 'zipalign.exe'), (Join-Path $buildTools 'apksigner.bat'))) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'Android artifact inspection tool unavailable' }
}

& $analyzer manifest print $path *> (Join-Path $output 'manifest.xml')
if ($LASTEXITCODE -ne 0) { throw 'Actual APK manifest decoding failed' }
$manifest = [xml](Get-Content -Raw -LiteralPath (Join-Path $output 'manifest.xml'))
$ns = 'http://schemas.android.com/apk/res/android'
$app = $manifest.manifest.application
$permissions = @($manifest.manifest.'uses-permission' | ForEach-Object { $_.GetAttribute('name', $ns) })
$exported = @($app.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.GetAttribute('exported', $ns) -eq 'true' } | ForEach-Object {
    [pscustomobject]@{Type=$_.LocalName; Name=$_.GetAttribute('name', $ns); Permission=$_.GetAttribute('permission', $ns)}
})
& (Join-Path $buildTools 'apksigner.bat') verify --verbose --print-certs $path *> (Join-Path $output 'signature.txt')
$signaturePass = $LASTEXITCODE -eq 0
& (Join-Path $buildTools 'zipalign.exe') -c -P 16 -v 4 $path *> (Join-Path $output 'zipalign.txt')
$zipPass = $LASTEXITCODE -eq 0

$native = @()
$abis = @()
$archive = [IO.Compression.ZipFile]::OpenRead($path)
try {
    $abis = @($archive.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/[^/]+\.so$' } |
        ForEach-Object { ($_.FullName -split '/')[1] } | Sort-Object -Unique)
    foreach ($entry in $archive.Entries | Where-Object { $_.FullName -match '^lib/(arm64-v8a|x86_64)/[^/]+\.so$' }) {
        $destination = [IO.Path]::GetFullPath((Join-Path $output $entry.FullName))
        if (-not $destination.StartsWith($output + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Native library escaped audit directory' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
        $loadLines = @(& $objdump -p $destination | Select-String -Pattern '^\s*LOAD ' | ForEach-Object { $_.Line })
        if ($LASTEXITCODE -ne 0 -or $loadLines.Count -eq 0) { throw 'Native LOAD inspection failed' }
        $alignments = @($loadLines | ForEach-Object {
            if ($_ -notmatch 'align 2\*\*(\d+)') { throw 'Unknown LOAD alignment output' }
            [int]$Matches[1]
        })
        $relroLines = @(& $readelf -Wl $destination | Select-String -Pattern '^\s*GNU_RELRO ' | ForEach-Object { $_.Line })
        if ($LASTEXITCODE -ne 0) { throw 'Native RELRO inspection failed' }
        $relroPass = $true
        foreach ($line in $relroLines) {
            $columns = $line.Trim() -split '\s+'
            $end = [Convert]::ToUInt64($columns[2].Substring(2), 16) + [Convert]::ToUInt64($columns[5].Substring(2), 16)
            if ($end % 16384 -ne 0) { $relroPass = $false }
        }
        $native += [pscustomobject]@{
            Library=$entry.FullName; LoadAlignmentPowers=$alignments
            Load16KPass=(@($alignments | Where-Object { $_ -lt 14 }).Count -eq 0)
            Relro16KPass=$relroPass; LoadLines=$loadLines; RelroLines=$relroLines
        }
    }
    $firebaseProvider = $null -ne ($app.provider | Where-Object { $_.GetAttribute('name', $ns) -eq 'com.google.firebase.provider.FirebaseInitProvider' })
} finally { $archive.Dispose() }
$sdkNode = $manifest.manifest.'uses-sdk'
$expectedCode = $ExpectedBuild
if ($SplitPerAbi) {
    # Flutter's split APK outputs use ABI_VERSION * 1000 + the base build number.
    $abiCodes = @{'armeabi-v7a'=1; 'arm64-v8a'=2; 'x86_64'=4}
    if ($abis.Count -ne 1 -or -not $abiCodes.ContainsKey($abis[0])) { throw 'Unexpected split APK ABI' }
    $expectedCode += $abiCodes[$abis[0]] * 1000
}
$identityPass = $manifest.manifest.package -eq 'com.luno.chess' -and
    $manifest.manifest.GetAttribute('versionName', $ns) -eq $ExpectedVersion -and
    [int]$manifest.manifest.GetAttribute('versionCode', $ns) -eq $expectedCode
$securityPass = $app.GetAttribute('debuggable', $ns) -ne 'true' -and
    $app.GetAttribute('usesCleartextTraffic', $ns) -ne 'true' -and
    [int]$sdkNode.GetAttribute('targetSdkVersion', $ns) -ge 35
$nativePass = @($native | Where-Object { -not $_.Load16KPass -or -not $_.Relro16KPass }).Count -eq 0
$result = [pscustomobject]@{
    Artifact=$Apk; Bytes=(Get-Item -LiteralPath $path).Length
    SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Package=$manifest.manifest.package; Version=$manifest.manifest.GetAttribute('versionName', $ns)
    Build=[int]$manifest.manifest.GetAttribute('versionCode', $ns)
    BaseBuild=$ExpectedBuild; ExpectedAndroidVersionCode=$expectedCode; SplitPerAbi=[bool]$SplitPerAbi; ABIs=$abis
    MinSDK=[int]$sdkNode.GetAttribute('minSdkVersion', $ns)
    TargetSDK=[int]$sdkNode.GetAttribute('targetSdkVersion', $ns)
    Permissions=$permissions; ExportedComponents=$exported
    Debuggable=$app.GetAttribute('debuggable', $ns); Cleartext=$app.GetAttribute('usesCleartextTraffic', $ns)
    FirebaseInitProvider=$firebaseProvider; SignaturePass=$signaturePass
    Zip16KPass=$zipPass; NativeLibraries=$native
    Native16KPass=$nativePass
    IdentityPass=$identityPass; ManifestSecurityPass=$securityPass
    Pass=($identityPass -and $securityPass -and $signaturePass -and $zipPass -and $nativePass -and $firebaseProvider)
    Limits='Local artifact inspection only; no Play signing/attestation, installation, runtime or device thermal acceptance.'
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'acceptance.json') -Encoding UTF8
$result | Select-Object Artifact,Bytes,Package,Version,Build,MinSDK,TargetSDK,SignaturePass,Zip16KPass,Pass | Format-List
if (-not $result.Pass) { exit 1 }
