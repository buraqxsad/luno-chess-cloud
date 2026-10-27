import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

class _Provider extends Fake implements UserInfo {
  @override
  String get providerId => 'google.com';
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User? user;
}

class DeletionUser extends TestUser {
  DeletionUser(super.uid, {this.anonymous = true, this.reauthenticate});
  final bool anonymous;
  final Future<UserCredential> Function()? reauthenticate;
  int verifications = 0;
  @override
  bool get isAnonymous => anonymous;
  @override
  List<UserInfo> get providerData => anonymous ? [] : [_Provider()];
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    if (credential.providerId != 'google.com') throw StateError('Expected native Google credential');
    verifications++;
    return reauthenticate == null ? _Credential(this) : await reauthenticate!();
  }
}

class DeletionAuth extends TestAuth {
  int signouts = 0;
  bool failSignout = false;
  @override
  Future<void> signOut() async {
    signouts++;
    if (failSignout) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    currentUser = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scenario in [
    'guest',
    'google',
    'cancel-verification',
    'switch-verification',
    'invalid-response',
    'server-failure',
    'already-deleted',
    'resume',
  ]) {
    test('deletion flow handles $scenario', () async {
      final store = GameStore.createForTesting();
      final auth = DeletionAuth();
      late DeletionUser deletingUser;
      deletingUser = DeletionUser(
        'first',
        anonymous:
            ![
              'google',
              'cancel-verification',
              'switch-verification',
            ].contains(scenario),
        reauthenticate: () async {
          if (scenario == 'cancel-verification') {
            throw FirebaseAuthException(code: 'cancelled');
          }
          if (scenario == 'switch-verification') {
            auth.currentUser = DeletionUser('second');
          }
          return _Credential(deletingUser);
        },
      );
      auth.currentUser = deletingUser;
      var requests = 0;
      var initialFailure =
          scenario == 'already-deleted' || scenario == 'resume';
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient((request) async {
          requests++;
          if (initialFailure) {
            return http.Response(
              jsonEncode({
                'ok': false,
                'error':
                    scenario == 'resume'
                        ? 'account-deletion-in-progress'
                        : 'account-deleted',
              }),
              scenario == 'resume' ? 409 : 403,
            );
          }
          expect(request.url.path.endsWith('/deleteAccount'), isTrue);
          expect(jsonDecode(request.body), {'confirm': true});
          return http.Response(
            scenario == 'invalid-response'
                ? '{"ok":true,"deleted":false}'
                : scenario == 'server-failure'
                ? '{"ok":false,"error":"pending-settlement-missing"}'
                : '{"ok":true,"deleted":true}',
            scenario == 'server-failure' ? 409 : 200,
          );
        }),
        appCheck: () async => 'check',
      );
      addTearDown(() async {
        service.dispose();
        await store.flush();
        store.dispose();
      });
      await service.start();
      store.data.bio = 'private bio';
      await store.save();
      if (initialFailure) {
        await expectLater(
          service.getPlayerState(),
          throwsA(isA<LunoApiException>()),
        );
        initialFailure = false;
      }
      if ([
        'cancel-verification',
        'switch-verification',
        'invalid-response',
        'server-failure',
      ].contains(scenario)) {
        await expectLater(
          service.deleteAccount(confirmed: true),
          throwsA(anything),
        );
        expect(store.data.bio, 'private bio');
        expect(auth.signouts, 0);
        expect(
          requests,
          ['cancel-verification', 'switch-verification'].contains(scenario)
              ? 0
              : 1,
        );
      } else {
        expect(await service.deleteAccount(confirmed: true), 'first');
        expect(store.accountUid, isNull);
        expect(store.data.bio, isNot('private bio'));
        expect(auth.signouts, 1);
        expect(service.user, isNull);
        expect(requests, scenario == 'resume' ? 2 : 1);
      }
      expect(deletingUser.verifications, deletingUser.anonymous ? 0 : 1);
    });
  }

  test(
    'confirmation is mandatory and concurrent deletion cannot duplicate dispatch',
    () async {
      final auth = DeletionAuth()..currentUser = DeletionUser('first');
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: MockClient((_) async {
          requests++;
          entered.complete();
          return response.future;
        }),
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(
        service.deleteAccount(confirmed: false),
        throwsA(isA<LunoApiException>()),
      );
      expect(requests, 0);
      final first = service.deleteAccount(confirmed: true);
      await entered.future;
      await expectLater(
        service.deleteAccount(confirmed: true),
        throwsA(isA<LunoApiException>()),
      );
      await expectLater(
        service.getPlayerState(),
        throwsA(isA<LunoApiException>()),
      );
      expect(requests, 1);
      response.complete(http.Response('{"ok":true,"deleted":true}', 200));
      expect(await first, 'first');
      expect(auth.signouts, 1);
    },
  );

  test(
    'failed signout leaves deleted account blocked and can finish without redispatch',
    () async {
      final store = GameStore.createForTesting();
      final auth =
          DeletionAuth()
            ..currentUser = DeletionUser('first')
            ..failSignout = true;
      var requests = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient((_) async {
          requests++;
          return http.Response('{"ok":true,"deleted":true}', 200);
        }),
        appCheck: () async => 'check',
      );
      addTearDown(() async {
        service.dispose();
        await store.flush();
        store.dispose();
      });
      await service.start();
      await expectLater(
        service.deleteAccount(confirmed: true),
        throwsA(
          isA<LunoApiException>().having(
            (error) => error.code,
            'code',
            'account-deletion-signout-pending',
          ),
        ),
      );
      expect(service.accountFailure?.code, 'account-deleted');
      expect(service.ready, isFalse);
      expect(store.accountUid, isNull);
      await expectLater(
        service.getPlayerState(),
        throwsA(isA<LunoApiException>()),
      );
      expect(requests, 1);
      auth.failSignout = false;
      expect(await service.deleteAccount(confirmed: true), 'first');
      expect(requests, 1);
      expect(auth.signouts, 2);
      expect(service.user, isNull);
    },
  );

  test(
    'reopening with a deleted UID clears the expired session before onboarding',
    () async {
      final store = GameStore.createForTesting();
      await store.bindAccount('first');
      await store.eraseLocalAccount('first');
      final auth = DeletionAuth()..currentUser = DeletionUser('first');
      var bootstrapCalls = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {
          bootstrapCalls++;
        },
        auth: auth,
        playerStore: store,
      );
      addTearDown(() async {
        service.dispose();
        await store.flush();
        store.dispose();
      });
      await service.start();
      expect(bootstrapCalls, 0);
      expect(auth.signouts, 1);
      expect(service.user, isNull);
      expect(service.accountFailure, isNull);
      expect(store.accountUid, isNull);
    },
  );

  for (final english in [false, true]) {
    testWidgets(
      'settings deletion can be cancelled in ${english ? 'en' : 'tr'}',
      (tester) async {
        final auth = DeletionAuth()..currentUser = DeletionUser('first');
        var requests = 0;
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          client: MockClient((_) async {
            requests++;
            return http.Response('{"ok":true,"deleted":true}', 200);
          }),
          appCheck: () async => 'check',
        );
        addTearDown(service.dispose);
        await service.start();
        final settings = LunoSettings(
          deviceLocale: Locale(english ? 'en' : 'tr'),
        );
        await tester.runAsync(settings.load);
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: SettingsScreen(online: service, settings: settings),
          ),
        );
        await tester.pumpAndSettle();
        final delete = find.text(english ? 'Delete account' : 'Hesabımı sil');
        await tester.ensureVisible(delete);
        await tester.pumpAndSettle();
        await tester.tap(delete);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text(english ? 'Delete account?' : 'Hesap silinsin mi?'),
          findsOneWidget,
        );
        await tester.tap(find.text(english ? 'Cancel' : 'Vazgeç'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(requests, 0);
        expect(auth.signouts, 0);
      },
    );
  }

  testWidgets(
    'settings confirms once and signs out only after server acknowledgement',
    (tester) async {
      final auth = DeletionAuth()..currentUser = DeletionUser('first');
      final response = Completer<http.Response>();
      var requests = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: MockClient((_) async {
          requests++;
          return response.future;
        }),
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();
      final settings = LunoSettings(deviceLocale: const Locale('tr'));
      await tester.runAsync(settings.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: SettingsScreen(online: service, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      final delete = find.text('Hesabımı sil');
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Kalıcı olarak sil'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests, 1);
      expect(auth.signouts, 0);
      final tile = tester.widget<ListTile>(
        find.ancestor(of: delete, matching: find.byType(ListTile)),
      );
      expect(tile.onTap, isNull);
      response.complete(http.Response('{"ok":true,"deleted":true}', 200));
      await tester.pumpAndSettle();
      expect(auth.signouts, 1);
      expect(find.text('Hesabın silindi.'), findsOneWidget);
    },
  );

  testWidgets('deletion confirmation closes after an account change', (
    tester,
  ) async {
    final auth = DeletionAuth()..currentUser = DeletionUser('first');
    final changes = StreamController<User?>.broadcast(sync: true);
    var requests = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth,
      authChanges: changes.stream,
      client: MockClient((_) async {
        requests++;
        return http.Response('{"ok":true}', 200);
      }),
      appCheck: () async => 'check',
    );
    addTearDown(() async {
      service.dispose();
      await changes.close();
    });
    await service.start();
    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    await tester.runAsync(settings.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: SettingsScreen(online: service, settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    final delete = find.text('Hesabımı sil');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pump(const Duration(milliseconds: 500));
    auth.currentUser = DeletionUser('second');
    changes.add(auth.currentUser);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests, 0);
    expect(auth.signouts, 0);
  });
}
