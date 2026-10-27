import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

class _GoogleProvider extends Fake implements UserInfo {
  @override
  String get providerId => 'google.com';
}

class _LinkCredential extends Fake implements UserCredential {
  _LinkCredential(this.user);
  @override
  final User? user;
}

class GoogleLinkUser extends TestUser {
  GoogleLinkUser(super.uid);
  bool linked = false;
  int links = 0;
  int refreshedTokens = 0;
  Future<void> Function()? onLink;
  @override
  List<UserInfo> get providerData => linked ? [_GoogleProvider()] : [];
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    if (credential.providerId != 'google.com') throw StateError('Expected native Google credential');
    links++;
    await onLink?.call();
    linked = true;
    return _LinkCredential(this);
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) refreshedTokens++;
    return 'token';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final attempt = 'a' * 32;

  for (final switchAccount in [false, true]) {
    testWidgets(
      'settings link notice respects account switch: $switchAccount',
      (tester) async {
        final auth = TestAuth();
        final player = GoogleLinkUser('first');
        auth.currentUser = player;
        final picker = Completer<void>();
        player.onLink = () => picker.future;
        final changes = StreamController<User?>.broadcast(sync: true);
        var completions = 0;
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          authChanges: changes.stream,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/prepareGoogleLink')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'alreadyLinked': false,
                  'attemptId': attempt,
                }),
                200,
              );
            }
            completions++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'linked': true,
                'uid': 'first',
                'state': {'gold': 123},
              }),
              200,
            );
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
        final l10n = LunoLocalizations(const Locale('tr'));
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: SettingsScreen(online: service, settings: settings),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.text(l10n.googleLink);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump(const Duration(milliseconds: 500));
        expect(player.links, 1);
        if (switchAccount) {
          auth.currentUser = GoogleLinkUser('second');
          changes.add(auth.currentUser);
          await tester.pump(const Duration(milliseconds: 100));
        }
        picker.complete();
        await tester.pumpAndSettle();
        expect(completions, switchAccount ? 0 : 1);
        expect(
          find.byType(SnackBar),
          switchAccount ? findsNothing : findsOneWidget,
        );
        expect(
          find.text(l10n.googleLinked),
          switchAccount ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  for (final scenario in [
    'success',
    'client-linked',
    'server-linked',
    'conflict',
    'switch-success',
    'switch-conflict',
    'invalid-prepare',
    'invalid-completion',
    'attempt-mismatch',
  ]) {
    test('Google linking handles $scenario for its starting UID', () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final linkingUser = GoogleLinkUser('first')
        ..linked = scenario == 'client-linked';
      auth.currentUser = linkingUser;
      final paths = <String>[];
      linkingUser.onLink = () async {
        if (scenario.startsWith('switch')) {
          auth.currentUser = GoogleLinkUser('second');
        }
        if (scenario == 'conflict' || scenario == 'switch-conflict') {
          throw FirebaseAuthException(code: 'credential-already-in-use');
        }
      };
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient((request) async {
          final path = request.url.path.split('/').last;
          paths.add(path);
          if (path == 'prepareGoogleLink') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'alreadyLinked': scenario == 'server-linked',
                'attemptId': scenario == 'invalid-prepare' ? 'bad' : attempt,
              }),
              200,
            );
          }
          if (path == 'recordGoogleLinkConflict') {
            return http.Response('{"ok":true}', 200);
          }
          expect(path, 'completeGoogleLink');
          expect(jsonDecode(request.body), {'attemptId': attempt});
          if (scenario == 'attempt-mismatch') {
            return http.Response(
              '{"ok":false,"error":"account-link-attempt-mismatch"}',
              409,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'linked': scenario != 'invalid-completion',
              'uid': 'first',
              'state': {
                'gold': 6543,
                'profile': {'username': 'linked_player'},
              },
            }),
            200,
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
      if (['success', 'client-linked', 'server-linked'].contains(scenario)) {
        await service.linkGoogle();
        expect(store.data.gold, 6543);
        expect(store.data.username, 'linked_player');
        expect(await store.readGoogleLinkAttempt('first'), isNull);
        expect(linkingUser.refreshedTokens, 1);
        expect(linkingUser.links, scenario == 'success' ? 1 : 0);
      } else {
        await expectLater(service.linkGoogle(), throwsA(anything));
        expect(store.data.gold, isNot(6543));
      }
      if (scenario.startsWith('switch') || scenario == 'invalid-prepare') {
        expect(paths, ['prepareGoogleLink']);
      } else if (scenario == 'conflict') {
        expect(paths, ['prepareGoogleLink', 'recordGoogleLinkConflict']);
        expect(await store.readGoogleLinkAttempt('first'), isNull);
      } else {
        expect(paths, ['prepareGoogleLink', 'completeGoogleLink']);
      }
      if (scenario == 'attempt-mismatch') {
        expect(await store.readGoogleLinkAttempt('first'), isNull);
      }
      if (scenario == 'invalid-completion') {
        expect(await store.readGoogleLinkAttempt('first'), attempt);
      }
    });
  }

  test(
    'cancelled linking survives service restart and reuses its prepared attempt',
    () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final linkingUser = GoogleLinkUser('first');
      auth.currentUser = linkingUser;
      var cancel = true;
      linkingUser.onLink = () async {
        if (cancel) throw FirebaseAuthException(code: 'web-context-canceled');
      };
      var prepares = 0;
      var completions = 0;
      LunoOnlineService createService() => LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/prepareGoogleLink')) {
            prepares++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'attemptId': attempt,
                'alreadyLinked': false,
              }),
              200,
            );
          }
          completions++;
          expect(jsonDecode(request.body), {'attemptId': attempt});
          return http.Response(
            '{"ok":true,"linked":true,"uid":"first","state":{"gold":6543}}',
            200,
          );
        }),
        appCheck: () async => 'check',
      );
      var service = createService();
      addTearDown(() async {
        service.dispose();
        await store.flush();
        store.dispose();
      });
      await service.start();
      await expectLater(
        service.linkGoogle(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(await store.readGoogleLinkAttempt('first'), attempt);
      service.dispose();
      service = createService();
      cancel = false;
      await service.start();
      await service.linkGoogle();
      expect(prepares, 1);
      expect(completions, 1);
      expect(linkingUser.links, 2);
      expect(store.data.gold, 6543);
    },
  );

  test(
    'native provider success can finish after an unconfirmed server response',
    () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final linkingUser = GoogleLinkUser('first');
      auth.currentUser = linkingUser;
      var prepares = 0;
      var complete = false;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/prepareGoogleLink')) {
            prepares++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'attemptId': attempt,
                'alreadyLinked': false,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'linked': complete,
              'uid': 'first',
              'state': {'gold': 6543},
            }),
            200,
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
      await expectLater(service.linkGoogle(), throwsFormatException);
      complete = true;
      await service.linkGoogle();
      expect(prepares, 1);
      expect(linkingUser.links, 1);
      expect(store.data.gold, 6543);
    },
  );

  test(
    'parallel linking and deletion cannot dispatch while native selection is open',
    () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final linkingUser = GoogleLinkUser('first');
      auth.currentUser = linkingUser;
      final entered = Completer<void>();
      final release = Completer<void>();
      linkingUser.onLink = () async {
        entered.complete();
        await release.future;
      };
      var prepares = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/prepareGoogleLink')) {
            prepares++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'attemptId': attempt,
                'alreadyLinked': false,
              }),
              200,
            );
          }
          return http.Response(
            '{"ok":true,"linked":true,"uid":"first","state":{"gold":6543}}',
            200,
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
      final first = service.linkGoogle();
      await entered.future;
      await expectLater(service.linkGoogle(), throwsA(isA<LunoApiException>()));
      await expectLater(
        service.deleteAccount(confirmed: true),
        throwsA(isA<LunoApiException>()),
      );
      expect(prepares, 1);
      release.complete();
      await first;
    },
  );

  test('pending link IDs are isolated and erased with their owner', () async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.bindAccount('A');
    await store.writeGoogleLinkAttempt('A', attempt);
    await store.bindAccount('B');
    expect(await store.readGoogleLinkAttempt('A'), isNull);
    await expectLater(
      store.writeGoogleLinkAttempt('A', attempt),
      throwsStateError,
    );
    await store.bindAccount('A');
    expect(await store.readGoogleLinkAttempt('A'), attempt);
    await store.eraseLocalAccount('A');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((key) => key.endsWith('_google_link')),
      isEmpty,
    );
  });
}
