import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/services/app_release_identity.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

const _channel = MethodChannel('com.luno.chess/release_identity');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test(
    'installed Android build overrides source version without protocol drift',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            expect(call.method, 'getReleaseIdentity');
            return {'versionName': '1.6.3', 'buildNumber': 18};
          });
      Map<String, dynamic>? sent;
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        appReleaseIdentity: () => AppReleaseIdentity.fromPlatform(),
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await online.enqueueBattleV1();
      expect(sent!['client'], {
        'platform': 'android',
        'build': 18,
        'protocolVersion': battleV1Protocol,
      });
    },
  );

  test(
    'installed split APK versionCode is preserved without normalization',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (_) async {
            return {'versionName': '1.6.3', 'buildNumber': 2018};
          });
      final identity = await AppReleaseIdentity.fromPlatform();
      expect(identity.buildNumber, 2018);
      expect(identity.versionName, '1.6.3');
    },
  );

  for (final value in <Object?>[
    null,
    {},
    {'versionName': '1.6.3', 'buildNumber': '18'},
    {'versionName': '1.6.3', 'buildNumber': true},
    {'versionName': '1.6.3', 'buildNumber': 0},
    {'versionName': '1.6.3', 'buildNumber': -1},
    {'versionName': null, 'buildNumber': 18},
  ]) {
    test(
      'invalid installed metadata never falls back to build 17: $value',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (_) async => value);
        var calls = 0;
        final online = LunoOnlineService.forTesting(
          auth: TestAuth(),
          bootstrap: () async {},
          appCheck: () async => 'check',
          appReleaseIdentity: () => AppReleaseIdentity.fromPlatform(),
          client: MockClient((_) async {
            calls++;
            return http.Response('{"ok":true}', 200);
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        await expectLater(online.enqueueBattleV1(), throwsFormatException);
        expect(calls, 0);
      },
    );
  }

  test(
    'account switch during metadata lookup cannot dispatch as the next user',
    () async {
      final auth = TestAuth();
      final entered = Completer<void>();
      final identity = Completer<AppReleaseIdentity>();
      var calls = 0;
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {},
        appCheck: () async => 'check',
        appReleaseIdentity: () {
          entered.complete();
          return identity.future;
        },
        client: MockClient((_) async {
          calls++;
          return http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      final operation = online.enqueueBattleV1();
      await entered.future;
      auth.currentUser = TestUser('second');
      final assertion = expectLater(
        operation,
        throwsA(
          isA<BattleV1Rejection>().having(
            (error) => error.code,
            'code',
            'session-changed',
          ),
        ),
      );
      identity.complete(
        const AppReleaseIdentity(versionName: '1.6.3', buildNumber: 18),
      );
      await assertion;
      expect(calls, 0);
    },
  );
}
