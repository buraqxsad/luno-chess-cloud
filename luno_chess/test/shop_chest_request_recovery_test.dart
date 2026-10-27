import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_store_isolation_test.dart' show accountKey;
import 'battle_deck_account_test.dart' as deck_fixture;
import 'online_request_session_test.dart' show TestAuth, TestUser;

Map<String, dynamic> recoveredShopChest() => {
  'ok': true,
  'opened': false,
  'idempotent': true,
  'chestId': 'rare',
  'transactionId': 'original-purchase',
  'rewardTransactionIds': ['original-reward'],
  'state': {'gold': 0, 'gems': 0},
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

  for (final kind in ['common', 'rare', 'legendary', 'royal']) {
    test(
      '$kind shop journal survives store recreation without replacing Pass identity',
      () async {
        final store = await storeFor('first');
        await store.stagePassChestRequest('first', kind, 'pass-$kind');
        await store.stageShopChestRequest('first', kind, 'shop-$kind');
        final restarted = await storeFor('first');
        expect(
          await restarted.stageShopChestRequest('first', kind, 'unused'),
          'shop-$kind',
        );
        expect(
          await restarted.stagePassChestRequest('first', kind, 'unused'),
          'pass-$kind',
        );
        await restarted.clearShopChestRequest('first', kind, 'shop-$kind');
        expect(await restarted.pendingShopChestRequestKinds('first'), isEmpty);
        expect(await restarted.pendingPassChestRequestKinds('first'), [kind]);
      },
    );
  }
  test(
    'concurrent staging shares one shop request but accounts remain separated',
    () async {
      final store = await storeFor('first');
      final ids = await Future.wait([
        for (var i = 0; i < 10; i++)
          store.stageShopChestRequest('first', 'rare', 'candidate-$i'),
      ]);
      expect(ids.toSet(), {'candidate-0'});
      await store.bindAccount('second');
      expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
      await store.stageShopChestRequest('second', 'rare', 'second-operation');
      expect(await store.pendingShopChestRequestKinds('second'), ['rare']);
      await store.bindAccount('first');
      expect(
        await store.stageShopChestRequest('first', 'rare', 'unused'),
        'candidate-0',
      );
    },
  );
  test('old acknowledgements cannot clear a replacement journal', () async {
    final store = await storeFor('first');
    await store.stageShopChestRequest('first', 'rare', 'current');
    await store.clearShopChestRequest('first', 'rare', 'old');
    expect(
      await store.stageShopChestRequest('first', 'rare', 'unused'),
      'current',
    );
  });
  test(
    'erasure removes all shop and Pass journals without touching another account',
    () async {
      final store = await storeFor('first');
      for (final kind in ['common', 'rare', 'legendary', 'royal']) {
        await store.stageShopChestRequest('first', kind, 'shop-$kind');
        await store.stagePassChestRequest('first', kind, 'pass-$kind');
      }
      await store.bindAccount('second');
      await store.stageShopChestRequest('second', 'rare', 'other-account');
      await store.eraseLocalAccount('first');
      final prefs = await SharedPreferences.getInstance();
      for (final kind in ['common', 'rare', 'legendary', 'royal']) {
        for (final origin in ['shop', 'pass']) {
          expect(
            prefs.getString(
              '${accountKey('first')}_pending_${origin}_chest_$kind',
            ),
            isNull,
          );
        }
      }
      expect(
        await store.stageShopChestRequest('second', 'rare', 'unused'),
        'other-account',
      );
      await expectLater(
        store.stageShopChestRequest('first', 'rare', 'late'),
        throwsStateError,
      );
    },
  );
  test(
    'malformed pending journal fails closed without replacing request identity',
    () async {
      final store = await storeFor('first'),
          prefs = await SharedPreferences.getInstance();
      final key = '${accountKey('first')}_pending_shop_chest_rare';
      await prefs.setString(key, 'bad\nheader');
      await expectLater(
        store.stageShopChestRequest('first', 'rare', 'new'),
        throwsStateError,
      );
      await expectLater(
        store.pendingShopChestRequestKinds('first'),
        throwsStateError,
      );
      expect(prefs.getString(key), 'bad\nheader');
    },
  );
  for (final kind in ['unknown', 'rare/other']) {
    test(
      'invalid shop kind $kind is rejected without writing a journal',
      () async {
        final store = await storeFor('first');
        await expectLater(
          store.stageShopChestRequest('first', kind, 'valid'),
          throwsArgumentError,
        );
        expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
      },
    );
  }
  test(
    'an in-progress error and recreated service reuse the original purchase identity',
    () async {
      final store = await storeFor('first');
      var fail = true;
      final ids = <String>[];
      LunoOnlineService create() => LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          expect(request.url.path.endsWith('/openChest'), true);
          ids.add(request.headers['X-Luno-Request-Id']!);
          return fail
              ? http.Response('{"ok":false,"error":"request-in-progress"}', 409)
              : http.Response(jsonEncode(recoveredShopChest()), 200);
        }),
      );
      final first = create();
      addTearDown(first.dispose);
      await first.start();
      await expectLater(
        first.openChest('rare'),
        throwsA(isA<LunoApiException>()),
      );
      final restarted = create();
      addTearDown(restarted.dispose);
      await restarted.start();
      fail = false;
      expect((await restarted.openChest('rare'))['rewards'], isNotEmpty);
      expect(ids.toSet().length, 1);
      expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
    },
  );
  test('same-kind concurrent openings share one network request', () async {
    final store = await storeFor('first'),
        entered = Completer<void>(),
        response = Completer<http.Response>();
    var calls = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      playerStore: store,
      appCheck: () async => 'check',
      client: MockClient((_) async {
        calls++;
        entered.complete();
        return response.future;
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    final results = Future.wait([
      for (var i = 0; i < 8; i++) service.openChest('rare'),
    ]);
    await entered.future;
    response.complete(http.Response(jsonEncode(recoveredShopChest()), 200));
    expect((await results).length, 8);
    expect(calls, 1);
  });
  test(
    'shop and Pass openings of the same rarity do not share an in-flight request',
    () async {
      final store = await storeFor('first');
      final paths = <String>[], ids = <String>[];
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          paths.add(request.url.path);
          ids.add(request.headers['X-Luno-Request-Id']!);
          return http.Response(jsonEncode(recoveredShopChest()), 200);
        }),
      );
      addTearDown(service.dispose);
      await service.start();
      await Future.wait([
        service.openChest('rare'),
        service.openPassChest('rare'),
      ]);
      expect(paths.map((path) => path.split('/').last).toSet(), {
        'openChest',
        'openPassChest',
      });
      expect(ids.toSet().length, 2);
    },
  );
  test(
    'only an explicit insufficient-balance error clears an unconsumed shop request',
    () async {
      final store = await storeFor('first');
      var error = 'chest-purchase-receipt-invalid';
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'ok': false, 'error': error}), 409),
        ),
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(
        service.openChest('rare'),
        throwsA(isA<LunoApiException>()),
      );
      expect(await store.pendingShopChestRequestKinds('first'), ['rare']);
      error = 'insufficient-balance';
      await expectLater(
        service.openChest('rare'),
        throwsA(isA<LunoApiException>()),
      );
      expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
    },
  );
  test(
    'malformed success preserves the shop journal for safe recovery',
    () async {
      final store = await storeFor('first');
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient(
          (_) async => http.Response('{"ok":true,"state":{}}', 200),
        ),
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(service.openChest('rare'), throwsFormatException);
      expect(await store.pendingShopChestRequestKinds('first'), ['rare']);
    },
  );
  test('departed session cannot acknowledge an old purchase', () async {
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
    final operation = service.openChest('rare');
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
    response.complete(http.Response(jsonEncode(recoveredShopChest()), 200));
    await assertion;
    expect(await store.pendingShopChestRequestKinds('first'), ['rare']);
  });

  final malformedConfirmations = <String, Map<String, dynamic>>{
    'missing purchase identity': recoveredShopChest()..remove('transactionId'),
    'missing reward identities':
        recoveredShopChest()..remove('rewardTransactionIds'),
    'missing chest identity': recoveredShopChest()..remove('chestId'),
    'wrong chest identity': recoveredShopChest()..['chestId'] = 'common',
    'empty replay drops': recoveredShopChest()..['rewards'] = <Object>[],
    'duplicated reward identities':
        recoveredShopChest()
          ..['rewardTransactionIds'] = ['original-reward', 'original-reward'],
  };
  for (final entry in malformedConfirmations.entries) {
    test('${entry.key} cannot acknowledge a paid chest journal', () async {
      final store = await storeFor('first');
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'check',
        client: MockClient(
          (_) async => http.Response(jsonEncode(entry.value), 200),
        ),
      );
      addTearDown(service.dispose);
      await service.start();
      await expectLater(service.openChest('rare'), throwsFormatException);
      expect(await store.pendingShopChestRequestKinds('first'), ['rare']);
    });
  }

  testWidgets('open shop hides the departed account journal after a switch', (
    tester,
  ) async {
    final store = await storeFor('first'), auth = TestAuth();
    await store.stageShopChestRequest('first', 'rare', 'first-purchase');
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth,
      playerStore: store,
      appCheck: () async => 'check',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          return http.Response(jsonEncode(deck_fixture.response()), 200);
        }
        return http.Response('{"ok":true,"state":{}}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: ShopScreen(online: service, playerStore: store),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-shop-chest')), findsOneWidget);
    auth.currentUser = TestUser('second');
    await store.bindAccount('second');
    await tester.pump();
    expect(find.byKey(const ValueKey('pending-shop-chest')), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-shop-chest')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${accountKey('first')}_pending_shop_chest_rare'),
      'first-purchase',
    );
    expect(await store.pendingShopChestRequestKinds('second'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final english in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(800, 1280),
    ]) {
      testWidgets(
        'paid retry is reachable without sufficient balance: en=$english at $size',
        (tester) async {
          final reportedErrors = <FlutterErrorDetails>[];
          final originalErrorHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            reportedErrors.add(details);
            originalErrorHandler?.call(details);
          };
          addTearDown(() => FlutterError.onError = originalErrorHandler);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = await storeFor('first');
          await store.stageShopChestRequest(
            'first',
            'rare',
            'paid-before-restart',
          );
          var openings = 0;
          final service = LunoOnlineService.forTesting(
            bootstrap: () async {},
            auth: TestAuth(),
            playerStore: store,
            appCheck: () async => 'check',
            client: MockClient((request) async {
              if (request.url.path.endsWith('/getBattleV1Deck')) {
                return http.Response(jsonEncode(deck_fixture.response()), 200);
              }
              if (request.url.path.endsWith('/getPlayerState')) {
                return http.Response(
                  '{"ok":true,"state":{"gold":0,"gems":0}}',
                  200,
                );
              }
              openings++;
              expect(
                request.headers['X-Luno-Request-Id'],
                'paid-before-restart',
              );
              return http.Response(jsonEncode(recoveredShopChest()), 200);
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
              home: ShopScreen(online: service, playerStore: store),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(store.data.gold, 0);
          expect(store.data.gems, 0);
          expect(
            find.text(
              english ? 'Pending chest transaction' : 'Bekleyen sandık işlemi',
            ),
            findsOneWidget,
          );
          final retry = find.descendant(
            of: find.byKey(const ValueKey('pending-shop-chest')),
            matching: find.byType(LunoButton),
          );
          expect(tester.widget<LunoButton>(retry).onPressed, isNotNull);
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          expect(tester.getRect(retry).right, lessThanOrEqualTo(size.width));
          expect(tester.getRect(retry).bottom, lessThanOrEqualTo(size.height));
          final callback = tester.widget<LunoButton>(retry).onPressed!;
          callback();
          await tester.tap(retry);
          await tester.runAsync(() async {
            final prefs = await SharedPreferences.getInstance();
            for (var i = 0; i < 50; i++) {
              if (prefs.getString(
                    '${accountKey('first')}_pending_shop_chest_rare',
                  ) ==
                  null) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
          await tester.pumpAndSettle();
          expect(openings, 1);
          final reveal = find.byType(ChestRevealDialog);
          expect(reveal, findsOneWidget);
          expect(
            tester.widget<ChestRevealDialog>(reveal).rewards,
            recoveredShopChest()['rewards'],
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
            find.byKey(const ValueKey('pending-shop-chest')),
            findsNothing,
          );
          expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
          expect(
            reportedErrors,
            isEmpty,
            reason: reportedErrors.map((error) => error.toString()).join('\n'),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
