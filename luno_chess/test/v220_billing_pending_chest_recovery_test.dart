import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/chest_odds.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_deck_account_test.dart' as deck_fixture;
import 'online_request_session_test.dart' show TestAuth;
import 'v220_billing_odds_fixture.dart';

Map<String, dynamic> completeState() {
  final fixture = (jsonDecode(v220ChestOddsFixturesJson) as List).firstWhere(
    (fixture) => fixture['name'] == 'complete',
  );
  final state = v220ChestState('first');
  state['inventory'] = fixture['inventory'];
  state['gold'] = 1000;
  state['gems'] = 0;
  for (final chest in (state['shopChests'] as Map).values) {
    chest['canPurchase'] = false;
  }
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<GameStore> storeFor() async {
    final store = GameStore.createForTesting();
    await store.bindAccount('first');
    addTearDown(store.dispose);
    return store;
  }

  test(
    'recovery-only staging cannot create a fresh journal after old receipt is cleared',
    () async {
      final store = await storeFor();
      await store.stageShopChestRequest('first', 'royal', 'original-accepted');
      expect(
        await store.stageShopChestRequest(
          'first',
          'royal',
          'unused',
          requireExisting: true,
        ),
        'original-accepted',
      );
      await store.clearShopChestRequest('first', 'royal', 'original-accepted');
      await expectLater(
        store.stageShopChestRequest(
          'first',
          'royal',
          'fresh-debit',
          requireExisting: true,
        ),
        throwsStateError,
      );
      expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
    },
  );
  test(
    'recovery transport without a journal sends no openChest request',
    () async {
      final store = await storeFor();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'test-only',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await expectLater(
        online.openChest('royal', recoverPendingOnly: true),
        throwsStateError,
      );
      expect(requests, 0);
      expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
    },
  );
  testWidgets(
    'already fulfilled pending chest recovers original receipt with exhausted collection and zero gems',
    (tester) async {
      final store = await storeFor();
      await store.stageShopChestRequest('first', 'royal', 'original-accepted');
      final state = completeState();
      expect(ChestOdds.fromPlayerState('royal', state).canPurchase, false);
      final ids = <String>[];
      var serverDebits = 1; // The original timed-out request already committed.
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        playerStore: store,
        appCheck: () async => 'test-only',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/getPlayerState')) {
            return http.Response(jsonEncode({'ok': true, 'state': state}), 200);
          }
          if (request.url.path.endsWith('/getBattleV1Deck')) {
            return http.Response(jsonEncode(deck_fixture.response()), 200);
          }
          expect(request.url.path.endsWith('/openChest'), true);
          final id = request.headers['X-Luno-Request-Id']!;
          ids.add(id);
          if (id != 'original-accepted') serverDebits++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'opened': false,
              'idempotent': true,
              'chestId': 'royal',
              'transactionId': 'original-purchase',
              'rewardTransactionIds': ['original-reward'],
              'state': state,
              'rewards': [
                {'type': 'gold', 'amount': 1000},
                {
                  'type': 'frame_shard',
                  'id': 'rainbow',
                  'amount': 1,
                  'rarity': 'mythic',
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: ShopScreen(online: online, playerStore: store),
        ),
      );
      await tester.pumpAndSettle();
      final retry = find.descendant(
        of: find.byKey(const ValueKey('pending-shop-chest')),
        matching: find.byType(LunoButton),
      );
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      final callback = tester.widget<LunoButton>(retry).onPressed!;
      callback();
      callback();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(ids, ['original-accepted']);
      expect(serverDebits, 1);
      expect(store.data.gems, 0);
      expect(store.data.gold, 1000);
      expect(find.byKey(const ValueKey('chest-odds-dialog')), findsNothing);
      expect(find.byType(ChestRevealDialog), findsOneWidget);
      expect(await store.pendingShopChestRequestKinds('first'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
