param([string]$Packager = (Join-Path $PSScriptRoot 'package_source.ps1'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('luno-v217-archive-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$passed = 0
$failed = 0

function New-Fixture {
    $root = Join-Path $sandbox ([guid]::NewGuid().ToString())
    foreach ($dir in @('tool', 'lib', 'assets', 'android/app', 'qa/source-audit')) {
        [IO.Directory]::CreateDirectory((Join-Path $root $dir)) | Out-Null
    }
    Copy-Item -LiteralPath $Packager -Destination (Join-Path $root 'tool/package_source.ps1')
    $policy = Join-Path (Split-Path $Packager) 'v217_android_archive_policy.ps1'
    if (Test-Path -LiteralPath $policy) {
        Copy-Item -LiteralPath $policy -Destination (Join-Path $root 'tool/v217_android_archive_policy.ps1')
    }
    [IO.File]::WriteAllText((Join-Path $root 'pubspec.yaml'), 'name: fixture')
    [IO.File]::WriteAllText((Join-Path $root 'lib/main.dart'), 'void main() {}')
    [IO.File]::WriteAllText((Join-Path $root 'assets/fixture.txt'), 'public fixture')
    [IO.File]::WriteAllText((Join-Path $root 'android/app/build.gradle.kts'), '// fixture')
    return $root
}

function Export-Fixture([string]$Root) {
    & (Join-Path $Root 'tool/package_source.ps1') -Destination 'qa/source-audit/source.zip' | Out-Null
}

function Get-Names([string]$Root) {
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $Root 'qa/source-audit/source.zip'))
    try { return @($zip.Entries.FullName) } finally { $zip.Dispose() }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passed++; Write-Output "PASS $Name" }
    catch { $script:failed++; Write-Output "FAIL $Name" }
}

try {
    Test-Case 'Windows paths retain source/assets with portable ZIP names' {
        $root = New-Fixture
        Export-Fixture $root
        $names = Get-Names $root
        foreach ($required in @('lib/main.dart', 'assets/fixture.txt', 'android/app/build.gradle.kts')) {
            if ($required -notin $names) { throw 'Required source file omitted.' }
        }
        if (@($names | Where-Object { $_.Contains('\') }).Count) { throw 'Nonportable ZIP name.' }
    }
    Test-Case 'Local config, inert key-name fixtures, caches and nested archives excluded' {
        $root = New-Fixture
        foreach ($relative in @('android/key.properties', 'android/key.properties.bak',
            'android/local.properties', 'android/upload.jks', 'android/upload.keystore',
            'android/identity.p12', 'android/identity.key', 'android/.env.production',
            'android/service-account.json', 'android/build/generated.txt',
            'android/.gradle/cache.txt', 'android/.qa-appdata/cache.txt',
            'assets/old.zip', 'assets/release-credentials/marker.txt')) {
            $path = Join-Path $root $relative
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
            [IO.File]::WriteAllText($path, '')
        }
        Export-Fixture $root
        $names = Get-Names $root
        if (@($names | Where-Object { $_ -match 'key\.properties|local\.properties|\.jks$|\.keystore$|\.p12$|\.key$|\.env|service-account|/build/|/\.gradle/|/\.qa-appdata/|old\.zip|release-credentials' }).Count) {
            throw 'Excluded fixture reached archive.'
        }
    }
    Test-Case 'Property-based signing source is not mistaken for a literal password' {
        $root = New-Fixture
        [IO.File]::WriteAllText((Join-Path $root 'android/app/build.gradle.kts'), 'storePassword = keystoreProperties.getProperty("storePassword")')
        [IO.File]::WriteAllText((Join-Path $root 'tool/probe.java'), 'keyPassword = properties.getProperty("keyPassword").toCharArray();')
        Export-Fixture $root
    }
    Test-Case 'Private material in an unexpected extension aborts atomically' {
        $root = New-Fixture
        $marker = '-----' + 'BEGIN PRIVATE KEY' + '-----'
        [IO.File]::WriteAllText((Join-Path $root 'assets/disguised.bin'), $marker)
        $rejected = $false
        try { Export-Fixture $root } catch { $rejected = $true }
        if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $root 'qa/source-audit/source.zip'))) {
            throw 'Export did not fail closed.'
        }
    }
    Test-Case 'Service-account JSON aborts without echoing its contents' {
        $root = New-Fixture
        $marker = '{"private_' + 'key":"not-a-key"}'
        [IO.File]::WriteAllText((Join-Path $root 'assets/innocent.json'), $marker)
        $rejected = $false
        try { Export-Fixture $root } catch { $rejected = $true }
        if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $root 'qa/source-audit/source.zip'))) {
            throw 'Export did not fail closed.'
        }
    }
    Test-Case 'Rejected export preserves a previous successful archive' {
        $root = New-Fixture
        Export-Fixture $root
        $path = Join-Path $root 'qa/source-audit/source.zip'
        $before = (Get-FileHash -LiteralPath $path).Hash
        [IO.File]::WriteAllText((Join-Path $root 'assets/innocent.json'), '{"private_' + 'key":"not-a-key"}')
        $rejected = $false
        try { Export-Fixture $root } catch { $rejected = $true }
        if (-not $rejected -or (Get-FileHash -LiteralPath $path).Hash -ne $before) {
            throw 'Prior archive changed.'
        }
    }
    Test-Case 'Destination outside the project is rejected' {
        $root = New-Fixture
        $rejected = $false
        try { & (Join-Path $root 'tool/package_source.ps1') -Destination '../outside.zip' | Out-Null }
        catch { $rejected = $true }
        if (-not $rejected) { throw 'Escaping destination accepted.' }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('luno-v217-archive-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Output "Archive regression tests: $passed passed, $failed failed. Inert fixtures only; no signing keys generated."
if ($failed) { exit 1 }
exit 0
