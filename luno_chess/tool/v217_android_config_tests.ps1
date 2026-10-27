$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gradle = Get-Content -Raw -LiteralPath (Join-Path $root 'android/app/build.gradle.kts')
$pubspec = Get-Content -Raw -LiteralPath (Join-Path $root 'pubspec.yaml')
$manifest = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'android/app/src/main/AndroidManifest.xml'))
$androidNs = 'http://schemas.android.com/apk/res/android'
$passed = 0
$failed = 0
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { if (-not (& $Body)) { throw 'Static assertion failed.' }; $script:passed++; Write-Output "PASS $Name" }
    catch { $script:failed++; Write-Output "FAIL $Name" }
}
Test-Case 'Release contains no debug signing assignment' {
    $gradle -notmatch 'signingConfigs\.(?:getByName|findByName)\("debug"\)|signingConfigs\["debug"\]'
}
Test-Case 'Normal release prebuild requires explicit fail-closed validator' {
    $gradle -match 'check\(signingReady\)' -and $gradle -match 'preReleaseBuild' -and
        $gradle -match 'dependsOn\(validateLunoReleaseSigning\)'
}
Test-Case 'Readiness requires all properties and an existing local keystore' {
    $gradle -match 'releaseSigningKeys\.all' -and $gradle -match 'releaseStoreFile\?\.isFile == true' -and
        $gradle -match 'signingPropertiesReadable && keystorePropertiesFile\.exists\(\)'
}
Test-Case 'Release uses only the local upload signing config' {
    $gradle -match 'if \(signingReady\) signingConfig = signingConfigs.getByName\("releaseUpload"\)'
}
Test-Case 'Application id and namespace remain stable' {
    $gradle -match 'applicationId = "com.luno.chess"' -and $gradle -match 'namespace = "com.luno.chess"'
}
Test-Case 'Version remains unchanged at 1.6.3+17' { $pubspec -match '(?m)^version: 1\.6\.3\+17\s*$' }
Test-Case 'Main manifest has Internet only and no explicit debug/cleartext flag' {
    $permissions = @($manifest.manifest.'uses-permission' | ForEach-Object { $_.GetAttribute('name', $androidNs) })
    $permissions.Count -eq 1 -and $permissions[0] -eq 'android.permission.INTERNET' -and
        $manifest.manifest.application.GetAttribute('debuggable', $androidNs) -ne 'true' -and
        $manifest.manifest.application.GetAttribute('usesCleartextTraffic', $androidNs) -ne 'true'
}
Test-Case 'Missing signing configuration is safely reported by read-only Java probe' {
    $missingRoot = Join-Path ([IO.Path]::GetTempPath()) ('luno-v217-missing-' + [guid]::NewGuid())
    $output = & java (Join-Path $PSScriptRoot 'v217_android_signing_probe.java') $missingRoot
    $code = $LASTEXITCODE
    $probe = $output | ConvertFrom-Json
    $code -eq 1 -and $probe.localSigningUsable -eq $false -and $probe.error -eq 'Local signing probe failed; values and exception details withheld.'
}
Write-Output "Android static config tests: $passed passed, $failed failed. Gradle was not executed."
if ($failed) { exit 1 }
exit 0
