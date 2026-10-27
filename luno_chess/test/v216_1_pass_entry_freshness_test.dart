import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/data/pass.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  setupPracticeTestAssets();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Pass free 4 waits for entry state and keeps its confirmed reward',
      (tester) async {
    const initialGold = 20000;
    const confirmedGold = initialGold + 180;
    const claimedAt = 1700000000001;
    final initialState = <String, dynamic>{
      'gold': initialGold,
      'economy': {
        'periods': {'seasonNumber': 1, 'seasonEndAt': 2000000000000},
      },
      'inventory': {'ownedEmojis': ['smile']},
      'passState': {
        'level': 4,
        'xp': 0,
        'premium': false,
        'rewardVersion': 1,
        'unlocks': <String>[],
        'claimed': {'free': <String, dynamic>{}, 'premium': <String, dynamic>{}},
      },
    };
    final confirmedState = <String, dynamic>{
      ...initialState,
      'gold': confirmedGold,
      'inventory': {'ownedEmojis': ['smile', 'laugh']},
      'passState': {
        'level': 4,
        'xp': 0,
        'premium': false,
        'rewardVersion': 1,
        'unlocks': ['emoji:laugh'],
        'claimed': {'free': {'4': claimedAt}, 'premium': <String, dynamic>{}},
      },
    };
    http.Response response(Map<String, dynamic> body) => http.Response(
      jsonEncode(body), 200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final entryResponse = Completer<http.Response>();
    final claimResponse = Completer<http.Response>();
    final calls = <String>[];
    Map<String, dynamic>? claimBody;
    final store = GameStore.createForTesting();
    await store.bindAccount('first');
    store.data.gold = initialGold;
    store.data.passXp = 4 * kPassXpPerLevel;
    addTearDown(store.dispose);

    // Match the acquisition fixture's injected store, without service binding.
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      appCheck: () async => 'local-test-only',
      client: MockClient((request) async {
        final path = request.url.path.split('/').last;
        calls.add(path);
        switch (path) {
          case 'getPlayerState':
            return entryResponse.future;
          case 'claimPassReward':
            claimBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
            return claimResponse.future;
          default:
            throw StateError('Unexpected request: $path');
        }
      }),
    );
    await online.start();
    addTearDown(online.dispose);
    addTearDown(() async {
      if (!entryResponse.isCompleted) {
        entryResponse.complete(response({'ok': true, 'state': initialState}));
      }
      if (!claimResponse.isCompleted) {
        claimResponse.complete(response({
          'ok': true, 'granted': true,
          'content': {'kind': 'emoji', 'id': 'laugh', 'duplicate': false},
          'state': confirmedState,
        }));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(shell(
      PassScreen(online: online, playerStore: store),
      language: 'en', reduced: true,
    ));
    await tester.pumpAndSettle();
    expect(calls, ['getPlayerState']);

    final claimButton = find.byKey(const ValueKey('pass-claim-free-4'));
    await tester.scrollUntilVisible(claimButton, 350,
      scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(claimButton);
    await tester.pumpAndSettle();
    expect(tester.widget<LunoButton>(claimButton).onPressed, isNotNull);
    await tester.tap(claimButton);
    await tester.pump(const Duration(milliseconds: 100));
    expect(entryResponse.isCompleted, isFalse);
    expect(calls, ['getPlayerState'],
      reason: 'The claim must wait for the held entry refresh.');
    expect(store.data.gold, initialGold);
    expect(store.data.ownedEmojis, isNot(contains('laugh')));
    expect(store.data.passFreeClaimed, isNot(contains(4)));

    entryResponse.complete(response({'ok': true, 'state': initialState}));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(calls, ['getPlayerState', 'claimPassReward']);
    expect(claimBody, containsPair('level', 4));
    expect(claimBody, containsPair('track', 'free'));
    expect(store.data.gold, initialGold);
    expect(store.data.ownedEmojis, isNot(contains('laugh')));
    expect(store.data.passFreeClaimed, isNot(contains(4)));

    claimResponse.complete(response({
      'ok': true,
      'granted': true,
      'content': {'kind': 'emoji', 'id': 'laugh', 'duplicate': false},
      'reward': {'gold': 180},
      'state': confirmedState,
    }));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    final dialog = find.byType(ShopRewardDialog);
    expect(dialog, findsOneWidget);
    expect(tester.widget<ShopRewardDialog>(dialog).emoteId, 'laugh');

    void expectConfirmedReward() {
      expect(store.data.gold, confirmedGold);
      expect(store.data.ownedEmojis, contains('laugh'));
      expect(store.data.passFreeClaimed, contains(4));
      expect(store.data.passUnlocks, contains('emoji:laugh'));
      expect(store.canClaimPassFree(4), isFalse);
    }
    expectConfirmedReward();
    await tester.tap(find.byKey(const ValueKey('shop-reward-action')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expectConfirmedReward();
    await tester.pump(const Duration(seconds: 1));
    expectConfirmedReward();
    expect(calls, ['getPlayerState', 'claimPassReward']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Pass entry deadline releases retry and rejects the old read', (tester) async {
    final store = GameStore.createForTesting();
    await store.bindAccount('first');
    store.data.gold = 20000;
    store.data.passXp = 4 * kPassXpPerLevel;
    final bootstrap = Completer<void>();
    final oldRead = Completer<http.Response>();
    var reads = 0;
    var claims = 0;
    Map<String, dynamic> state(int gold, {bool claimed = false}) => {
      'gold': gold,
      'economy': {'periods': {'seasonNumber': 1, 'seasonEndAt': 2000000000000}},
      'inventory': {'ownedEmojis': ['smile']},
      'passState': {
        'level': 4, 'xp': 0, 'premium': false, 'rewardVersion': 1,
        'claimed': {'free': {if (claimed) '1': 1700000000001}, 'premium': {}},
      },
    };
    http.Response response(Map<String, dynamic> body) => http.Response(jsonEncode(body), 200);
    final online = LunoOnlineService.forTesting(
      bootstrap: () => bootstrap.future, auth: TestAuth(),
      appCheck: () async => 'local-test-only',
      client: MockClient((request) async {
        if (request.url.path.endsWith('getPlayerState')) {
          reads++;
          return reads == 1 ? oldRead.future : response({'ok': true, 'state': state(21000)});
        }
        if (request.url.path.endsWith('claimPassReward')) {
          claims++;
          return response({'ok': true, 'granted': true, 'state': state(22250, claimed: true)});
        }
        throw StateError('Unexpected request: ${request.url.path}');
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      if (!bootstrap.isCompleted) bootstrap.complete();
      if (!oldRead.isCompleted) oldRead.complete(response({'ok': true, 'state': state(20000)}));
      await tester.pump();
      online.dispose();
      store.dispose();
    });
    await tester.pumpWidget(shell(PassScreen(online: online, playerStore: store),
        language: 'en', reduced: true));
    final claim = find.byKey(const ValueKey('pass-claim-free-1'));
    await tester.scrollUntilVisible(claim, 150, scrollable: find.byType(Scrollable).first);
    tester.widget<LunoButton>(claim).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    bootstrap.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.widget<LunoButton>(claim).onPressed, isNotNull);
    expect(claims, 0);
    expect(store.data.gold, 20000);
    tester.widget<LunoButton>(claim).onPressed!();
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(claims, 1);
    expect(store.data.gold, 22250);
    expect(store.data.passFreeClaimed, contains(1));
    oldRead.complete(response({'ok': true, 'state': state(20000)}));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.data.gold, 22250);
    expect(store.data.passFreeClaimed, contains(1));
    expect(tester.takeException(), isNull);
  });
}
