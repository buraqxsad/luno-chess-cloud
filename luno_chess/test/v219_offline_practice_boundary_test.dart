import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_deck_account_test.dart' show app;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth;
import 'v217_player_journey_support.dart' show journeyAwait, journeyPump;

void main() {
  setupPracticeTestAssets();
  final store = GameStore.instance;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await store.load();
  });

  for (final language in ['tr', 'en']) {
    testWidgets('account-free practice starts and resigns without economic '
        'or first-match progression: $language', (tester) async {
      await journeyAwait(tester, () => store.bindAccount(null));
      store
        ..hasCompletedTutorial = true
        ..firstSessionMatchesStarted = 0;
      final before = Map<String, dynamic>.from(store.data.toJson());
      final trophies = store.rankTrophies;
      final phase = store.firstSessionPhase;
      var bootstraps = 0, requests = 0;
      final auth = TestAuth()..currentUser = null;
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {
          bootstraps++;
          throw StateError('Test transport is offline');
        },
        client: MockClient((_) async {
          requests++;
          throw StateError('Practice must not submit an HTTP request');
        }),
        appCheck: () async => null,
      );
      addTearDown(online.dispose);

      await tester.pumpWidget(
        app(
          BattleV1Screen(
            practiceStage: 0,
            practiceCanExit: true,
            deckOnline: online,
            rewardOnline: online,
          ),
          language,
        ),
      );
      await journeyPump(tester);
      final dynamic state = tester.state(find.byType(BattleV1Screen));
      expect(state.localSession, isNotNull);
      expect(state.localSession.practice, isTrue);
      expect(state.controller, isNull);
      expect(state.loadError, isNull);
      expect(store.accountUid, isNull);
      expect(bootstraps, 0);
      expect(requests, 0);

      state.localSession.resign();
      await journeyPump(tester);
      expect(state.localSession.terminal, isNotNull);
      expect(store.data.toJson(), before);
      expect(store.rankTrophies, trophies);
      expect(store.firstSessionPhase, phase);
      expect(find.byKey(const ValueKey('claim-welcome-reward')), findsNothing);
      expect(bootstraps, 0);
      expect(requests, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await journeyAwait(tester, store.flush);
    });
  }
}
