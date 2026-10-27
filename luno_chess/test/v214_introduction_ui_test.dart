import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_introduction_screen.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'v214_social_safety_ui_test.dart' show capture;

Future<void> tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setupPracticeTestAssets();
  test(
    'legacy completion and partial Academy progress survive intro migration',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'tutorialCompleted': true,
          'tutorialStep': 9,
          'practiceStage': 2,
          'accountUid': 'legacy',
          'usernameChosen': true,
        }),
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.hasCompletedTutorial, isTrue);
      expect(store.practiceStage, 2);
      expect(store.tutorialStep, 9);
      expect(store.introductionStep, 0);
      await store.save();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('luno_player_v1')!) as Map;
      expect(saved['introductionSchema'], GameStore.introductionSchema);
      expect(saved['practiceStage'], 2);
    },
  );
  test(
    'partial legacy tutorial starts the shorter lesson without erasing legacy progress',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'tutorialCompleted': false,
          'tutorialStep': 5,
        }),
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.hasCompletedTutorial, isFalse);
      expect(store.tutorialStep, 5);
      expect(store.introductionStep, 0);
      expect(store.practiceStage, isNull);
    },
  );
  test(
    'intro checkpoint is persisted per account and stale completion is ignored',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.bindAccount('intro_first');
      final first = store.accountBindingRevision;
      await store.setIntroductionStep(8, first);
      await store.bindAccount('intro_second');
      await store.setIntroductionStep(12, first);
      await store.completeIntroduction(first);
      expect(store.introductionStep, 0);
      expect(store.hasCompletedTutorial, isFalse);
      await store.bindAccount('intro_first');
      expect(store.introductionStep, 8);
      await store.completeIntroduction(store.accountBindingRevision);
      await store.save();
      expect(store.hasCompletedTutorial, isTrue);
      expect(store.practiceStage, isNull);
      await store.bindAccount('intro_second');
      await store.bindAccount('intro_first');
      expect(store.hasCompletedTutorial, isTrue);
    },
  );
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      testWidgets('intro responsive $language ${size.width} text150', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final stage in [
          IntroductionStage.firstPiece,
          IntroductionStage.mana,
          IntroductionStage.mineConfirm,
          IntroductionStage.mineTriggered,
          IntroductionStage.victory,
        ]) {
          final store = GameStore.createForTesting();
          await tester.runAsync(store.load);
          store.introductionStep = stage.index;
          await tester.pumpWidget(
            shell(
              BattleIntroductionScreen(
                key: ValueKey(stage),
                playerStore: store,
              ),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await tick(tester);
          noOverflow(tester);
          expect(find.byType(BattleBoard), findsOneWidget);
          if (stage == IntroductionStage.firstPiece ||
              stage == IntroductionStage.mana ||
              stage == IntroductionStage.mineConfirm ||
              stage == IntroductionStage.victory) {
            expect(
              tester.getRect(find.byType(BattleBoard)).bottom,
              lessThanOrEqualTo(
                tester
                        .getRect(
                          find.byKey(const ValueKey('introduction-body')),
                        )
                        .bottom +
                    1,
              ),
            );
          }
          if (stage == IntroductionStage.firstPiece ||
              stage == IntroductionStage.mana ||
              stage == IntroductionStage.victory) {
            await capture(
              tester,
              'intro-${stage.name}-$language-${size.width.toInt()}-150',
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(store.save);
          store.dispose();
        }
      });
    }
    testWidgets(
      'complete lesson by real controls $language and no economy grants',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = GameStore.createForTesting();
        addTearDown(store.dispose);
        await tester.runAsync(store.load);
        final before = jsonEncode(store.data.toJson());
        await tester.pumpWidget(
          shell(
            BattleIntroductionScreen(playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        final script = BattleIntroduction();
        while (script.stage != IntroductionStage.victory) {
          final stage = script.stage;
          if (script.expectedSquare case final int square) {
            final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
            expect(board.enabled, isTrue);
            expect(board.targets, contains(square));
            board.onTap(square);
          } else if (stage == IntroductionStage.mana) {
            final tile = tester.widget<BattleCardTile>(
              find.byKey(const ValueKey('hand-mine')),
            );
            expect(tile.enabled, isTrue);
            tile.onSelect!();
          } else if (const {
            IntroductionStage.draw,
            IntroductionStage.opponent,
            IntroductionStage.mineTriggered,
          }.contains(stage)) {
            expect(
              find.byKey(ValueKey('introduction-command-${stage.name}')),
              findsNothing,
            );
            await tester.pump(
              Duration(
                milliseconds:
                    stage == IntroductionStage.mineTriggered ? 1600 : 1100,
              ),
            );
          } else {
            final command = find.byKey(
              ValueKey('introduction-command-${stage.name}'),
            );
            expect(command, findsOneWidget);
            tester.widget<LunoButton>(command).onPressed!();
          }
          script.advanceExpected();
          await tick(tester);
          expect(store.introductionStep, script.checkpoint);
          noOverflow(tester);
        }
        final finish =
            tester
                .widget<LunoButton>(
                  find.byKey(const ValueKey('introduction-command-victory')),
                )
                .onPressed!;
        finish();
        finish();
        await tick(tester);
        expect(store.hasCompletedTutorial, isTrue);
        expect(store.practiceStage, isNull);
        expect(store.hasChosenUsername, isFalse);
        expect(jsonEncode(store.data.toJson()), before);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.save);
      },
    );
  }
  testWidgets(
    'skip, covered and departed callbacks cannot enter Academy or mutate another account',
    (tester) async {
      final store =
          (await tester.runAsync(() async {
            final store = GameStore.createForTesting();
            await store.load();
            await store.bindAccount('intro_owner');
            return store;
          }))!;
      addTearDown(store.dispose);
      await tester.pumpWidget(
        shell(BattleIntroductionScreen(playerStore: store), reduced: true),
      );
      final skip =
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('introduction-skip')),
              )
              .onPressed!;
      final boardTap =
          tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap;
      final navigator = Navigator.of(
        tester.element(find.byType(BattleIntroductionScreen)),
      );
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      skip();
      boardTap(8);
      await tick(tester);
      expect(store.hasCompletedTutorial, isFalse);
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.bindAccount('intro_other'));
      skip();
      boardTap(8);
      await tick(tester);
      expect(store.hasCompletedTutorial, isFalse);
      await tester.pumpWidget(
        shell(
          BattleIntroductionScreen(
            key: const ValueKey('new'),
            playerStore: store,
          ),
          reduced: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('introduction-skip')));
      await tick(tester);
      expect(store.hasCompletedTutorial, isTrue);
      expect(store.practiceStage, isNull);
      await tester.pumpWidget(const SizedBox());
      skip();
      await tester.runAsync(store.save);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('paused and stale commands cannot advance the introduction', (
    tester,
  ) async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await tester.runAsync(store.load);
    store.introductionStep = IntroductionStage.draw.index;
    await tester.pumpWidget(
      shell(BattleIntroductionScreen(playerStore: store), reduced: true),
    );
    expect(
      find.byKey(const ValueKey('introduction-command-draw')),
      findsNothing,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tick(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(store.introductionStep, IntroductionStage.draw.index);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tick(tester);
    await tester.pump(const Duration(milliseconds: 1100));
    await tick(tester);
    expect(store.introductionStep, IntroductionStage.mana.index);
    await tester.pump(const Duration(seconds: 3));
    await tick(tester);
    expect(store.introductionStep, IntroductionStage.mana.index);
    final tap =
        tester
            .widget<BattleCardTile>(find.byKey(const ValueKey('hand-mine')))
            .onSelect!;
    tap();
    tap();
    await tick(tester);
    expect(store.introductionStep, IntroductionStage.mineTarget.index);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.save);
  });
  testWidgets(
    'card information opens one real sheet without advancing the lesson',
    (tester) async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await tester.runAsync(store.load);
      store.introductionStep = IntroductionStage.mana.index;
      await tester.pumpWidget(
        shell(BattleIntroductionScreen(playerStore: store), reduced: true),
      );
      final detail =
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('introduction-card-information')),
              )
              .onPressed!;
      detail();
      detail();
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailSheet), findsOneWidget);
      expect(store.introductionStep, IntroductionStage.mana.index);
      Navigator.of(tester.element(find.byType(CardDetailSheet))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('guide exposes optional Academy and resumes saved practice', (
    tester,
  ) async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await tester.runAsync(store.load);
    store.hasCompletedTutorial = true;
    store.practiceStage = 2;
    await tester.pumpWidget(
      shell(TutorialScreen(playerStore: store), reduced: true),
    );
    expect(find.byTooltip('Luno Akademisi'), findsOneWidget);
    final navigator = Navigator.of(tester.element(find.byType(TutorialScreen)));
    await tester.tap(find.byTooltip('Luno Akademisi'));
    await tick(tester);
    expect(
      tester.widget<BattleV1Screen>(find.byType(BattleV1Screen)).practiceStage,
      2,
    );
    expect(
      tester
          .widget<BattleV1Screen>(find.byType(BattleV1Screen))
          .practiceCanExit,
      isTrue,
    );
    expect(store.practiceStage, 2);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(store.practiceStage, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Academy rejects covered, repeated and departed completions', (
    tester,
  ) async {
    final store =
        (await tester.runAsync(() async {
          final store = GameStore.createForTesting();
          await store.load();
          await store.bindAccount('academy_owner');
          store.hasCompletedTutorial = true;
          store.practiceStage = 2;
          await store.save();
          return store;
        }))!;
    addTearDown(store.dispose);
    await tester.pumpWidget(
      shell(
        BattlePracticeCampaign(storeOverride: store, replay: true),
        reduced: true,
      ),
    );
    await tick(tester);
    final complete =
        tester
            .widget<BattleV1Screen>(find.byType(BattleV1Screen))
            .onPracticeComplete!;
    final navigator = Navigator.of(
      tester.element(find.byType(BattlePracticeCampaign)),
    );
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    await tester.runAsync(complete);
    expect(store.practiceStage, 2);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final first = complete();
      final repeated = complete();
      await first;
      await repeated;
    });
    await tick(tester);
    expect(store.practiceStage, 3);
    expect(
      tester.widget<BattleV1Screen>(find.byType(BattleV1Screen)).practiceStage,
      3,
    );
    await tester.runAsync(complete);
    expect(store.practiceStage, 3);
    final departed =
        tester
            .widget<BattleV1Screen>(find.byType(BattleV1Screen))
            .onPracticeComplete!;
    await tester.runAsync(() => store.bindAccount('academy_other'));
    await tester.runAsync(departed);
    expect(store.practiceStage, isNull);
    expect(store.hasCompletedTutorial, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(departed);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'optional Academy and username no longer block first real match',
    (tester) async {
      final store = GameStore.instance;
      store.loaded = true;
      store.hasCompletedTutorial = true;
      store.hasChosenUsername = false;
      store.firstSessionMatchesStarted = 0;
      store.practiceStage = 2;
      await tester.pumpWidget(const LunoAppShell());
      final artwork = tester.widget<LunoLoadingArtwork>(
        find.byType(LunoLoadingArtwork),
      );
      expect(artwork.onShown, isNotNull);
      artwork.onShown!();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BattlePracticeCampaign), findsNothing);
      expect(find.byType(UsernameSetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(store.practiceStage, 2);
      store.recordFirstSessionMatchStart(store.accountBindingRevision);
      store.recordFirstSessionMatchCompletion(store.accountBindingRevision);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(UsernameSetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
