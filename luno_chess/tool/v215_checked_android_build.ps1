param(
  [ValidateSet('aab', 'apk')][string]$Target = 'aab',
  [string]$FlutterCommand = 'L:\.tools\flutter\bin\flutter.bat'
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = [IO.Path]::GetFullPath((Join-Path $root '.dart_tool\flutter_build'))
if (-not $cache.StartsWith($root + [IO.Path]::DirectorySeparatorChar)) {
  throw 'Generated Flutter cache escaped the project root.'
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml')) -or
    -not (Test-Path -LiteralPath (Join-Path $root 'qa/v215/assets/inventory.json'))) {
  throw 'Run inside the verified Luno project with a current asset inventory.'
}
Push-Location -LiteralPath $root
try {
  # C: and SUBST aliases can identify the same files with different output keys.
  # Remove only generated Flutter stamps; do not remove source or old packages.
  if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }
  $arguments = if ($Target -eq 'aab') {
    @('build', 'appbundle', '--release', '--target-platform', 'android-arm64', '--analyze-size', '--code-size-directory=qa/v215/size-analysis-checked')
  } else { @('build', 'apk', '--release', '--split-per-abi') }
  & $FlutterCommand @arguments *> "qa/v215-checked-$Target-build.txt"
  if ($LASTEXITCODE -ne 0) { throw "Flutter $Target build failed; inspect its log." }
  $packages = if ($Target -eq 'aab') { @('build/app/outputs/bundle/release/app-release.aab') }
  else {
    @('build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk',
      'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
      'build/app/outputs/flutter-apk/app-x86_64-release.apk')
  }
  & (Join-Path $PSScriptRoot 'v215_package_audit.ps1') -Packages $packages -Output "qa/v215/checked-$Target-analysis.json"
} finally { Pop-Location }
