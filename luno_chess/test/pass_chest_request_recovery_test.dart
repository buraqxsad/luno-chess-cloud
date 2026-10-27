import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart' show ChestRevealDialog;
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_store_isolation_test.dart' show accountKey;
import 'online_request_session_test.dart' show TestAuth, TestUser;

Map<String, dynamic> confirmed() => {
  'ok': true,
  'opened': false,
  'idempotent': true,
  'state': {'gold': 1500},
  'rewards': [
    {'type': 'gold', 'amount': 250},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GameStore> storeFor(String uid) async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.bindAccount(uid);
    return store;
  }

  test('concurrent staging shares one durable request identity', () async {
    final store = await storeFor('first');
    final ids = await Future.wait([
      for (var i = 0; i < 10; i++)
        store.stagePassChestRequest('first', 'rare', 'candidate-$i'),
    ]);
    expect(ids.toSet(), {'candidate-0'});
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${accountKey('first')}_pending_pass_chest_rare'),
      'candidate-0',
    );
  });

  test(
    'a recreated store recovers its account-owned pending identity',
    () async {
      final first = await storeFor('first');
      await first.stagePassChestRequest('first', 'royal', 'before-restart');
      final restarted = await storeFor('first');
      expect(
        await restarted.stagePassChestRequest(
          'first',
          'royal',
          'after-restart',
        ),
        'before-restart',
      );
    },
  );

  test(
    'different accounts and chest kinds never share request identities',
    () async {
      final store = await storeFor('first');
      expect(
        await store.stagePassChestRequest('first', 'rare', 'first-rare'),
        'first-rare',
      );
      expect(
        await store.stagePassChestRequest('first', 'common', 'first-common'),
        'first-common',
      );
      await store.bindAccount('second');
      expect(
        await store.stagePassChestRequest('second', 'rare', 'second-rare'),
        'second-rare',
      );
      await store.bindAccount('first');
      expect(
        await store.stagePassChestRequest('first', 'rare', 'unused'),
        'first-rare',
      );
    },
  );

  test(
    'only the matching acknowledgement clears the pending request',
    () async {
      final store = await storeFor('first');
      await store.stagePassChestRequest('first', 'rare', 'owned');
      await store.clearPassChestRequest('first', 'rare', 'different');
      expect(
        await store.stagePassChestRequest('first', 'rare', 'unused'),
        'owned',
      );
      await store.clearPassChestRequest('first', 'rare', 'owned');
      expect(
        await store.stagePassChestRequest('first', 'rare', 'next'),
        'next',
      );
    },
  );

  test(
    'pending request discovery is account-owned and follows acknowledgements',
    () async {
      final store = await storeFor('first');
      await store.stagePassChestRequest('first', 'rare', 'first-rare');
      await store.stagePassChestRequest('first', 'royal', 'first-royal');
      expect(await store.pendingPassChestRequestKinds('first'), [
        'rare',
        'royal',
      ]);
      await store.clearPassChestRequest('first', 'rare', 'first-rare');
      expect(await store.pendingPassChestRequestKinds('first'), ['royal']);
      await store.bindAccount('second');
      expect(await store.pendingPassChestRequestKinds('first'), isEmpty);
      expect(await store.pendingPassChestRequestKinds('second'), isEmpty);
    },
  );

  test(
    'account erasure removes its journals and prevents late recreation',
    () async {
      final store = await storeFor('first');
      for (final kind in ['common', 'rare', 'legendary', 'royal']) {
        await store.stagePassChestRequest('first', kind, 'request-$kind');
      }
      await store.bindAccount('second');
      await store.stagePassChestRequest('second', 'rare', 'other');
      await store.eraseLocalAccount('first');
      final prefs = await SharedPreferences.getInstance();
      for (final kind in ['common', 'rare', 'legendary', 'royal']) {
        expect(
          prefs.getString('${accountKey('first')}_pending_pass_chest_$kind'),
          isNull,
        );
      }
      expect(
        await store.stagePassChestRequest('second', 'rare', 'unused'),
        'other',
      );
      await expectLater(
        store.stagePassChestRequest('first', 'rare', 'late'),
        throwsStateError,
      );
    },
  );

  test(
    'malformed stored identity fails closed rather than creating a new operation',
    () async {
      final store = await storeFor('first'),
          prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${accountKey('first')}_pending_pass_chest_rare',
        'bad\nheader',
      );
      await expectLater(
        store.stagePassChestRequest('first', 'rare', 'new'),
        throwsStateError,
      );
      expect(
        prefs.getString('${accountKey('first')}_pending_pass_chest_rare'),
        'bad\nheader',
      );
    },
  );

  for (final malformed in ['unknown', 'rare/other']) {
    test(
      'invalid chest kind $malformed is rejected before persistence',
      () async {
        final store = await storeFor('first');
        await expectLater(
          store.stagePassChestRequest('first', malformed, 'valid'),
          throwsArgumentError,
        );
      },
    );
  }

  test(
    '409 in-progress followed by a new service call reuses the saved identity',
    () async {
      final store = await storeFor('first'), auth = TestAuth();
      final ids = <String>[];
      var fail = true;
      final client = MockClient((request) async {
        ids.add(request.headers['X-Luno-Request-Id']!);
        expect(jsonDecode(request.body), {'chestId': 'rare'});
        return fail
            ? http.Response('{"ok":false,"error":"request-in-progress"}', 409)
            : http.Response(jsonEncode(confirmed()), 200);
      });
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: client,
        appCheck: () async => 'check',
        playerStore: store,
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(
        service.openPassChest('rare'),
        throwsA(isA<LunoApiException>()),
      );
      fail = false;
      expect((await service.openPassChest('rare'))['idempotent'], true);
      expect(ids.length, 2);
      expect(ids.toSet().length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${accountKey('first')}_pending_pass_chest_rare'),
        isNull,
      );
      await service.openPassChest('rare');
      expect(ids.last, isNot(ids.first));
    },
  );

  test(
    'recreated service sends the pending identity saved before a process restart',
    () async {
      final store = await storeFor('first');
      await store.stagePassChestRequest('first', 'rare', 'persisted-operation');
      final restarted = await storeFor('first');
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: restarted,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          expect(request.headers['X-Luno-Request-Id'], 'persisted-operation');
          return http.Response(jsonEncode(confirmed()), 200);
        }),
      );
      addTearDown(service.dispose);
      await service.start();
      expect((await service.openPassChest('rare'))['rewards'], isNotEmpty);
    },
  );

  test('concurrent service calls share one network opening', () async {
    final store = await storeFor('first'),
        entered = Completer<void>(),
        response = Completer<http.Response>();
    var requests = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      playerStore: store,
      appCheck: () async => 'check',
      client: MockClient((_) async {
        requests++;
        entered.complete();
        return response.future;
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    final results = Future.wait([
      for (var i = 0; i < 8; i++) service.openPassChest('rare'),
    ]);
    await entered.future;
    response.complete(http.Response(jsonEncode(confirmed()), 200));
    expect((await results).length, 8);
    expect(requests, 1);
  });

  test(
    'confirmed not-owned clears an unconsumed request without hiding other errors',
    () async {
      final store = await storeFor('first');
      await store.stagePassChestRequest('first', 'rare', 'unconsumed');
      var code = 'pass-chest-recovery-unavailable';
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'ok': false, 'error': code}), 409),
        ),
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(
        service.openPassChest('rare'),
        throwsA(isA<LunoApiException>()),
      );
      expect(await store.pendingPassChestRequestKinds('first'), ['rare']);
      code = 'pass-chest-not-owned';
      await expectLater(
        service.openPassChest('rare'),
        throwsA(isA<LunoApiException>()),
      );
      expect(await store.pendingPassChestRequestKinds('first'), isEmpty);
    },
  );

  for (final english in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(800, 1280),
    ]) {
      testWidgets(
        'last consumed chest remains recoverable in Pass: en=$english at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = await storeFor('first');
          await store.stagePassChestRequest('first', 'rare', 'last-consumed');
          expect(store.data.pendingChests, isEmpty);
          var requests = 0;
          final service = LunoOnlineService.forTesting(
            bootstrap: () async {},
            auth: TestAuth(),
            playerStore: store,
            appCheck: () async => 'check',
            client: MockClient((request) async {
              if (request.url.path.endsWith('/getPlayerState')) {
                return http.Response('{"ok":true,"state":{}}', 200);
              }
              expect(request.url.path.endsWith('/openPassChest'), true);
              requests++;
              expect(request.headers['X-Luno-Request-Id'], 'last-consumed');
              return http.Response(jsonEncode(confirmed()), 200);
            }),
          );
          addTearDown(service.dispose);
          await service.start();
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(english ? 'en' : 'tr'),
              supportedLocales: LunoLocalizations.supportedLocales,
              localizationsDelegates: const [
                LunoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: LunoTheme.dark,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.8)),
                    child: child!,
                  ),
              home: PassScreen(online: service, playerStore: store),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              english
                  ? 'Finish your pending chest opening.'
                  : 'Bekleyen sandık açılışını tamamla.',
            ),
            findsOneWidget,
          );
          final retry = find.widgetWithText(
            FilledButton,
            english ? 'RETRY' : 'TEKRAR DENE',
          );
          expect(retry, findsOneWidget);
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          final retryBounds = tester.getRect(retry);
          expect(retryBounds.left, greaterThanOrEqualTo(0));
          expect(retryBounds.right, lessThanOrEqualTo(size.width));
          expect(retryBounds.bottom, lessThanOrEqualTo(size.height));
          tester.widget<FilledButton>(retry).onPressed!();
          await tester.runAsync(() async {
            final prefs = await SharedPreferences.getInstance();
            for (var i = 0; i < 50; i++) {
              if (prefs.getString(
                    '${accountKey('first')}_pending_pass_chest_rare',
                  ) ==
                  null) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
          await tester.pumpAndSettle();
          expect(requests, 1);
          expect(await store.pendingPassChestRequestKinds('first'), isEmpty);
          final reveal = find.byType(ChestRevealDialog);
          expect(reveal, findsOneWidget);
          expect(
            tester.widget<ChestRevealDialog>(reveal).rewards,
            confirmed()['rewards'],
          );
          final close = find.descendant(
            of: reveal,
            matching: find.byType(LunoButton),
          );
          await tester.ensureVisible(close);
          await tester.pumpAndSettle();
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(reveal, findsNothing);
          expect(
            find.byKey(const ValueKey('pending-pass-chest')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'an open Pass screen does not expose a departed account recovery',
    (tester) async {
      final store = await storeFor('first');
      await store.stagePassChestRequest('first', 'rare', 'first-pending');
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: PassScreen(playerStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-pass-chest')), findsOneWidget);
      await store.bindAccount('second');
      await tester.pump();
      expect(find.byKey(const ValueKey('pending-pass-chest')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-pass-chest')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'malformed confirmation preserves the journal for a safe retry',
    () async {
      final store = await storeFor('first');
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient(
          (_) async => http.Response(
            '{"ok":true,"opened":true,"state":{},"rewards":[]}',
            200,
          ),
        ),
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(service.openPassChest('rare'), throwsFormatException);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${accountKey('first')}_pending_pass_chest_rare'),
        isNotNull,
      );
    },
  );

  test(
    'a departed session cannot acknowledge or clear its pending opening',
    () async {
      final store = await storeFor('first'),
          auth = TestAuth(),
          entered = Completer<void>(),
          response = Completer<http.Response>();
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient((_) async {
          entered.complete();
          return response.future;
        }),
      );
      addTearDown(service.dispose);
      await service.start();
      final operation = service.openPassChest('rare');
      await entered.future;
      auth.currentUser = TestUser('second');
      final assertion = expectLater(
        operation,
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'session-changed',
          ),
        ),
      );
      response.complete(http.Response(jsonEncode(confirmed()), 200));
      await assertion;
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${accountKey('first')}_pending_pass_chest_rare'),
        isNotNull,
      );
      expect(
        prefs.getString('${accountKey('second')}_pending_pass_chest_rare'),
        isNull,
      );
    },
  );
}
