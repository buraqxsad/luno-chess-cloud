param([string]$EvidenceDirectory = 'qa/source-audit', [switch]$SourceOnly)
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Resources = Join-Path $Root 'android/app/src/main/res'
$Android = 'http://schemas.android.com/apk/res/android'
function Assert-Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$Manifest = [xml](Get-Content -LiteralPath (Join-Path $Root 'android/app/src/main/AndroidManifest.xml') -Raw)
Assert-Check ($Manifest.manifest.application.GetAttribute('icon', $Android) -eq '@mipmap/ic_launcher') 'Launcher is not the branded mipmap resource.'
$Permissions = @($Manifest.manifest.'uses-permission' | ForEach-Object { $_.GetAttribute('name', $Android) })
Assert-Check ($Permissions.Count -eq 1 -and $Permissions[0] -eq 'android.permission.INTERNET') 'Unexpected production Android permission.'
foreach ($Api in @('v26', 'v33')) {
    $Icon = [xml](Get-Content -LiteralPath (Join-Path $Resources "mipmap-anydpi-$Api/ic_launcher.xml") -Raw)
    Assert-Check ($Icon.'adaptive-icon'.background.GetAttribute('drawable', $Android) -eq '@color/luno_launcher_background') 'Adaptive background mismatch.'
    Assert-Check ($Icon.'adaptive-icon'.foreground.GetAttribute('drawable', $Android) -eq '@drawable/luno_launcher_foreground') 'Adaptive foreground mismatch.'
    if ($Api -eq 'v33') { Assert-Check ($Icon.'adaptive-icon'.monochrome.GetAttribute('drawable', $Android) -eq '@drawable/luno_launcher_monochrome') 'Themed icon missing.' }
}
$Colors = [xml](Get-Content -LiteralPath (Join-Path $Resources 'values/colors.xml') -Raw)
foreach ($Name in @('luno_splash', 'luno_launcher_background')) {
    $Value = @($Colors.resources.color | Where-Object name -eq $Name)[0].InnerText
    Assert-Check ($Value -eq '#080F18') 'Startup background does not match the Flutter shell.'
}
foreach ($Folder in @('values','values-night','values-v31','values-night-v31')) {
    $Styles = [xml](Get-Content -LiteralPath (Join-Path $Resources "$Folder/styles.xml") -Raw)
    foreach ($Item in $Styles.SelectNodes('/resources/style/item')) {
        if ($Item.GetAttribute('name') -in @('android:statusBarColor','android:navigationBarColor','android:windowSplashScreenBackground')) {
            Assert-Check ($Item.InnerText -eq '@color/luno_splash') 'Native startup bar/background mismatch.'
        }
    }
    if ($Folder -like '*v31') {
        Assert-Check ($Styles.SelectSingleNode('/resources/style[@name="LaunchTheme"]/item[@name="android:windowSplashScreenAnimatedIcon"]').InnerText -eq '@drawable/luno_splash_v212') 'Android 12 branded splash missing.'
    }
}
foreach ($Folder in @('drawable','drawable-v21')) {
    $Splash = [xml](Get-Content -LiteralPath (Join-Path $Resources "$Folder/launch_background.xml") -Raw)
    Assert-Check (@($Splash.'layer-list'.item | Where-Object { $_.GetAttribute('drawable', $Android) -eq '@drawable/luno_pre31_splash' }).Count -eq 1) 'Pre-Android-12 branded splash missing.'
}
$Foreground = [xml](Get-Content -LiteralPath (Join-Path $Resources 'drawable/luno_launcher_foreground.xml') -Raw)
Assert-Check ($Foreground.'layer-list'.item.bitmap.GetAttribute('src', $Android) -eq '@drawable/luno_launcher_art') 'Adaptive foreground bitmap missing.'
if ($SourceOnly) {
    $OutputDirectory = [IO.Path]::GetFullPath((Join-Path $Root $EvidenceDirectory))
    Assert-Check ($OutputDirectory.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'Evidence output must stay inside this project.'
    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    @{ status = 'ANDROID SOURCE RESOURCE CHECKS PASSED'; generatedAt = [DateTime]::UtcNow.ToString('o'); permissions = $Permissions; startupColor = '#080F18'; adaptiveApi26 = $true; themedApi33 = $true; signingBuildVerifiedInThisRun = $false; physicalAndroidLaunchVerified = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'android-source-check.json')
    Write-Output 'Fresh Android source resource checks passed; no signing, binary or device claim.'
    return
}
$Archive = Get-Content -LiteralPath (Join-Path $Root 'qa/source-audit/package-check.json') -Raw | ConvertFrom-Json
Assert-Check ($Archive.forbidden -eq 0) 'Source package contains prohibited entries.'
$Debug = Get-Content -LiteralPath (Join-Path $Root 'qa/source-audit-debug-resources.txt') -Raw
$Missing = Get-Content -LiteralPath (Join-Path $Root 'qa/source-audit-release-missing-signing.txt') -Raw
$Present = Get-Content -LiteralPath (Join-Path $Root 'qa/source-audit-release-signing-present.txt') -Raw
Assert-Check ($Debug -match 'BUILD SUCCESSFUL') 'Debug resource build was not verified without release keys.'
Assert-Check ($Missing -match ':app:validateLunoReleaseSigning FAILED') 'Missing signing did not fail explicitly at the release task.'
Assert-Check ($Present -match 'BUILD SUCCESSFUL') 'Present signing was not validated.'
@{ status = 'ANDROID SOURCE RESOURCE AND SIGNING CHECKS PASSED'; permissions = $Permissions; startupColor = '#080F18'; adaptiveApi26 = $true; themedApi33 = $true; sourceArchiveForbiddenEntries = 0; debugResourcesWithoutReleaseSigning = $true; releaseWithoutSigningExpectedFailure = $true; presentSigningValidation = $true; physicalAndroidLaunchVerified = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'qa/source-audit/android-check.json')
Write-Output 'Android source resource, package hygiene and signing gates passed; no binary/device claim.'
