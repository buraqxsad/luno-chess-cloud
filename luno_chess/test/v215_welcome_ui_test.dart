import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'online_request_session_test.dart' show TestAuth;
import 'v214_first_match_ui_test.dart' show resign, settleRoute;

Map<String, dynamic> welcome() => {
  'ok': true,
  'granted': true,
  'idempotent': false,
  'welcome': {
    'version': 1,
    'claimed': true,
    'card': 'mine',
    'eligibility': 'account_welcome',
  },
  'reward': {'gold': 500},
  'state': {'gold': 1234},
};

void main() {
  setupPracticeTestAssets();
  for (final transition in ['confirm', 'rematch', 'account', 'timeout']) {
    testWidgets('welcome reply respects $transition and duplicate taps', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = GameStore.instance;
      store
        ..accountUid = 'first'
        ..data = PlayerData.initial()
        ..loaded = true
        ..hasCompletedTutorial = true
        ..hasChosenUsername = true
        ..firstSessionMatchesStarted = 0;
      final beforeGold = store.data.gold;
      final pending = Completer<http.Response>();
      var claims = 0, reads = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/claimOnboardingReward')) {
          claims++;
          return pending.future;
        }
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          reads++;
          return http.Response(
            jsonEncode(
              response(
                owned: [...starterDeck.map((card) => card.wire), 'mine'],
              ),
            ),
            200,
          );
        }
        throw StateError('Unexpected endpoint ${request.url.path}');
      });
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        client: client,
        appCheck: () async => 'check',
      );
      await tester.runAsync(online.start);
      await tester.runAsync(online.getBattleV1Deck);
      reads = 0;
      addTearDown(online.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        shell(
          BattleV1Screen(rewardOnline: online, deckOnline: online),
          scale: 1.5,
          reduced: true,
        ),
      );
      await settleRoute(tester);
      await resign(tester);
      final claim = find.byKey(const ValueKey('claim-welcome-reward'));
      await tester.ensureVisible(claim);
      final callback = tester.widget<BattleCommand>(claim).onPressed!;
      callback();
      callback();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(claims, 1);
      if (transition == 'rematch') {
        tester
            .widget<BattleCommand>(find.byKey(const ValueKey('local-rematch')))
            .onPressed!();
      } else if (transition == 'account') {
        store.accountUid = 'second';
      } else if (transition == 'timeout') {
        await tester.pump(const Duration(seconds: 16));
      }
      pending.complete(http.Response(jsonEncode(welcome()), 200));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      if (transition == 'confirm') {
        expect(store.data.gold, 1234);
        expect(reads, 1);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is BattleCardArt && widget.card == CardId.mine,
          ),
          findsOneWidget,
        );
        expect(claim, findsNothing);
      } else {
        expect(reads, 0);
        expect(store.data.gold, beforeGold);
        if (transition == 'timeout') {
          expect(tester.widget<BattleCommand>(claim).onPressed, isNotNull);
          expect(find.textContaining('Bağlanınca tekrar'), findsOneWidget);
        }
      }
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.save);
    });
  }
}
