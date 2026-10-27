$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('luno-v217-package-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$passed = 0
$failed = 0

function New-Fixture {
    $root = Join-Path $sandbox ([guid]::NewGuid().ToString())
    foreach ($dir in @('tool', 'qa/v215/assets', 'qa/v217/assets')) {
        [IO.Directory]::CreateDirectory((Join-Path $root $dir)) | Out-Null
    }
    foreach ($name in @('v215_package_audit.ps1', 'v217_android_archive_policy.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $root ('tool/' + $name))
    }
    $data = [Text.Encoding]::UTF8.GetBytes('current asset')
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($data))
    $inventory = @{declaredAssetFiles=1; undeclared=@(); entries=@(@{path='assets/fixture.txt'; sha256=$hash})} | ConvertTo-Json -Depth 5
    foreach ($version in @('v215', 'v217')) {
        [IO.File]::WriteAllText((Join-Path $root "qa/$version/assets/inventory.json"), $inventory)
    }
    $prefix = 'base/assets/flutter_assets/'
    $entries = @{}
    $entries[$prefix + 'assets/fixture.txt'] = 'current asset'
    $entries[$prefix + 'AssetManifest.bin'] = 'synthetic manifest'
    $entries[$prefix + 'fonts/MaterialIcons-Regular.otf'] = 'synthetic font'
    $entries[$prefix + 'FontManifest.json'] = @('Nunito','Cinzel','CinzelTurkish','Spectral','SpectralTurkish') |
        ForEach-Object { @{family=$_; fonts=@()} } | ConvertTo-Json -Depth 4
    foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
        $entries["base/lib/$abi/libflutter.so"] = 'synthetic runtime'
        $entries["base/lib/$abi/libapp.so"] = 'synthetic AOT'
    }
    return @{root=$root; entries=$entries}
}

function Write-Package($Fixture) {
    $path = Join-Path $Fixture.root 'qa/v217/fixture.aab'
    $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Fixture.entries.Keys) {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($name).Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write($Fixture.entries[$name]) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Invoke-Audit($Fixture, [switch]$Historical) {
    Write-Package $Fixture
    $args = @{Packages=@('qa/v217/fixture.aab'); Output='qa/v217/result.json'}
    if (-not $Historical) { $args.Inventory = 'qa/v217/assets/inventory.json' }
    & (Join-Path $Fixture.root 'tool/v215_package_audit.ps1') @args | Out-Null
}

function Assert-Rejected($Fixture) {
    $rejected = $false
    try { Invoke-Audit $Fixture } catch { $rejected = $true }
    if (-not $rejected -or -not (Test-Path -LiteralPath (Join-Path $Fixture.root 'qa/v217/result.json'))) {
        throw 'Package rejection was not reached.'
    }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passed++; Write-Output "PASS $Name" }
    catch { $script:failed++; Write-Output "FAIL $Name" }
}

try {
    Test-Case 'Historical default inventory remains supported' {
        Invoke-Audit (New-Fixture) -Historical
    }
    Test-Case 'Explicit current inventory overrides stale historical inventory' {
        $f = New-Fixture
        [IO.File]::WriteAllText((Join-Path $f.root 'qa/v215/assets/inventory.json'), '{}')
        Invoke-Audit $f
        $report = Get-Content -Raw -LiteralPath (Join-Path $f.root 'qa/v217/result.json') | ConvertFrom-Json
        if ($report.InventoryPath -ne 'qa/v217/assets/inventory.json' -or $report.Packages[0].ABIs.Count -ne 3) {
            throw 'Wrong inventory or ABI report.'
        }
    }
    Test-Case 'Secret ZIP entry is rejected even when runtime/assets match' {
        $f = New-Fixture
        $f.entries['base/assets/key.properties'] = ''
        Assert-Rejected $f
    }
    Test-Case 'Generated AGP metadata namespace is not a source cache' {
        $f = New-Fixture
        $f.entries['base/root/META-INF/com/android/build/gradle/app-metadata.properties'] = 'appMetadataVersion=1.1'
        Invoke-Audit $f
    }
    Test-Case 'AGP metadata exception cannot bypass credential scanning' {
        $f = New-Fixture
        $f.entries['base/root/META-INF/com/android/build/gradle/app-metadata.properties'] = 'storePassword=synthetic-test-only'
        Assert-Rejected $f
    }
    Test-Case 'Changed current asset hash is rejected' {
        $f = New-Fixture
        $f.entries['base/assets/flutter_assets/assets/fixture.txt'] = 'stale asset'
        Assert-Rejected $f
    }
    Test-Case 'Credential-shaped JSON in an innocuous ZIP entry is rejected' {
        $f = New-Fixture
        $f.entries['base/assets/innocent.json'] = '{"private_' + 'key":"not-a-key"}'
        Assert-Rejected $f
    }
    Test-Case 'Empty Flutter runtime manifest is rejected' {
        $f = New-Fixture
        $f.entries['base/assets/flutter_assets/AssetManifest.bin'] = ''
        Assert-Rejected $f
    }
    Test-Case 'Missing Flutter runtime manifest is rejected' {
        $f = New-Fixture
        $f.entries.Remove('base/assets/flutter_assets/AssetManifest.bin')
        Assert-Rejected $f
    }
    Test-Case 'Missing required font family is rejected' {
        $f = New-Fixture
        $f.entries['base/assets/flutter_assets/FontManifest.json'] = '[]'
        Assert-Rejected $f
    }
    Test-Case 'Mismatched Dart/Flutter ABI libraries are rejected' {
        $f = New-Fixture
        $f.entries.Remove('base/lib/x86_64/libapp.so')
        Assert-Rejected $f
    }
    Test-Case 'Inventory outside project is rejected' {
        $f = New-Fixture
        Write-Package $f
        $outside = Join-Path $sandbox 'inventory.json'
        Copy-Item -LiteralPath (Join-Path $f.root 'qa/v217/assets/inventory.json') -Destination $outside
        $rejected = $false
        try {
            & (Join-Path $f.root 'tool/v215_package_audit.ps1') -Packages @('qa/v217/fixture.aab') -Inventory $outside -Output 'qa/v217/result.json' | Out-Null
        } catch { $rejected = $_.Exception.Message -eq 'Inventory must remain inside the project.' }
        if (-not $rejected) { throw 'Escaping inventory accepted.' }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('luno-v217-package-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Output "Package regression tests: $passed passed, $failed failed. Synthetic ZIPs only; no Android build performed."
if ($failed) { exit 1 }
exit 0
