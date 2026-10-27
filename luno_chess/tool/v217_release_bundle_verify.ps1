[CmdletBinding()]
param(
    [string]$Bundle,
    [switch]$ParentFinalBuildComplete,
    [switch]$SelfTest,
    [string]$Java = 'C:\Program Files\Microsoft\jdk-21.0.12.8-hotspot\bin\java.exe',
    [string]$ClasspathFile,
    [ValidateRange(1, 2100000000)][int]$ExpectedBuild = 17,
    [string[]]$AllowedPermission
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $ClasspathFile) {
    $ClasspathFile = Join-Path $root 'qa\v215\bundletool-resolved-classpath.txt'
}

try {
    if ($SelfTest) {
        if ($Bundle -or $ParentFinalBuildComplete -or $AllowedPermission) {
            throw 'SelfTest cannot be combined with final-bundle arguments.'
        }
    } elseif (-not $ParentFinalBuildComplete -or -not $Bundle) {
        throw 'Wait for the parent final rebuild to succeed, then pass -ParentFinalBuildComplete and -Bundle.'
    }
    if (-not (Test-Path -LiteralPath $Java -PathType Leaf)) { throw 'Java 21 executable unavailable.' }
    if (-not (Test-Path -LiteralPath $ClasspathFile -PathType Leaf)) { throw 'Local classpath list unavailable.' }
    $paths = @(Get-Content -LiteralPath $ClasspathFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($paths.Count -eq 0) { throw 'Local classpath list is empty.' }
    foreach ($path in $paths) {
        if (-not [IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
            [IO.Path]::GetExtension($path) -ne '.jar') { throw 'Local classpath has an unavailable JAR.' }
    }
    foreach ($artifact in @('bundletool-', 'aapt2-proto-', 'protobuf-java-', 'gson-')) {
        if (-not ($paths | Where-Object { [IO.Path]::GetFileName($_).StartsWith($artifact) })) {
            throw 'Local classpath is missing a required artifact.'
        }
    }
    $arguments = @('-Xmx256m', "-Dluno.expectedBuild=$ExpectedBuild", '--class-path', ($paths -join [IO.Path]::PathSeparator),
        (Join-Path $PSScriptRoot 'v217_release_bundle_verify.java'))
    if ($SelfTest) {
        $arguments += @('--self-test', $root)
        & $Java @arguments
        exit $LASTEXITCODE
    }

    if (-not [IO.Path]::IsPathRooted($Bundle)) { $Bundle = Join-Path $root $Bundle }
    $Bundle = [IO.Path]::GetFullPath($Bundle)
    if (-not (Test-Path -LiteralPath $Bundle -PathType Leaf)) { throw 'Requested AAB is unavailable.' }
    $arguments += @('--parent-final-build-complete', $root, $Bundle)
    if ($AllowedPermission) { $arguments += $AllowedPermission }
    # Deny writes/deletion for the entire Java read; never race an active build.
    $lock = [IO.File]::Open($Bundle, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        & $Java @arguments
        $status = $LASTEXITCODE
    } finally { $lock.Dispose() }
    exit $status
} catch {
    # Only wrapper-authored messages reach stderr. Never echo provider exception details.
    Write-Error 'Bundle helper prerequisite/coordination failed; no acceptance result. See bundle-helper.md.' -ErrorAction Continue
    exit 1
}
