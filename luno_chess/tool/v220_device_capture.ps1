[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [ValidatePattern('^[a-z0-9-]+$')][string]$Label = 'baseline',
    [string]$Adb = 'C:\Users\Casper\AppData\Local\Android\Sdk\platform-tools\adb.exe'
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $root ('qa\v220\device\' + $Label)
New-Item -ItemType Directory -Force -Path $output | Out-Null
if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw 'adb unavailable' }
$state = & $Adb -s $Serial get-state
if ($LASTEXITCODE -ne 0 -or "$state".Trim() -ne 'device') { throw 'Selected device unavailable' }

# Read-only diagnostic capture: no install, clear-data, settings or live requests.
$commands = [ordered]@{
    'android-version' = @('shell', 'getprop', 'ro.build.version.release')
    'android-sdk' = @('shell', 'getprop', 'ro.build.version.sdk')
    'model' = @('shell', 'getprop', 'ro.product.model')
    'page-size' = @('shell', 'getconf', 'PAGE_SIZE')
    'display' = @('shell', 'wm', 'size')
    'display-density' = @('shell', 'wm', 'density')
    'package' = @('shell', 'dumpsys', 'package', 'com.luno.chess')
    'frame-stats' = @('shell', 'dumpsys', 'gfxinfo', 'com.luno.chess', 'framestats')
    'memory' = @('shell', 'dumpsys', 'meminfo', 'com.luno.chess')
    'thermal' = @('shell', 'dumpsys', 'thermalservice')
    'battery' = @('shell', 'dumpsys', 'battery')
}
foreach ($entry in $commands.GetEnumerator()) {
    & $Adb -s $Serial @($entry.Value) *> (Join-Path $output ($entry.Key + '.txt'))
    if ($LASTEXITCODE -ne 0) { throw ('Device command failed: ' + $entry.Key) }
}
Write-Output ('Captured diagnostics: qa/v220/device/' + $Label)
Write-Output 'Measurements are device/session-specific; emulator values are not physical-device acceptance.'
