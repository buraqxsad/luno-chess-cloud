import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

String _section(String source, String start, String end) {
  final first = source.indexOf(start);
  final last = source.indexOf(end, first < 0 ? 0 : first);
  if (first < 0 || last <= first) {
    throw StateError('Expected source section was not found');
  }
  return source.substring(first, last);
}

void main() {
  test('Android launcher and Kotlin activity retain the native entry contract',
      () {
    final manifest = _source('android/app/src/main/AndroidManifest.xml');
    final activity = _source(
      'android/app/src/main/kotlin/com/luno/chess/MainActivity.kt',
    );
    expect(manifest.contains('android:name="com.luno.chess.MainActivity"'),
        isTrue);
    expect(manifest.contains('android:name="flutterEmbedding"'), isTrue);
    expect(activity.contains('package com.luno.chess'), isTrue);
    expect(activity.contains('class MainActivity : FlutterActivity()'), isTrue);
    expect(activity.contains('super.configureFlutterEngine(flutterEngine)'),
        isTrue);
  });

  test('Android source manifests do not enable debug or cleartext networking',
      () {
    for (final variant in ['main', 'debug', 'profile']) {
      final manifest = _source(
        'android/app/src/$variant/AndroidManifest.xml',
      );
      expect(
        RegExp(r'android:usesCleartextTraffic\s*=\s*["\x27]true["\x27]')
            .hasMatch(manifest),
        isFalse,
        reason: '$variant manifest must not explicitly enable cleartext',
      );
      expect(
        RegExp(r'android:debuggable\s*=\s*["\x27]true["\x27]')
            .hasMatch(manifest),
        isFalse,
        reason: '$variant source manifest must not force debuggable=true',
      );
      final permissions = RegExp(
        r'<uses-permission\b[^>]*android:name\s*=\s*"([^"]+)"',
      ).allMatches(manifest).map((match) => match.group(1)).toList();
      expect(permissions, ['android.permission.INTERNET'], reason: variant);
    }
  });

  test('production native API base is HTTPS without embedded credentials', () {
    final service = _source('lib/services/luno_online_service.dart');
    final match = RegExp(
      r"static const apiBase\s*=\s*'([^']+)';",
    ).firstMatch(service);
    expect(match != null, isTrue);
    final uri = Uri.parse(match!.group(1)!);
    expect(uri.scheme, 'https');
    expect(uri.hasAuthority, isTrue);
    expect(uri.userInfo.isEmpty, isTrue);
    expect(service.contains('useAuthEmulator('), isFalse);
    expect(service.contains('useDatabaseEmulator('), isFalse);
  });

  test('native Firebase startup activates App Check before remote bootstrap',
      () {
    final service = _source('lib/services/luno_online_service.dart');
    final boot = _section(
      service,
      'Future<void> _startInternal()',
      'Future<void> retry()',
    );
    final initialize = boot.indexOf('Firebase.initializeApp()');
    final attest = boot.indexOf('await _activateAppCheck()');
    final profile = boot.indexOf('await _ensureRemoteProfile()');
    expect(initialize >= 0, isTrue);
    expect(attest > initialize, isTrue);
    expect(profile > attest, isTrue);

    final activation = _section(
      service,
      'Future<void> _activateAppCheck()',
      'Future<String?> _appCheckToken()',
    );
    expect(
      RegExp(
        r'kDebugMode\s*\?\s*const AndroidDebugProvider\(\)\s*'
        r':\s*const AndroidPlayIntegrityProvider\(\)',
      ).hasMatch(activation),
      isTrue,
    );
  });

  test('first frame stays ahead of local preference loads and Firebase work',
      () {
    final main = _source('lib/main.dart');
    final run = main.indexOf('runApp(const LunoApp())');
    expect(run >= 0, isTrue);
    expect(main.indexOf('unawaited(GameStore.instance.load())') > run, isTrue);
    expect(main.indexOf('unawaited(LunoSettings.instance.load())') > run,
        isTrue);
    expect(main.substring(0, run).contains('Firebase.initializeApp('), isFalse);
    expect(main.contains('FlutterError.onError = handlers.framework'), isTrue);
    expect(main.contains('PlatformDispatcher.instance.onError = '
        'handlers.asynchronous'), isTrue);
  });
}
