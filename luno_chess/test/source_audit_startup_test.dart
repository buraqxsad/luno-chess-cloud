import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

void main() {
  setupPracticeTestAssets();
  setUp(() {
    LunoSettings.instance.language = LunoSettings.languageTurkish;
    final store = GameStore.instance;
    store.loaded = false;
    store.hasCompletedTutorial = false;
    store.hasChosenUsername = false;
    store.practiceStage = null;
    store.tutorialStep = 0;
    store.introductionStep = 0;
    store.welcomeStep = 0;
    store.onboardingBattleStage = 0;
  });
  testWidgets('slow essential local initialization holds loader until ready', (
    tester,
  ) async {
    await tester.pumpWidget(const LunoAppShell());
    tester
        .widget<LunoLoadingArtwork>(find.byType(LunoLoadingArtwork))
        .onShown!();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('loading')), findsOneWidget);
    expect(find.byType(BattlePracticeCampaign), findsNothing);
    GameStore.instance.loaded = true;
    await GameStore.instance.setTutorialStep(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('loading')), findsNothing);
    expect(find.byType(BattlePracticeCampaign), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await GameStore.instance.setTutorialStep(0);
      await tester.pump();
    }
    expect(find.byType(BattlePracticeCampaign), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('fast data still shows loading artwork before the welcome', (
    tester,
  ) async {
    GameStore.instance.loaded = true;
    await tester.pumpWidget(const LunoAppShell());
    tester
        .widget<LunoLoadingArtwork>(find.byType(LunoLoadingArtwork))
        .onShown!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BattlePracticeCampaign), findsNothing);
    expect(find.byKey(const ValueKey('loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BattlePracticeCampaign), findsOneWidget);
    expect(find.byKey(const ValueKey('loading')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'malformed persisted data recovers to safe local initialization, not fabricated auth',
    () async {
      SharedPreferences.setMockInitialValues({'luno_player_v1': '{broken'});
      final store = GameStore.createForTesting();
      await store.load();
      expect(store.loaded, true);
      expect(store.hasCompletedTutorial, false);
      expect(store.accountUid, isNull);
      store.dispose();
    },
  );
}
