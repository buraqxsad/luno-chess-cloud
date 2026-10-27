import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/navigation/luno_route.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'helpers/live_onboarding_driver.dart';
import 'v217_player_journey_support.dart';

void main() {
  setupPracticeTestAssets();
  setUp(() async {
    await SharedPreferences.getInstance();
    await LunoSettings.instance.load();
    await LunoSettings.instance.setLanguage(LunoSettings.languageEnglish);
  });
  final store = GameStore.instance;
  setUpAll(store.load);

  testWidgets('fresh/resumed welcome -> one guided match -> username -> Home -> '
      'recovered welcome reward -> main routes -> persisted reopen', (tester) async {
    for (final tutorial in ['fresh', 'resume']) {
      journeyViewport(tester);
      try {
        await journeyAwait(tester, () async {
          await store.bindAccount('journey-unused-$tutorial');
          await store.bindAccount('v217-journey-$tutorial');
        });
        // The preferences fixture is reset per test. Binding through a distinct
        // account exercises the real fresh-account transition on the singleton.
        expect(store.hasCompletedTutorial, isFalse);
        expect(store.hasChosenUsername, isFalse);
        expect(store.firstSessionPhase, 'none');
        expect(store.welcomeStep, 0);
        final initialGold = store.data.gold;
        final initialPlayer = store.data.toJson();
        final initialRank = (store.rankTrophies, store.rankArenaIdx);
        await tester.pumpWidget(const LunoAppShell());
        await showLiveOnboarding(tester);
        expect(find.byType(BattlePracticeCampaign), findsOneWidget);
        expect(find.byType(BattleWelcomeScreen), findsOneWidget);
        expect(find.byType(UsernameSetupScreen), findsNothing);
        if (tutorial == 'resume') {
          await journeyTap(tester, find.byKey(const ValueKey('welcome-next')));
          expect(store.welcomeStep, 1);
          await journeyFlush(tester, store);
          final checkpoint = GameStore.createForTesting();
          addTearDown(checkpoint.dispose);
          await journeyAwait(tester, checkpoint.load);
          expect(checkpoint.welcomeStep, 1);
          expect(checkpoint.hasCompletedTutorial, isFalse);
          expect(checkpoint.firstSessionMatchCompleted, isFalse);
          await tester.pumpWidget(const SizedBox());
          await journeyPump(tester);
          await tester.pumpWidget(const LunoAppShell());
          await showLiveOnboarding(tester);
          expect(find.byKey(const ValueKey('welcome-title-1')), findsOneWidget);
        }
        await completeLiveOnboarding(tester);
        expect(store.hasCompletedTutorial, isTrue);
        expect(store.firstSessionMatchCompleted, isTrue);
        expect(store.firstSessionMatchesStarted, 1);
        expect(store.firstSessionPhase, 'firstCompleted');
        expect(store.needsFirstSessionMatch, isFalse);
        expect(store.practiceStage, isNull);
        expect(
          store.data.toJson(),
          initialPlayer,
          reason:
              'Guided onboarding grants no currency, rating or career result.',
        );
        expect((store.rankTrophies, store.rankArenaIdx), initialRank);
        expect(find.byType(BattleV1Screen), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.byType(UsernameSetupScreen), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'JourneyPlayer');
        await journeyTap(tester, find.text('CONTINUE OFFLINE'));
        expect(store.hasChosenUsername, isTrue);
        expect(store.data.username, 'journeyplayer');
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(BattleV1Screen), findsNothing);

        final transport = JourneyTransport(store);
        final online = transport.service();
        addTearDown(online.dispose);
        await journeyAwait(tester, online.start);
        expect(transport.welcomeRequests, 0);
        final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));

        // Finishing onboarding must not claim or lose the welcome reward. The Shop
        // recovery surface uses the same public server-confirmed claim path.
        unawaited(
          navigator.push(
            lunoRoute(ShopScreen(online: online, playerStore: store)),
          ),
        );
        await journeyPump(tester);
        await journeyTap(
          tester,
          find.byKey(const ValueKey('shop-welcome-reward')),
        );
        expect(transport.welcomeRequests, 1);
        expect(online.cachedBattleDeck!.owned, contains(CardId.mine));
        expect(store.data.gold, initialGold + 500);
        expect(find.byType(ShopRewardDialog), findsOneWidget);
        await journeyTap(
          tester,
          find.byKey(const ValueKey('shop-reward-action')),
        );
        expect(find.byType(BattleDeckScreen), findsOneWidget);
        navigator.popUntil((route) => route.isFirst);
        await journeyPump(tester);

        await journeyTap(
          tester,
          find.byKey(const ValueKey('home-primary-battle')),
        );
        expect(find.byType(PlayModeScreen), findsOneWidget);
        expect(find.byType(BattleV1Screen), findsNothing);
        expect(store.firstSessionMatchesStarted, 1);
        await journeyTap(tester, find.text('RANKED MATCH'));
        expect(find.byType(OnlineHubScreen), findsOneWidget);
        navigator.pop();
        await journeyPump(tester);
        expect(find.byType(PlayModeScreen), findsOneWidget);
        expect(store.rankTrophies, 0);
        expect(store.rankArenaIdx, 0);
        // Arena card is a separate route from the ranked queue.
        final arenaText = find.text('ROOKIE CAMP');
        await tester.scrollUntilVisible(
          arenaText,
          -240,
          scrollable:
              find
                  .descendant(
                    of: find.byType(PlayModeScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
        );
        expect(arenaText, findsOneWidget);
        final arenaTap =
            find.ancestor(of: arenaText, matching: find.byType(InkWell)).first;
        await journeyTap(tester, arenaTap);
        expect(find.byType(ArenasScreen), findsOneWidget);
        await journeyTap(
          tester,
          find.byKey(const ValueKey('arena-card-library')),
        );
        expect(find.byType(BattleDeckScreen), findsOneWidget);
        expect(
          tester
              .widget<BattleDeckScreen>(find.byType(BattleDeckScreen))
              .catalogOnly,
          isTrue,
        );
        navigator.popUntil((route) => route.isFirst);
        await journeyPump(tester);
        await journeyTap(
          tester,
          find
              .ancestor(
                of: find.text('COLLECTION'),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(find.byType(CollectionScreen), findsOneWidget);
        navigator.pop();
        await journeyPump(tester);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await journeyFlush(tester, store);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await journeyPump(tester);
        final restored = GameStore.createForTesting();
        addTearDown(restored.dispose);
        await journeyAwait(tester, restored.load);
        expect(restored.hasCompletedTutorial, isTrue);
        expect(restored.firstSessionMatchCompleted, isTrue);
        expect(restored.firstSessionMatchesStarted, 1);
        expect(restored.needsFirstSessionMatch, isFalse);
        expect(restored.welcomeStep, GameStore.welcomeStepCount);
        expect(restored.practiceStage, isNull);
        expect(restored.hasChosenUsername, isTrue);
        expect(restored.data.username, 'journeyplayer');
        expect(restored.data.gold, initialGold + 500);
        final prefs = await journeyAwait(tester, SharedPreferences.getInstance);
        expect(prefs.getString('luno_player_v1'), isNotNull);
        await tester.pumpWidget(const SizedBox());
        await journeyFlush(tester, store);
        await tester.pumpWidget(const LunoAppShell());
        final artwork = tester.widget<LunoLoadingArtwork>(
          find.byType(LunoLoadingArtwork),
        );
        artwork.onShown!();
        await tester.pump(const Duration(milliseconds: 1500));
        await journeyPump(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(BattleWelcomeScreen), findsNothing);
        expect(find.byType(BattleV1Screen), findsNothing);
        expect(find.byType(UsernameSetupScreen), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        // Rebase the singleton's public account queue in the real I/O zone
        // before this test's FakeAsync zone is discarded, even on failure.
        await journeyAwait(tester, () => store.bindAccount(store.accountUid));
        await journeyFlush(tester, store);
      }
    }
  });
}
