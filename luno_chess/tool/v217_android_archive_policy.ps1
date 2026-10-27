function Test-LunoExcludedArchivePath([string]$Relative) {
    $path = $Relative.Replace('\', '/')
    return $path -match '(^|/)(\.git|\.gradle|\.kotlin|build|\.dart_tool|\.idea|\.cxx|ephemeral|failures|node_modules|\.pub-cache|\.pub|\.qa-appdata|\.qa-localappdata|release-credentials|credentials|backups)(/|$)' -or
        $path -match '(^|/)(local\.properties(?:\..*)?|key\.properties(?:\.(?!example$).*)?|\.env(?:\..*)?|.*(?:service.account|serviceAccount|credential|secret).*\.(json|pem|p12))$' -or
        $path -match '\.(jks|keystore|log|zip|apk|aab|p12|pfx|pem|key|iml|tmp)$'
}

function Test-LunoSourceArchivePath([string]$Relative) {
    $path = $Relative.Replace('\', '/')
    $top = $path.Split('/')[0]
    $allowed = $top -in @('lib', 'test', 'tool', 'android', 'ios', 'web', 'windows', 'linux', 'macos', 'assets') -or
        $path -in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.gitignore', 'README.md')
    return $allowed -and -not (Test-LunoExcludedArchivePath $path)
}

function Test-LunoExcludedPackagePath([string]$Relative) {
    $path = $Relative.Replace('\', '/')
    # AGP's namespace contains "build" but is not a source build-cache folder.
    # Its contents still pass the package credential scanner.
    if ($path -in @(
        'base/root/META-INF/com/android/build/gradle/app-metadata.properties',
        'META-INF/com/android/build/gradle/app-metadata.properties'
    )) { return $false }
    return Test-LunoExcludedArchivePath $path
}

function Assert-LunoNoPrivateMaterial([IO.Stream]$Stream) {
    # Check every extension, with overlap so a marker split across reads is detected.
    $reader = [IO.StreamReader]::new($Stream, [Text.Encoding]::UTF8, $true, 16384, $true)
    try {
        $buffer = [char[]]::new(16384)
        $tail = ''
        while (($count = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $text = $tail + [string]::new($buffer, 0, $count)
            if ($text -match '-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----|"private_key"\s*:|"type"\s*:\s*"service_account"' -or
                $text -match '(?im)^\s*(?:storePassword|keyPassword)\s*[:=]\s*(?![A-Za-z_]\w*\.(?:getProperty|get)\()(?!(?:CHANGE_ME|REPLACE\w*|YOUR_\w*|<[^>]+>)\s*$)\S+') {
                throw 'Private credential material found in an export candidate; export stopped. Values are never logged.'
            }
            $tail = $text.Substring([Math]::Max(0, $text.Length - 1024))
        }
    } finally { $reader.Dispose() }
}
