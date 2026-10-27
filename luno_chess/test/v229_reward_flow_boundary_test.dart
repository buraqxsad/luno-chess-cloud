import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/data/pass_purchase.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/pass_purchase_recovery.dart';

import 'battle_deck_account_test.dart' as deck_fixture;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth, TestUser;

const _purchase = PassPremiumPurchase(
  seasonId: 's6',
  requestId: 'v229-premium',
);
const _item = 'piece_set:roma';
const _flows = ['shop-daily', 'pass-claim', 'pass-premium', 'pass-chest'];
const _recoveries = ['shop-chest', 'shop-item', 'pass-chest', 'pass-premium'];

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

http.Response _confirmed(String flow) => _json({
  'ok': true,
  if (flow == 'shop-daily') ...{
    'granted': true,
    'reward': {'gold': 120},
  },
  if (flow == 'pass-claim') 'granted': true,
  if (flow == 'pass-premium') 'purchased': true,
  if (flow == 'pass-chest') ...{'opened': false, 'rewards': []},
  'state': {
    'gold': 777,
    'passState': {
      'level': 1,
      'xp': 0,
      'premium': flow == 'pass-premium',
      'claimed': {
        'free': {if (flow == 'pass-claim') '1': 1700000000001},
        'premium': <String, dynamic>{},
      },
    },
  },
});

GameStore _store([String owner = 'first']) {
  final store =
      GameStore.createForTesting()
        ..loaded = true
        ..accountUid = owner;
  store.data.gold = 1234;
  store.data.gems = 9999;
  store.data.passXp = 250;
  store.data.pendingChests = ['common'];
  addTearDown(store.dispose);
  return store;
}

LunoOnlineService _service(
  Future<http.Response> Function(http.Request) respond, {
  GameStore? store,
  TestAuth? auth,
  VoidCallback? onDeckRead,
}) {
  final service = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: auth ?? TestAuth(),
    playerStore: store,
    appCheck: () async => 'v229-local-test',
    client: MockClient((request) async {
      if (request.url.path.endsWith('/getBattleV1Deck')) {
        onDeckRead?.call();
        return _json(deck_fixture.response());
      }
      return respond(request);
    }),
  );
  addTearDown(service.dispose);
  return service;
}

Widget _app(Widget home, {GlobalKey<NavigatorState>? navigator}) => MaterialApp(
  navigatorKey: navigator,
  theme: LunoTheme.dark,
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
  home: home,
);

Widget _screen(String flow, GameStore store, LunoOnlineService online) =>
    flow == 'shop-daily'
        ? ShopScreen(
          key: const ValueKey('v229-screen'),
          playerStore: store,
          online: online,
        )
        : PassScreen(
          key: const ValueKey('v229-screen'),
          playerStore: store,
          online: online,
        );

VoidCallback _callback(WidgetTester tester, String flow) {
  if (flow == 'shop-daily') {
    return tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'AL'))
        .onPressed!;
  }
  if (flow == 'pass-chest') {
    return tester
        .widget<FilledButton>(
          find.descendant(
            of: find.byKey(const ValueKey('pending-pass-chest')),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed!;
  }
  final button =
      flow == 'pass-claim'
          ? find.byKey(const ValueKey('pass-claim-free-1'))
          : find.byWidgetPredicate(
            (widget) =>
                widget is LunoButton && widget.label.contains('PREMIUM AL'),
          );
  return tester.widget<LunoButton>(button.first).onPressed!;
}

Finder _recoveryTile(String kind) => find.byKey(
  ValueKey(switch (kind) {
    'shop-chest' => 'pending-shop-chest',
    'shop-item' => 'pending-permanent-purchase',
    'pass-chest' => 'pending-pass-chest',
    _ => 'pending-pass-premium',
  }),
);

Widget _recoveryScreen(
  String kind,
  GameStore store,
  LunoOnlineService online, {
  VoidCallback? onRetry,
}) {
  if (kind == 'pass-premium') {
    return Scaffold(
      body: PassPurchaseRecoveryTile(
        store: store,
        busy: false,
        enabled: true,
        onRetry: onRetry ?? () {},
      ),
    );
  }
  return kind.startsWith('shop')
      ? ShopScreen(playerStore: store, online: online)
      : PassScreen(playerStore: store, online: online);
}

Future<void> _stage(GameStore store, String kind) async {
  switch (kind) {
    case 'shop-chest':
      await store.stageShopChestRequest('first', 'rare', 'v229-shop-chest');
    case 'shop-item':
      await store.stagePermanentPurchase('first', _item, 'v229-shop-item');
    case 'pass-chest':
      await store.stagePassChestRequest('first', 'common', 'v229-pass-chest');
    case 'pass-premium':
      await store.stagePassPremiumPurchase('first', _purchase);
  }
}

Future<void> _clear(GameStore store, String kind) async {
  switch (kind) {
    case 'shop-chest':
      await store.clearShopChestRequest('first', 'rare', 'v229-shop-chest');
    case 'shop-item':
      await store.clearPermanentPurchase('first', _item, 'v229-shop-item');
    case 'pass-chest':
      await store.clearPassChestRequest('first', 'common', 'v229-pass-chest');
    case 'pass-premium':
      await store.clearPassPremiumPurchase('first', _purchase);
  }
}

Future<void> _expectPending(GameStore store, String kind, bool pending) async {
  switch (kind) {
    case 'shop-chest':
      expect(
        await store.pendingShopChestRequestKinds('first'),
        pending ? ['rare'] : isEmpty,
      );
    case 'shop-item':
      expect(
        await store.pendingPermanentPurchaseItems('first'),
        pending ? [_item] : isEmpty,
      );
    case 'pass-chest':
      expect(
        await store.pendingPassChestRequestKinds('first'),
        pending ? ['common'] : isEmpty,
      );
    case 'pass-premium':
      expect(
        (await store.pendingPassPremiumPurchase('first'))?.requestId,
        pending ? _purchase.requestId : isNull,
      );
  }
}

void _noFeedback(WidgetTester tester) {
  expect(find.byType(SnackBar), findsNothing);
  expect(find.byType(ShopRewardDialog), findsNothing);
  expect(find.byType(ChestRevealDialog), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final flow in _flows) {
    for (final boundary in [
      'covered',
      'paused',
      'store-replaced',
      'service-replaced',
    ]) {
      for (final fails in [false, true]) {
        testWidgets('$flow $boundary completion: failure=$fails', (
          tester,
        ) async {
          final store = _store();
          final response = Completer<http.Response>();
          var mutations = 0;
          final online = _service((request) async {
            if (request.url.path.endsWith('/getPlayerState')) {
              return _json({'ok': true, 'state': <String, dynamic>{}});
            }
            mutations++;
            return response.future;
          });
          await online.start();
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            _app(_screen(flow, store, online), navigator: navigator),
          );
          await tester.pumpAndSettle();
          final originalState = tester.state(
            find.byKey(const ValueKey('v229-screen')),
          );
          final callback = _callback(tester, flow);
          callback();
          callback();
          await tester.pump(const Duration(milliseconds: 100));
          expect(mutations, 1);
          expect(store.data.gold, 1234);
          expect(store.data.gems, 9999);
          expect(store.data.premium, isFalse);
          expect(store.data.passFreeClaimed, isEmpty);
          expect(store.data.pendingChests, ['common']);

          GameStore? replacement;
          if (boundary == 'covered') {
            unawaited(
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Covered route')),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
          } else if (boundary == 'paused') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            await tester.pump();
          } else {
            replacement =
                boundary == 'store-replaced' ? _store('second') : store;
            final next =
                boundary == 'store-replaced'
                    ? online
                    : _service(
                      (_) async =>
                          _json({'ok': true, 'state': <String, dynamic>{}}),
                      auth: TestAuth()..currentUser = TestUser('first'),
                    );
            await next.start();
            await tester.pumpWidget(
              _app(_screen(flow, replacement, next), navigator: navigator),
            );
            expect(
              tester.state(find.byKey(const ValueKey('v229-screen'))),
              same(originalState),
              reason: 'Exercise dependency replacement, not screen disposal.',
            );
            await tester.pump(const Duration(milliseconds: 100));
          }

          response.complete(
            fails
                ? _json({'ok': false, 'error': 'request-in-progress'}, 409)
                : _confirmed(flow),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (boundary == 'paused') {
            _noFeedback(tester);
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
          await tester.pumpAndSettle();
          expect(
            store.data.gold,
            !fails && !boundary.endsWith('replaced') ? 777 : 1234,
          );
          if (replacement != null) expect(replacement.data.gold, 1234);
          expect(mutations, 1);
          _noFeedback(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
      }
    }
  }

  for (final flow in ['shop-daily', 'pass-claim']) {
    testWidgets('$flow disposed completion does not present or redispatch', (
      tester,
    ) async {
      final store = _store();
      final response = Completer<http.Response>();
      var mutations = 0;
      final online = _service((request) async {
        if (request.url.path.endsWith('/getPlayerState')) {
          return _json({'ok': true, 'state': <String, dynamic>{}});
        }
        mutations++;
        return response.future;
      });
      await online.start();
      await tester.pumpWidget(_app(_screen(flow, store, online)));
      await tester.pumpAndSettle();
      _callback(tester, flow)();
      await tester.pump(const Duration(milliseconds: 100));
      expect(mutations, 1);
      await tester.pumpWidget(const SizedBox());
      response.complete(_confirmed(flow));
      await tester.pumpAndSettle();
      expect(mutations, 1);
      _noFeedback(tester);
    });

    for (final boundary in ['paused', 'disposed']) {
      testWidgets('$flow entry wait cannot dispatch after $boundary', (
        tester,
      ) async {
        final store = _store();
        final entry = Completer<http.Response>();
        var mutations = 0;
        var deckReads = 0;
        final online = _service((request) async {
          if (request.url.path.endsWith('/getPlayerState')) return entry.future;
          mutations++;
          return _confirmed(flow);
        }, onDeckRead: () => deckReads++);
        await online.start();
        await tester.pumpWidget(_app(_screen(flow, store, online)));
        await tester.pump(const Duration(milliseconds: 100));
        _callback(tester, flow)();
        await tester.pump();
        expect(mutations, 0);
        if (boundary == 'paused') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        entry.complete(_json({'ok': true, 'state': <String, dynamic>{}}));
        await tester.pump(const Duration(milliseconds: 100));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(mutations, 0);
        expect(deckReads, 0);
        expect(store.data.gold, 1234);
        _noFeedback(tester);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final kind in _recoveries) {
    for (final initiallyPending in [false, true]) {
      testWidgets(
        '$kind refreshes its receipt cache after A-B-A: pending=$initiallyPending',
        (tester) async {
          final store = GameStore.createForTesting();
          addTearDown(store.dispose);
          await store.bindAccount('first');
          store.data.pendingChests = [];
          if (initiallyPending) await _stage(store, kind);
          final online = _service(
            (_) async => _json({'ok': true, 'state': <String, dynamic>{}}),
          );
          await online.start();
          await tester.pumpWidget(_app(_recoveryScreen(kind, store, online)));
          await tester.pumpAndSettle();
          expect(
            _recoveryTile(kind),
            initiallyPending ? findsOneWidget : findsNothing,
          );
          final revision = store.accountBindingRevision;

          // Deliberately do not pump between bindings: the UID is identical at
          // the next frame, but the receipt snapshot belongs to an older binding.
          await store.bindAccount('second');
          await store.bindAccount('first');
          store.data.pendingChests = [];
          if (initiallyPending) {
            await _clear(store, kind);
          } else {
            await _stage(store, kind);
          }
          expect(store.accountBindingRevision, greaterThan(revision));
          await _expectPending(store, kind, !initiallyPending);
          await tester.pumpAndSettle();
          expect(
            _recoveryTile(kind),
            initiallyPending ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('$kind old retry callback cannot follow an A-B-A binding', (
      tester,
    ) async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('first');
      store.data.pendingChests = [];
      await _stage(store, kind);
      var retries = 0;
      var mutations = 0;
      final online = _service((request) async {
        if (request.url.path.endsWith('/getPlayerState')) {
          return _json({'ok': true, 'state': <String, dynamic>{}});
        }
        mutations++;
        return _json({'ok': false, 'error': 'request-in-progress'}, 409);
      }, store: store);
      await online.start();
      await tester.pumpWidget(
        _app(_recoveryScreen(kind, store, online, onRetry: () => retries++)),
      );
      await tester.pumpAndSettle();
      final button = find.descendant(
        of: _recoveryTile(kind),
        matching:
            kind == 'pass-chest'
                ? find.byType(FilledButton)
                : find.byType(LunoButton),
      );
      final stale =
          kind == 'pass-chest'
              ? tester.widget<FilledButton>(button).onPressed!
              : tester.widget<LunoButton>(button).onPressed!;
      await store.bindAccount('second');
      await store.bindAccount('first');
      store.data.pendingChests = [];
      stale();
      stale();
      await tester.pumpAndSettle();
      expect(mutations, 0);
      expect(retries, 0);
      await _expectPending(store, kind, true);
      expect(_recoveryTile(kind), findsOneWidget);
      _noFeedback(tester);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
