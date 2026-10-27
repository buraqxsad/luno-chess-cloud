param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..'),
    [string]$JavaCommand = 'java',
    [string[]]$HistoricalBundles = @()
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
. (Join-Path $PSScriptRoot 'v217_android_archive_policy.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$gradle = Get-Content -Raw -LiteralPath (Join-Path $root 'android/app/build.gradle.kts')
$pubspec = Get-Content -Raw -LiteralPath (Join-Path $root 'pubspec.yaml')
$manifest = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'android/app/src/main/AndroidManifest.xml'))
$androidNs = 'http://schemas.android.com/apk/res/android'
$firebase = Get-Content -Raw -LiteralPath (Join-Path $root 'android/app/google-services.json') | ConvertFrom-Json
$client = Get-Content -Raw -LiteralPath (Join-Path $root 'lib/services/luno_online_service.dart')
$appId = [regex]::Match($gradle, 'applicationId\s*=\s*"([^"]+)"').Groups[1].Value
$version = [regex]::Match($pubspec, '(?m)^version:\s*(\S+)').Groups[1].Value
$guardPresent = $gradle -match 'check\(signingReady\)' -and
    $gradle -match 'preReleaseBuild' -and $gradle -match 'dependsOn\(validateLunoReleaseSigning\)'
$noDebugFallback = $gradle -notmatch 'signingConfigs\.(?:getByName|findByName)\("debug"\)|signingConfigs\["debug"\]'
$releaseUploadOnly = $gradle -match 'if \(signingReady\) signingConfig = signingConfigs.getByName\("releaseUpload"\)'
$bundlePaths = @($HistoricalBundles | ForEach-Object {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $root $_ }))
})
$probeText = & $JavaCommand (Join-Path $PSScriptRoot 'v217_android_signing_probe.java') $root @bundlePaths
$probeExit = $LASTEXITCODE
$probe = $probeText | ConvertFrom-Json
$registeredHashes = @($firebase.client.oauth_client.android_info.certificate_hash | Where-Object { $_ })
$oauthCertificateMatch = $probe.localSigningUsable -and $probe.publicCertificateSha1 -in $registeredHashes
# Report only booleans; even public certificate digests are unnecessary in the handoff.
$probe.PSObject.Properties.Remove('publicCertificateSha1')
$archives = @(Get-ChildItem -LiteralPath $root -File -Filter '*.zip' | ForEach-Object {
    $zip = [IO.Compression.ZipFile]::OpenRead($_.FullName)
    try {
        $count = @($zip.Entries | Where-Object { Test-LunoExcludedArchivePath $_.FullName }).Count
        $signingCount = @($zip.Entries | Where-Object { $_.FullName -match '(^|[\\/])key\.properties($|\.)' -and $_.FullName -notmatch '\.example$' }).Count
        [pscustomobject]@{Path=$_.Name; ForbiddenEntryCount=$count; SigningConfigEntryCount=$signingCount; PathPolicyPass=($count -eq 0); ContentsNotInspected=$true}
    } finally { $zip.Dispose() }
})
$local = @{}
Get-Content -LiteralPath (Join-Path $root 'android/local.properties') | ForEach-Object {
    if ($_ -match '^([^#!:=]+)=(.*)$') { $local[$Matches[1].Trim()]=$Matches[2].Replace('\\','\').Replace('\:',':') }
}
$sdk = $local['sdk.dir']
$flutter = $local['flutter.sdk']
$extension = Join-Path $flutter 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
$defaults = Get-Content -Raw -LiteralPath $extension
$components = @{}
foreach ($name in @('compileSdkVersion','targetSdkVersion','minSdkVersion')) {
    $components[$name] = [int][regex]::Match($defaults, "val ${name}: Int = (\d+)").Groups[1].Value
}
$ndk = [regex]::Match($defaults, 'val ndkVersion: String = "([^"]+)"').Groups[1].Value
$permissions = @($manifest.manifest.'uses-permission' | ForEach-Object { $_.GetAttribute('name', $androidNs) })
$result = [pscustomobject]@{
    AnalysisOnly=$true
    ApplicationId=$appId
    Version=$version
    ManifestPermissions=$permissions
    MainActivityExported=($manifest.manifest.application.activity.GetAttribute('exported', $androidNs) -eq 'true')
    MainManifestExplicitlyDebuggable=($manifest.manifest.application.GetAttribute('debuggable', $androidNs) -eq 'true')
    Signing=[pscustomobject]@{StaticFailClosedGuard=$guardPresent; NoDebugFallback=$noDebugFallback; ReleaseUploadOnly=$releaseUploadOnly; ProbeExit=$probeExit; ReadOnlyProbe=$probe}
    Firebase=[pscustomobject]@{ProjectConfigured=!!$firebase.project_info.project_id; AndroidPackageMatches=($appId -in $firebase.client.client_info.android_client_info.package_name); LocalUploadCertificateHasOAuthClient=$oauthCertificateMatch; LiveConsoleVerified=$false}
    AppCheck=[pscustomobject]@{ReleasePlayIntegrityBranch=($client -match 'kDebugMode\s*\? const AndroidDebugProvider\(\)\s*: const AndroidPlayIntegrityProvider\(\)'); LiveAttestationVerified=$false}
    SDK=[pscustomobject]@{FlutterDefaults=$components; CompilePlatformPresent=(Test-Path -LiteralPath (Join-Path $sdk ("platforms/android-" + $components.compileSdkVersion))); NdkPresent=(Test-Path -LiteralPath (Join-Path $sdk ("ndk/" + $ndk))); FlutterBinaryPresent=(Test-Path -LiteralPath (Join-Path $flutter 'bin/flutter.bat')); AdbBinaryPresent=(Test-Path -LiteralPath (Join-Path $sdk 'platform-tools/adb.exe')); NoBuildOrInstallPerformed=$true}
    HistoricalRootArchives=$archives
    PathPolicyBlockedHistoricalRootArchiveCount=@($archives | Where-Object { -not $_.PathPolicyPass }).Count
    HistoricalArchivesWithSigningConfigCount=@($archives | Where-Object { $_.SigningConfigEntryCount -gt 0 }).Count
}
$result | ConvertTo-Json -Depth 10
if (-not $guardPresent -or -not $noDebugFallback -or -not $releaseUploadOnly -or $probeExit -ne 0) { exit 1 }
if ($result.PathPolicyBlockedHistoricalRootArchiveCount) { exit 2 }
