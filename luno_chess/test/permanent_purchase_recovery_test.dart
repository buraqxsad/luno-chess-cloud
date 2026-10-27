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

const item = 'piece_set:roma';
String journalKey(String uid) =>
    '${accountKey(uid)}_pending_permanent_purchases';
Map<String, dynamic> recoveredPurchase() => {
  'ok': true,
  'purchased': false,
  'idempotent': true,
  'itemId': item,
  'transactionId': 'original-purchase',
  'grant': {'kind': 'piece_set', 'id': 'roma'},
  'state': {
    'gold': 0,
    'gems': 0,
    'inventory': {
      'ownedSets': ['std', 'roma'],
      'activePieceSet': 'std',
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<GameStore> storeFor([String uid = 'first']) async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.bindAccount(uid);
    return store;
  }

  LunoOnlineService serviceFor(
    GameStore store,
    Future<http.Response> Function(http.Request) respond, {
    TestAuth? auth,
  }) {
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth ?? TestAuth(),
      playerStore: store,
      appCheck: () async => 'check',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          return http.Response(jsonEncode(deck_fixture.response()), 200);
        }
        return respond(request);
      }),
    );
    addTearDown(service.dispose);
    return service;
  }

  for (final kind in [
    'piece_set',
    'skin',
    'emoji',
    'frame',
    'bio_frame',
    'costume',
    'costume_pack',
  ]) {
    test(
      '$kind journal survives recreation without replacing other intents',
      () async {
        final store = await storeFor(),
            id = '$kind:${kind == 'costume_pack' ? 'all' : 'example'}';
        await store.stagePermanentPurchase('first', id, 'original');
        await store.stageShopChestRequest('first', 'rare', 'paid-chest');
        final restarted = await storeFor();
        expect(
          await restarted.stagePermanentPurchase('first', id, 'unused'),
          'original',
        );
        await restarted.clearPermanentPurchase('first', id, 'original');
        expect(await restarted.pendingPermanentPurchaseItems('first'), isEmpty);
        expect(await restarted.pendingShopChestRequestKinds('first'), ['rare']);
      },
    );
  }
  test(
    'concurrent product staging preserves each intent and rejects old acknowledgement',
    () async {
      final store = await storeFor();
      final ids = await Future.wait([
        for (var i = 0; i < 10; i++)
          store.stagePermanentPurchase('first', item, 'candidate-$i'),
      ]);
      expect(ids.toSet(), {'candidate-0'});
      await store.stagePermanentPurchase('first', 'piece_set:ice', 'ice');
      await store.clearPermanentPurchase('first', item, 'old');
      expect(
        await store.stagePermanentPurchase('first', item, 'unused'),
        'candidate-0',
      );
      await store.clearPermanentPurchase('first', item, 'candidate-0');
      expect(await store.pendingPermanentPurchaseItems('first'), [
        'piece_set:ice',
      ]);
    },
  );
  test('account erasure clears only the departed purchase journal', () async {
    final store = await storeFor();
    await store.stagePermanentPurchase('first', item, 'first-request');
    await store.bindAccount('second');
    await store.stagePermanentPurchase('second', item, 'second-request');
    expect(await store.pendingPermanentPurchaseItems('first'), isEmpty);
    await store.eraseLocalAccount('first');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(journalKey('first')), isNull);
    expect(
      await store.stagePermanentPurchase('second', item, 'unused'),
      'second-request',
    );
    await expectLater(
      store.stagePermanentPurchase('first', item, 'late'),
      throwsStateError,
    );
  });
  for (final value in [
    'bad-json',
    '[]',
    '{"pass:premium":"old"}',
    '{"piece_set:roma":5}',
    '{"piece_set:roma":"bad\\nheader"}',
  ]) {
    test(
      'malformed journal $value fails closed without replacing it',
      () async {
        final store = await storeFor(),
            prefs = await SharedPreferences.getInstance();
        await prefs.setString(journalKey('first'), value);
        await expectLater(
          store.stagePermanentPurchase('first', item, 'new'),
          throwsStateError,
        );
        await expectLater(
          store.pendingPermanentPurchaseItems('first'),
          throwsStateError,
        );
        expect(prefs.getString(journalKey('first')), value);
      },
    );
  }
  for (final invalid in [
    'pass:premium',
    'unknown:roma',
    'piece_set:../roma',
    'piece_set:',
    'costume_pack:other',
  ]) {
    test(
      'non-permanent or invalid $invalid cannot enter the journal',
      () async {
        final store = await storeFor();
        await expectLater(
          store.stagePermanentPurchase('first', invalid, 'valid'),
          throwsArgumentError,
        );
        expect(await store.pendingPermanentPurchaseItems('first'), isEmpty);
      },
    );
  }
  test(
    'in-progress failure and recreated service reuse the persisted request ID',
    () async {
      final store = await storeFor();
      var fail = true;
      final ids = <String>[];
      Future<http.Response> respond(http.Request request) async {
        expect(request.url.path.endsWith('/purchaseSoftItem'), true);
        ids.add(request.headers['X-Luno-Request-Id']!);
        return fail
            ? http.Response('{"ok":false,"error":"request-in-progress"}', 409)
            : http.Response(jsonEncode(recoveredPurchase()), 200);
      }

      final first = serviceFor(store, respond);
      await first.start();
      await expectLater(
        first.purchaseSoftItem(item),
        throwsA(isA<LunoApiException>()),
      );
      final restarted = serviceFor(store, respond);
      await restarted.start();
      fail = false;
      expect((await restarted.purchaseSoftItem(item))['idempotent'], true);
      expect(ids.toSet().length, 1);
      expect(await store.pendingPermanentPurchaseItems('first'), isEmpty);
    },
  );
  test('concurrent purchase taps share one network request', () async {
    final store = await storeFor(),
        entered = Completer<void>(),
        response = Completer<http.Response>();
    var calls = 0;
    final service = serviceFor(store, (_) async {
      calls++;
      entered.complete();
      return response.future;
    });
    await service.start();
    final results = Future.wait([
      for (var i = 0; i < 8; i++) service.purchaseSoftItem(item),
    ]);
    await entered.future;
    response.complete(http.Response(jsonEncode(recoveredPurchase()), 200));
    expect((await results).length, 8);
    expect(calls, 1);
  });
  for (final code in [
    'insufficient-balance',
    'already-owned',
    'soft-purchase-receipt-invalid',
    'request-in-progress',
    'billing-review-required',
  ]) {
    test(
      '$code clears only a definitely unconsumed permanent intent',
      () async {
        final store = await storeFor();
        final service = serviceFor(
          store,
          (_) async =>
              http.Response(jsonEncode({'ok': false, 'error': code}), 409),
        );
        await service.start();
        await expectLater(
          service.purchaseSoftItem(item),
          throwsA(isA<LunoApiException>()),
        );
        expect(
          await store.pendingPermanentPurchaseItems('first'),
          ['insufficient-balance', 'already-owned'].contains(code)
              ? isEmpty
              : [item],
        );
      },
    );
  }
  for (final field in [
    'ok',
    'purchased',
    'itemId',
    'transactionId',
    'grant',
    'state',
  ]) {
    test(
      'missing $field confirmation cannot erase a pending purchase',
      () async {
        final store = await storeFor(),
            result = recoveredPurchase()..remove(field);
        final service = serviceFor(
          store,
          (_) async => http.Response(jsonEncode(result), 200),
        );
        await service.start();
        await expectLater(
          service.purchaseSoftItem(item),
          field == 'ok'
              ? throwsA(
                isA<LunoApiException>()
                    .having(
                      (error) => error.code,
                      'code',
                      'invalid-server-response',
                    )
                    .having((error) => error.status, 'status', 200),
              )
              : throwsFormatException,
        );
        expect(await store.pendingPermanentPurchaseItems('first'), [item]);
      },
    );
  }
  test(
    'grant or ownership mismatch cannot confirm the wrong product',
    () async {
      final store = await storeFor();
      final result = recoveredPurchase();
      result['grant'] = {'kind': 'piece_set', 'id': 'ice'};
      final service = serviceFor(
        store,
        (_) async => http.Response(jsonEncode(result), 200),
      );
      await service.start();
      await expectLater(service.purchaseSoftItem(item), throwsFormatException);
      result['grant'] = {'kind': 'piece_set', 'id': 'roma'};
      (result['state'] as Map)['inventory'] = {
        'ownedSets': ['std'],
      };
      await expectLater(service.purchaseSoftItem(item), throwsFormatException);
      expect(await store.pendingPermanentPurchaseItems('first'), [item]);
    },
  );
  test(
    'departed session response cannot clear or apply the old account receipt',
    () async {
      final store = await storeFor(),
          auth = TestAuth(),
          entered = Completer<void>(),
          response = Completer<http.Response>();
      final service = serviceFor(store, (_) async {
        entered.complete();
        return response.future;
      }, auth: auth);
      await service.start();
      final pending = service.purchaseSoftItem(item);
      final rejected = expectLater(
        pending,
        throwsA(
          isA<LunoApiException>().having(
            (error) => error.code,
            'code',
            'session-changed',
          ),
        ),
      );
      await entered.future;
      auth.currentUser = TestUser('second');
      await store.bindAccount('second');
      response.complete(http.Response(jsonEncode(recoveredPurchase()), 200));
      await rejected;
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(journalKey('first'))!) as Map,
        contains(item),
      );
      expect(await store.pendingPermanentPurchaseItems('second'), isEmpty);
    },
  );
  test(
    'premium Pass is deliberately not persisted as a permanent purchase',
    () async {
      final store = await storeFor();
      final service = serviceFor(store, (request) async {
        final state = {
          'gems': 0,
          'passState': {'seasonKey': 'ranked-s6-v2', 'premium': true},
          'economy': {
            'periods': {'seasonId': 's6'},
          },
        };
        if (request.url.path.endsWith('/getPlayerState')) {
          return http.Response(jsonEncode({'ok': true, 'state': state}), 200);
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'purchased': true,
            'idempotent': false,
            'itemId': 'pass:premium',
            'seasonId': 's6',
            'currentSeasonId': 's6',
            'passActive': true,
            'transactionId': 'premium-transaction',
            'grant': {'kind': 'pass_premium', 'id': 'premium'},
            'state': state,
          }),
          200,
        );
      });
      await service.start();
      expect((await service.purchaseSoftItem('pass:premium'))['ok'], true);
      expect(await store.pendingPermanentPurchaseItems('first'), isEmpty);
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
    },
  );

  for (final chest in [false, true]) {
    testWidgets(
      'unrelated daily modal keeps pending ${chest ? 'chest' : 'item'} tile mounted',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1280);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await storeFor(),
            entered = Completer<void>(),
            response = Completer<http.Response>();
        if (chest) {
          await store.stageShopChestRequest('first', 'rare', 'pending-chest');
        } else {
          await store.stagePermanentPurchase('first', item, 'pending-item');
        }
        final service = serviceFor(store, (request) async {
          if (request.url.path.endsWith('/getPlayerState')) {
            return http.Response('{"ok":true,"state":{}}', 200);
          }
          expect(request.url.path.endsWith('/claimDailyReward'), true);
          entered.complete();
          return response.future;
        });
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
        final tile = find.byKey(
          ValueKey(chest ? 'pending-shop-chest' : 'pending-permanent-purchase'),
        );
        expect(tile, findsOneWidget);
        final element = tester.element(tile);
        final daily = find.widgetWithText(FilledButton, 'AL');
        await tester.ensureVisible(daily);
        await tester.pumpAndSettle();
        await tester.tap(daily);
        await tester.runAsync(() async {
          await entered.future;
          response.complete(
            http.Response(
              '{"ok":true,"granted":true,"reward":{"gold":100},"state":{"gold":100}}',
              200,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        expect(
          element.mounted,
          true,
          reason:
              'An unrelated reward must not dispose a pending recovery tile.',
        );
        await tester.pumpAndSettle();
        final close = find.descendant(
          of: find.byType(ShopRewardDialog),
          matching: find.byType(LunoButton),
        );
        await tester.tap(close);
        await tester.pumpAndSettle();
        await tester.drag(
          find.byWidgetPredicate(
            (widget) =>
                widget is ListView && widget.scrollDirection == Axis.vertical,
          ),
          const Offset(0, 1000),
        );
        await tester.pumpAndSettle();
        expect(tile, findsOneWidget);
        expect(
          await store.pendingPermanentPurchaseItems('first'),
          chest ? isEmpty : [item],
        );
        expect(
          await store.pendingShopChestRequestKinds('first'),
          chest ? ['rare'] : isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('visible recovery tile cannot follow another account', (
    tester,
  ) async {
    final store = await storeFor(), auth = TestAuth();
    await store.stagePermanentPurchase('first', item, 'first-purchase');
    final service = serviceFor(
      store,
      (_) async => http.Response('{"ok":true,"state":{}}', 200),
      auth: auth,
    );
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
    final tile = find.byKey(const ValueKey('pending-permanent-purchase'));
    expect(tile, findsOneWidget);
    auth.currentUser = TestUser('second');
    await store.bindAccount('second');
    await tester.pump();
    expect(tile, findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(journalKey('first')), contains('first-purchase'));
    expect(await store.pendingPermanentPurchaseItems('second'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final english in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(800, 1280),
    ]) {
      testWidgets(
        'owned item retry stays reachable at zero balance: en=$english $size',
        (tester) async {
          final errors = <FlutterErrorDetails>[],
              oldHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            errors.add(details);
            oldHandler?.call(details);
          };
          addTearDown(() => FlutterError.onError = oldHandler);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = await storeFor();
          await store.stagePermanentPurchase(
            'first',
            item,
            'paid-before-restart',
          );
          var purchases = 0;
          final service = serviceFor(store, (request) async {
            if (request.url.path.endsWith('/getPlayerState')) {
              return http.Response(
                jsonEncode({'ok': true, 'state': recoveredPurchase()['state']}),
                200,
              );
            }
            purchases++;
            expect(request.headers['X-Luno-Request-Id'], 'paid-before-restart');
            return http.Response(jsonEncode(recoveredPurchase()), 200);
          });
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
          expect(
            find.text(
              english ? 'Pending item transaction' : 'Bekleyen ürün işlemi',
            ),
            findsOneWidget,
          );
          expect(store.data.gems, 0);
          final tile = find.byKey(const ValueKey('pending-permanent-purchase'));
          final retry = find.descendant(
            of: tile,
            matching: find.byType(LunoButton),
          );
          expect(tester.widget<LunoButton>(retry).onPressed, isNotNull);
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          expect(tester.getRect(retry).right, lessThanOrEqualTo(size.width));
          expect(tester.getRect(retry).bottom, lessThanOrEqualTo(size.height));
          tester.widget<LunoButton>(retry).onPressed!();
          await tester.tap(retry);
          await tester.runAsync(() async {
            final prefs = await SharedPreferences.getInstance();
            for (
              var i = 0;
              i < 50 && prefs.getString(journalKey('first')) != null;
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
          await tester.pumpAndSettle();
          expect(purchases, 1);
          final reveal = find.byType(ShopRewardDialog);
          expect(reveal, findsOneWidget);
          expect(
            find.text(
              english
                  ? 'Purchase confirmed. The item is in your account.'
                  : 'Satın alma doğrulandı. Ürün hesabında.',
            ),
            findsOneWidget,
          );
          final close = find.descendant(
            of: reveal,
            matching: find.byType(LunoButton),
          );
          await tester.ensureVisible(close);
          await tester.pumpAndSettle();
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(tile, findsNothing);
          expect(await store.pendingPermanentPurchaseItems('first'), isEmpty);
          expect(store.data.pieceSet, 'luno');
          expect(
            errors,
            isEmpty,
            reason: errors.map((error) => error.toString()).join('\n'),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
