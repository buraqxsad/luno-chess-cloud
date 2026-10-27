import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/data/pass_purchase.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/pass_action_result.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_store_isolation_test.dart' show accountKey;
import 'online_request_session_test.dart' show TestAuth, TestUser;

String journalKey(String uid) =>
    '${accountKey(uid)}_pending_pass_premium_purchase';
const original = PassPremiumPurchase(seasonId: 's6', requestId: 'original');
Map<String, dynamic> passState(String season, {bool premium = false}) => {
  'gold': 0,
  'gems': 0,
  'passState': {
    'seasonKey': 'ranked-$season-v2',
    'season': int.parse(season.substring(1)),
    'level': 0,
    'xp': 0,
    'premium': premium,
    'claimed': {'free': <String, bool>{}, 'premium': <String, bool>{}},
    'unlocks': <String>[],
  },
  'economy': {
    'periods': {'seasonId': season},
  },
};
Map<String, dynamic> confirmation({bool expired = false}) => {
  'ok': true,
  'purchased': false,
  'idempotent': true,
  'itemId': 'pass:premium',
  'seasonId': 's6',
  'currentSeasonId': expired ? 's7' : 's6',
  'passActive': !expired,
  'transactionId': 'original-transaction',
  'grant': {'kind': 'pass_premium', 'id': 'premium'},
  'state': passState(expired ? 's7' : 's6', premium: !expired),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });
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
      client: MockClient(respond),
    );
    addTearDown(service.dispose);
    return service;
  }

  test(
    'recreation retains the original season and request, not a new season',
    () async {
      final store = await storeFor();
      await store.stagePassPremiumPurchase('first', original);
      final restarted = await storeFor();
      final retained = await restarted.stagePassPremiumPurchase(
        'first',
        const PassPremiumPurchase(seasonId: 's7', requestId: 'new-season'),
      );
      expect(retained.seasonId, 's6');
      expect(retained.requestId, 'original');
    },
  );
  test(
    'concurrent staging shares one identity and acknowledgement compares both fields',
    () async {
      final store = await storeFor();
      final results = await Future.wait([
        for (var i = 0; i < 10; i++)
          store.stagePassPremiumPurchase(
            'first',
            PassPremiumPurchase(seasonId: 's6', requestId: 'candidate-$i'),
          ),
      ]);
      expect(results.map((value) => value.requestId).toSet(), {'candidate-0'});
      for (final wrong in [
        const PassPremiumPurchase(seasonId: 's7', requestId: 'candidate-0'),
        const PassPremiumPurchase(seasonId: 's6', requestId: 'wrong'),
      ]) {
        await store.clearPassPremiumPurchase('first', wrong);
        expect(
          (await store.pendingPassPremiumPurchase('first'))?.requestId,
          'candidate-0',
        );
      }
      await store.clearPassPremiumPurchase('first', results.first);
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
    },
  );
  test(
    'account switching and erasure never expose or clear another journal',
    () async {
      final store = await storeFor();
      await store.stagePassPremiumPurchase('first', original);
      await store.bindAccount('second');
      const other = PassPremiumPurchase(
        seasonId: 's7',
        requestId: 'second-request',
      );
      await store.stagePassPremiumPurchase('second', other);
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
      await expectLater(
        store.clearPassPremiumPurchase('first', original),
        throwsStateError,
      );
      await store.eraseLocalAccount('first');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(journalKey('first')), isNull);
      expect(
        (await store.pendingPassPremiumPurchase('second'))?.requestId,
        'second-request',
      );
      await expectLater(
        store.stagePassPremiumPurchase('first', original),
        throwsStateError,
      );
    },
  );
  test(
    'reading pending state never reloads an already loaded player',
    () async {
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      addTearDown(store.dispose);
      store.data.passXp = 250;
      store.data.gems = 9999;
      store.data.pendingChests = ['common'];
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
      expect(store.accountUid, 'first');
      expect(store.data.passXp, 250);
      expect(store.data.gems, 9999);
      expect(store.data.pendingChests, ['common']);
    },
  );
  for (final raw in [
    'bad-json',
    '[]',
    '{"version":1,"seasonId":"s06","requestId":"old"}',
    '{"version":1,"seasonId":"s6","requestId":"bad\\nheader"}',
    '{"version":2,"seasonId":"s6","requestId":"old"}',
    '{"version":1,"seasonId":"s6","requestId":"old","extra":true}',
  ]) {
    test('corrupt journal $raw fails closed without replacement', () async {
      final store = await storeFor(),
          prefs = await SharedPreferences.getInstance();
      await prefs.setString(journalKey('first'), raw);
      await expectLater(
        store.stagePassPremiumPurchase('first', original),
        throwsStateError,
      );
      await expectLater(
        store.pendingPassPremiumPurchase('first'),
        throwsStateError,
      );
      expect(prefs.getString(journalKey('first')), raw);
    });
  }
  for (final invalid in [
    const PassPremiumPurchase(seasonId: 's0', requestId: 'valid'),
    const PassPremiumPurchase(seasonId: 's06', requestId: 'valid'),
    const PassPremiumPurchase(seasonId: 's6:other', requestId: 'valid'),
    const PassPremiumPurchase(seasonId: 's6', requestId: 'bad\nheader'),
  ]) {
    test(
      'invalid intent ${invalid.seasonId}/${invalid.requestId} is not persisted',
      () async {
        final store = await storeFor();
        await expectLater(
          store.stagePassPremiumPurchase('first', invalid),
          throwsArgumentError,
        );
        expect(await store.pendingPassPremiumPurchase('first'), isNull);
      },
    );
  }
  test(
    'fresh purchase uses the server season and persists before sending',
    () async {
      final store = await storeFor();
      final paths = <String>[];
      final service = serviceFor(store, (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/getPlayerState')) {
          return http.Response(
            jsonEncode({'ok': true, 'state': passState('s6')}),
            200,
          );
        }
        final pending = await store.pendingPassPremiumPurchase('first');
        expect(pending, isNotNull);
        expect(request.headers['X-Luno-Request-Id'], pending!.requestId);
        expect(jsonDecode(request.body), {
          'itemId': 'pass:premium',
          'seasonId': 's6',
        });
        return http.Response(jsonEncode(confirmation()), 200);
      });
      await service.start();
      await service.purchaseSoftItem('pass:premium');
      expect(paths.length, 2);
      expect(paths.first.endsWith('/getPlayerState'), true);
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
      expect(await store.pendingPermanentPurchaseItems('first'), isEmpty);
    },
  );
  test(
    'an unconfirmed server season cannot create or send a purchase intent',
    () async {
      final store = await storeFor();
      var calls = 0;
      final service = serviceFor(store, (_) async {
        calls++;
        return http.Response(
          jsonEncode({'ok': true, 'state': passState('s7')..['economy'] = {}}),
          200,
        );
      });
      await service.start();
      await expectLater(
        service.purchaseSoftItem('pass:premium'),
        throwsFormatException,
      );
      expect(calls, 1);
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
    },
  );
  test(
    'restarted service retries the same old-season request, without a fresh-season fetch',
    () async {
      final store = await storeFor();
      await store.stagePassPremiumPurchase('first', original);
      var fail = true;
      final ids = <String>[];
      Future<http.Response> respond(http.Request request) async {
        expect(request.url.path.endsWith('/purchaseSoftItem'), true);
        expect(jsonDecode(request.body), {
          'itemId': 'pass:premium',
          'seasonId': 's6',
        });
        ids.add(request.headers['X-Luno-Request-Id']!);
        return fail
            ? http.Response('{"ok":false,"error":"request-in-progress"}', 409)
            : http.Response(jsonEncode(confirmation(expired: true)), 200);
      }

      final first = serviceFor(store, respond);
      await first.start();
      await expectLater(
        first.purchaseSoftItem('pass:premium'),
        throwsA(isA<LunoApiException>()),
      );
      final restarted = serviceFor(await storeFor(), respond);
      await restarted.start();
      fail = false;
      final result = await restarted.purchaseSoftItem('pass:premium');
      expect(result['passActive'], false);
      expect(ids, ['original', 'original']);
      expect(await store.pendingPassPremiumPurchase('first'), isNull);
    },
  );
  test('concurrent purchases share one HTTP request and one journal', () async {
    final store = await storeFor(),
        entered = Completer<void>(),
        response = Completer<http.Response>();
    await store.stagePassPremiumPurchase('first', original);
    var calls = 0;
    final service = serviceFor(store, (_) async {
      calls++;
      entered.complete();
      return response.future;
    });
    await service.start();
    final results = Future.wait([
      for (var i = 0; i < 8; i++) service.purchaseSoftItem('pass:premium'),
    ]);
    await entered.future;
    response.complete(http.Response(jsonEncode(confirmation()), 200));
    expect((await results).length, 8);
    expect(calls, 1);
  });
  for (final code in [
    'insufficient-balance',
    'already-owned',
    'pass-season-changed',
    'request-in-progress',
    'pass-purchase-receipt-invalid',
    'billing-review-required',
  ]) {
    test('$code only clears an explicitly unconsumed intent', () async {
      final store = await storeFor();
      await store.stagePassPremiumPurchase('first', original);
      final service = serviceFor(
        store,
        (_) async =>
            http.Response(jsonEncode({'ok': false, 'error': code}), 409),
      );
      await service.start();
      await expectLater(
        service.purchaseSoftItem('pass:premium'),
        throwsA(isA<LunoApiException>()),
      );
      final pending = await store.pendingPassPremiumPurchase('first');
      expect(
        pending == null,
        [
          'insufficient-balance',
          'already-owned',
          'pass-season-changed',
        ].contains(code),
      );
    });
  }
  for (final field in [
    'ok',
    'purchased',
    'idempotent',
    'itemId',
    'seasonId',
    'currentSeasonId',
    'passActive',
    'transactionId',
    'grant',
    'state',
  ]) {
    test('missing $field cannot acknowledge the pending purchase', () async {
      final store = await storeFor();
      await store.stagePassPremiumPurchase('first', original);
      final result = confirmation()..remove(field);
      final service = serviceFor(
        store,
        (_) async => http.Response(jsonEncode(result), 200),
      );
      await service.start();
      await expectLater(
        service.purchaseSoftItem('pass:premium'),
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
      expect(
        (await store.pendingPassPremiumPurchase('first'))?.requestId,
        'original',
      );
    });
  }
  for (final corruption in [
    'grant',
    'active',
    'period',
    'ownership',
    'gems',
    'season',
  ]) {
    test('$corruption mismatch fails strict current-state validation', () {
      final result = confirmation();
      switch (corruption) {
        case 'grant':
          result['grant'] = {'kind': 'piece_set', 'id': 'premium'};
        case 'active':
          result['passActive'] = false;
        case 'period':
          ((result['state'] as Map)['economy'] as Map)['periods'] = {
            'seasonId': 's7',
          };
        case 'ownership':
          ((result['state'] as Map)['passState'] as Map)['premium'] = false;
        case 'gems':
          (result['state'] as Map)['gems'] = -1;
        case 'season':
          result['seasonId'] = 's7';
      }
      expect(
        () => validatePassPremiumPurchaseResult(result, 's6'),
        throwsFormatException,
      );
    });
  }
  test('late response cannot acknowledge the departed account', () async {
    final store = await storeFor(),
        auth = TestAuth(),
        entered = Completer<void>(),
        response = Completer<http.Response>();
    await store.stagePassPremiumPurchase('first', original);
    final service = serviceFor(store, (_) async {
      entered.complete();
      return response.future;
    }, auth: auth);
    await service.start();
    final result = service.purchaseSoftItem('pass:premium');
    final assertion = expectLater(
      result,
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
    response.complete(http.Response(jsonEncode(confirmation()), 200));
    await assertion;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(journalKey('first')), contains('original'));
    expect(await store.pendingPassPremiumPurchase('second'), isNull);
    expect(store.data.premium, false);
  });

  for (final premiumScreen in [false, true]) {
    for (final scenario in ['account', 'signout', 'covered']) {
      testWidgets(
        '${premiumScreen ? 'Premium' : 'Pass'} late confirmation respects $scenario boundary',
        (tester) async {
          final store = await storeFor(),
              auth = TestAuth(),
              response = Completer<http.Response>();
          await store.stagePassPremiumPurchase('first', original);
          var calls = 0;
          final service = serviceFor(store, (request) async {
            if (!premiumScreen &&
                request.url.path.endsWith('/getPlayerState')) {
              return http.Response(
                jsonEncode({'ok': true, 'state': passState('s6')}),
                200,
              );
            }
            calls++;
            return response.future;
          }, auth: auth);
          await service.start();
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: LunoTheme.dark,
              home:
                  premiumScreen
                      ? LunoPremiumScreen(online: service, playerStore: store)
                      : PassScreen(online: service, playerStore: store),
            ),
          );
          // Keep the status request in flight; settling a loading spinner would
          // advance virtual time through its timeout before the owner changes.
          await tester.pump(const Duration(milliseconds: 100));
          final tile = find.byKey(const ValueKey('pending-pass-premium'));
          if (premiumScreen) {
            expect(tile, findsNothing);
            expect(
              calls,
              1,
              reason: 'Membership reads only its server status.',
            );
            if (scenario == 'account') {
              auth.currentUser = TestUser('second');
              await store.bindAccount('second');
            } else if (scenario == 'signout') {
              auth.currentUser = null;
              await store.bindAccount(null);
            } else {
              unawaited(
                navigator.currentState!.push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => const Scaffold(body: Text('Covered screen')),
                  ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 400));
            }
            response.complete(
              http.Response(
                jsonEncode({
                  'ok': true,
                  'state': {
                    'gold': 777,
                    'membership': {'active': true, 'expiresAt': 2000000000000},
                  },
                }),
                200,
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pumpAndSettle();
            expect(store.data.gold, isNot(777));
            final prefs = await SharedPreferences.getInstance();
            expect(prefs.getString(journalKey('first')), contains('original'));
            expect(find.byType(SnackBar), findsNothing);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 2));
            expect(
              calls,
              1,
              reason: 'Departed status read must not dispatch another request.',
            );
            expect(tester.takeException(), isNull);
            return;
          }
          final retry = find.descendant(
            of: tile,
            matching: find.byType(LunoButton),
          );
          tester.widget<LunoButton>(retry).onPressed!();
          await tester.pump(const Duration(milliseconds: 100));
          expect(calls, 1);
          if (scenario == 'account') {
            auth.currentUser = TestUser('second');
            await store.bindAccount('second');
          } else if (scenario == 'signout') {
            auth.currentUser = null;
            await store.bindAccount(null);
          } else {
            unawaited(
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Covered screen')),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
          }
          final result = confirmation();
          (result['state'] as Map)['gold'] = 777;
          response.complete(http.Response(jsonEncode(result), 200));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(store.data.gold, scenario == 'covered' ? 777 : isNot(777));
          expect(find.byType(SnackBar), findsNothing);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString(journalKey('first')),
            scenario == 'covered' ? isNull : contains('original'),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final english in [false, true]) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(800, 1280),
      ]) {
        testWidgets(
          '${premiumScreen ? 'Premium' : 'Pass'} recovery at $size ${english ? 'en' : 'tr'} 1.8 scaling',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final store = await storeFor();
            store.applyServerState(passState('s6', premium: true));
            await store.stagePassPremiumPurchase('first', original);
            var calls = 0;
            final service = serviceFor(store, (request) async {
              if (request.url.path.endsWith('/getPlayerState')) {
                return http.Response(
                  jsonEncode({
                    'ok': true,
                    'state': {
                      ...passState('s6', premium: true),
                      'membership': {'active': false, 'expiresAt': 0},
                    },
                  }),
                  200,
                );
              }
              calls++;
              expect(request.headers['X-Luno-Request-Id'], 'original');
              return http.Response(
                jsonEncode(confirmation(expired: true)),
                200,
              );
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
                home:
                    premiumScreen
                        ? LunoPremiumScreen(online: service, playerStore: store)
                        : PassScreen(online: service, playerStore: store),
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pumpAndSettle();
            final tile = find.byKey(const ValueKey('pending-pass-premium'));
            if (premiumScreen) {
              expect(tile, findsNothing);
              expect(
                find.byKey(const ValueKey('membership-status')),
                findsOneWidget,
              );
              final distinction = find.byKey(
                const ValueKey('membership-not-pass'),
              );
              await tester.scrollUntilVisible(
                distinction,
                250,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              final bounds = tester.getRect(distinction);
              expect(bounds.left, greaterThanOrEqualTo(0));
              expect(bounds.right, lessThanOrEqualTo(size.width));
              expect(bounds.bottom, lessThanOrEqualTo(size.height));
              expect(store.data.premium, true);
              expect(store.data.isMembershipActive, false);
              expect(
                calls,
                0,
                reason: 'Membership must not retry a seasonal Pass purchase.',
              );
              expect(
                (await store.pendingPassPremiumPurchase('first'))?.requestId,
                'original',
              );
              expect(tester.takeException(), isNull);
              return;
            }
            expect(tile, findsOneWidget);
            expect(
              find.text(
                english
                    ? 'Confirm your pending Premium purchase.'
                    : 'Bekleyen Premium alımını doğrula.',
              ),
              findsOneWidget,
            );
            final retry = find.descendant(
              of: tile,
              matching: find.byType(LunoButton),
            );
            await tester.ensureVisible(retry);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(retry);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(bounds.bottom, lessThanOrEqualTo(size.height));
            final button = tester.widget<LunoButton>(retry);
            expect(
              button.onPressed,
              isNotNull,
              reason:
                  'Recovery remains reachable with zero gems and existing ownership.',
            );
            await tester.tap(retry);
            button.onPressed!();
            await tester.runAsync(() async {
              final prefs = await SharedPreferences.getInstance();
              for (
                var i = 0;
                i < 50 && prefs.getString(journalKey('first')) != null;
                i++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 20));
              }
              await Future<void>.delayed(const Duration(milliseconds: 30));
            });
            await tester.pumpAndSettle();
            expect(calls, 1);
            expect(await store.pendingPassPremiumPurchase('first'), isNull);
            expect(store.data.premium, false);
            expect(tile, findsNothing);
            expect(
              find.text(
                english
                    ? 'Your previous-season Premium purchase is confirmed. The new season was not activated.'
                    : 'Önceki sezonun Premium alımı doğrulandı. Yeni sezon etkinleştirilmedi.',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    testWidgets(
      '${premiumScreen ? 'Premium' : 'Pass'} recovery disappears on account departure',
      (tester) async {
        final store = await storeFor();
        await store.stagePassPremiumPurchase('first', original);
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home:
                premiumScreen
                    ? LunoPremiumScreen(playerStore: store)
                    : PassScreen(playerStore: store),
          ),
        );
        await tester.pumpAndSettle();
        final tile = find.byKey(const ValueKey('pending-pass-premium'));
        expect(tile, premiumScreen ? findsNothing : findsOneWidget);
        await store.bindAccount('second');
        await tester.pump();
        expect(tile, findsNothing);
        await tester.pumpAndSettle();
        expect(tile, findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(journalKey('first')), contains('original'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
