import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_introduction_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/screens/blocked_players_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_deck_account_test.dart' show response;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart'
    show
        renderBattle,
        editedFixture,
        effectFixture,
        knowledgeFixture,
        visualTap,
        captureKey,
        VisualScene;
import 'helpers/live_onboarding_driver.dart';
import 'rc_battle_capture_test.dart' as rc_battle;
import 'rc_screen_capture_test.dart' as rc_screens;
import 'v214_first_match_ui_test.dart' as first_match;
import 'v214_active_deck_test.dart' as active_deck;
import 'v214_introduction_ui_test.dart' as intro;
import 'v214_social_safety_ui_test.dart' as social;
import 'v217_player_journey_support.dart' show journeyAwait, journeyTap;

const journeyKey = ValueKey('v214-first-session-capture');

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Map<String, double> rectJson(Rect rect) => {
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
};

Future<void> surfaceCapture(
  WidgetTester tester,
  String name, {
  Key key = boundaryKey,
  String? note,
}) async {
  final context = tester.element(find.byKey(key));
  final providers = <ImageProvider>{
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      image.image,
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ))
      if (box.decoration case final BoxDecoration decoration)
        if (decoration.image != null) decoration.image!.image,
  };
  await tester.runAsync(() async {
    for (final provider in providers) {
      await precacheImage(
        provider,
        context,
      ).timeout(const Duration(seconds: 15));
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  expect(tester.takeException(), isNull, reason: name);
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final ownHeader = find.byWidgetPredicate(
    (widget) => widget is BattlePlayerHeader && widget.own,
  );
  final ownMana = find.descendant(
    of: ownHeader,
    matching: find.byType(BattleMana),
  );
  final boardScroll = find.byKey(const ValueKey('battle-scroll'));
  final scaleContext =
      find.byType(BattleV1Scaffold).evaluate().isNotEmpty
          ? tester.element(find.byType(BattleV1Scaffold).first)
          : find.byType(Scaffold).evaluate().isNotEmpty
          ? tester.element(find.byType(Scaffold).first)
          : context;
  final metadata = {
    'name': name,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceMark': Platform.environment['V214_SOURCE_MARK'] ?? 'unmarked',
    'fixture': 'Actual local Flutter render; no live Firebase or device proof',
    'note': note,
    'viewport': rectJson(viewport),
    'textScaleAt14': MediaQuery.textScalerOf(scaleContext).scale(14) / 14,
    'board':
        find.byType(BattleBoard).evaluate().isEmpty
            ? null
            : rectJson(tester.getRect(find.byType(BattleBoard).first)),
    'hand':
        find.byType(BattleHand).evaluate().isEmpty
            ? null
            : rectJson(tester.getRect(find.byType(BattleHand).first)),
    'ownMana':
        ownMana.evaluate().isEmpty
            ? null
            : rectJson(tester.getRect(ownMana.first)),
    'boardCell':
        find.byType(BattleBoard).evaluate().isEmpty
            ? null
            : tester.getRect(find.byType(BattleBoard).first).width / 8,
    'battleScroll':
        boardScroll.evaluate().isEmpty
            ? null
            : rectJson(tester.getRect(boardScroll)),
    'text': [
      for (final text in tester.widgetList<RichText>(find.byType(RichText)))
        text.text.toPlainText(),
    ],
    'ellipsizedText': [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph paragraph)
          if (paragraph.hasSize && paragraph.didExceedMaxLines)
            paragraph.text.toPlainText(),
    ],
  };
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(key)).renderObject! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory(
      Platform.environment['V214_CAPTURE_ROOT'] ?? 'qa/v214/current-visual',
    )..createSync(recursive: true);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    await File('${output.path}/$name.json').writeAsString(jsonEncode(metadata));
    image.dispose();
  });
}

void assertBoardAndHandVisible(WidgetTester tester, Size size, String label) {
  final board = tester.getRect(find.byType(BattleBoard).first);
  final hand = tester.getRect(find.byType(BattleHand).first);
  final viewport = Offset.zero & size;
  expect(board.top, greaterThanOrEqualTo(viewport.top), reason: label);
  expect(board.bottom, lessThanOrEqualTo(viewport.bottom), reason: label);
  expect(
    board.width / 8,
    greaterThanOrEqualTo(24),
    reason: '$label: chess cells need a readable minimum logical size',
  );
  expect(hand.top, greaterThanOrEqualTo(viewport.top), reason: label);
  expect(
    hand.bottom,
    lessThanOrEqualTo(viewport.bottom),
    reason: '$label: own hand must be initially visible without scrolling',
  );
  final mainScroll = find.byKey(const ValueKey('battle-scroll'));
  if (find
      .ancestor(of: find.byType(BattleBoard), matching: mainScroll)
      .evaluate()
      .isNotEmpty) {
    expect(
      board.bottom,
      lessThanOrEqualTo(tester.getRect(mainScroll).bottom),
      reason: '$label: board must not be clipped behind the hand dock',
    );
  }
  if (find
      .ancestor(of: find.byType(BattleHand), matching: mainScroll)
      .evaluate()
      .isNotEmpty) {
    expect(
      hand.bottom,
      lessThanOrEqualTo(tester.getRect(mainScroll).bottom),
      reason: '$label: hand must not be clipped behind the action dock',
    );
  }
  expect(
    find.byKey(const ValueKey('open-menu')).hitTestable(),
    findsOneWidget,
    reason: '$label: match/back control must be reachable',
  );
  final ownHeader = find.byWidgetPredicate(
    (widget) => widget is BattlePlayerHeader && widget.own,
  );
  final ownMana = find.descendant(
    of: ownHeader,
    matching: find.byType(BattleMana),
  );
  expect(ownMana, findsOneWidget, reason: label);
  final mana = tester.getRect(ownMana);
  expect(mana.top, greaterThanOrEqualTo(0), reason: label);
  expect(mana.bottom, lessThanOrEqualTo(size.height), reason: label);
  expect(
    mana.height,
    greaterThanOrEqualTo(16),
    reason: '$label: own mana must not shrink to an unreadable strip',
  );
}

void firstSessionTests() {
  testWidgets('V214 fresh guided onboarding 10 captured states tr and en', (
    tester,
  ) async {
    // The App's singleton queues stay in one FakeAsync zone across both locales.
    for (final language in ['tr', 'en']) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await journeyAwait(tester, () async {
        await LunoSettings.instance.load();
        await LunoSettings.instance.setLanguage(
          language == 'tr'
              ? LunoSettings.languageTurkish
              : LunoSettings.languageEnglish,
        );
      });
      final store = GameStore.instance;
      store
        ..data = PlayerData.initial()
        ..loaded = false
        ..hasCompletedTutorial = false
        ..hasChosenUsername = false
        ..pendingUsernameDraft = ''
        ..tutorialStep = 0
        ..introductionStep = 0
        ..welcomeStep = 0
        ..onboardingBattleStage = 0
        ..firstSessionMatchesStarted = 0
        ..practiceStage = null;
      final initialPlayer = store.data.toJson();
      await tester.pumpWidget(
        const RepaintBoundary(key: journeyKey, child: LunoAppShell()),
      );
      await surfaceCapture(
        tester,
        'first-01-loading-$language',
        key: journeyKey,
        note: 'Fresh local account; artwork before the three-page welcome.',
      );
      store.loaded = true;
      store.notifyListeners();
      await showLiveOnboarding(tester);
      const welcomeNames = ['luno', 'turn-order', 'ready'];
      for (var step = 0; step < welcomeNames.length; step++) {
        expect(find.byType(BattleWelcomeScreen), findsOneWidget);
        expect(find.byKey(ValueKey('welcome-title-$step')), findsOneWidget);
        expect(find.byType(BattleV1Screen), findsNothing);
        expect(find.byType(UsernameSetupScreen), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
        await surfaceCapture(
          tester,
          'first-0${step + 2}-welcome-${welcomeNames[step]}-$language',
          key: journeyKey,
          note:
              'Actual fresh-account welcome page ${step + 1}/3; UI taps only.',
        );
        if (step < welcomeNames.length - 1) {
          await journeyTap(tester, find.byKey(const ValueKey('welcome-next')));
          expect(store.welcomeStep, step + 1);
        }
      }
      await advanceLiveWelcome(tester);
      expect(find.byType(BattleV1Screen), findsOneWidget);
      await surfaceCapture(
        tester,
        'first-05-guided-match-$language',
        key: journeyKey,
        note:
            'One real local Baby Luno guided match, not the optional scripted introduction.',
      );
      await journeyTap(tester, find.byKey(const ValueKey('square-8')));
      final selected = tester.widget<BattleBoard>(find.byType(BattleBoard));
      expect(selected.selected, 8);
      expect(selected.targets, containsAll([16, 24]));
      await surfaceCapture(
        tester,
        'first-06-guided-piece-selected-$language',
        key: journeyKey,
        note: 'Actual pawn selection and legal targets before any chess move.',
      );
      await completeLiveOnboarding(tester);
      expect(store.hasCompletedTutorial, isTrue);
      expect(store.firstSessionMatchCompleted, isTrue);
      expect(store.firstSessionMatchesStarted, 1);
      expect(store.needsFirstSessionMatch, isFalse);
      expect(store.practiceStage, isNull);
      expect(store.data.toJson(), initialPlayer);
      expect(find.byType(BattleV1Screen), findsNothing);
      expect(find.byType(UsernameSetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await surfaceCapture(
        tester,
        'first-07-username-$language',
        key: journeyKey,
        note:
            'After real card, discard and chess taps plus confirmed terminal resignation; no local rewards.',
      );
      await tester.enterText(find.byType(TextField), 'SurfacePlayer');
      await journeyTap(
        tester,
        find.text(
          language == 'tr' ? 'ÇEVRİMDIŞI DEVAM ET' : 'CONTINUE OFFLINE',
        ),
      );
      expect(store.hasChosenUsername, isTrue);
      expect(store.data.username, 'surfaceplayer');
      expect(find.byType(UsernameSetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(BattleV1Screen), findsNothing);
      await surfaceCapture(
        tester,
        'first-08-home-$language',
        key: journeyKey,
        note: 'Actual Home after choosing a username; no extra forced match.',
      );
      final primary = find.byKey(const ValueKey('home-primary-battle'));
      expect(primary.hitTestable(), findsOneWidget);
      await surfaceCapture(
        tester,
        'first-09-battle-cta-$language',
        key: journeyKey,
        note: 'Home battle CTA before its actual tap opens PlayMode.',
      );
      await journeyTap(tester, primary);
      expect(find.byType(PlayModeScreen), findsOneWidget);
      expect(find.byType(BattleV1Screen), findsNothing);
      expect(store.firstSessionMatchesStarted, 1);
      await surfaceCapture(
        tester,
        'first-10-play-mode-$language',
        key: journeyKey,
        note:
            'Normal mode selection; fresh onboarding does not start a second match.',
      );
      await tester.pumpWidget(const SizedBox());
      await journeyAwait(tester, () => store.bindAccount(store.accountUid));
      await journeyAwait(tester, store.flush);
    }
  });
}

void battleTests() {
  final scenes = <VisualScene>[
    VisualScene(
      '01-initial-hand',
      fixture: () => battleFixture(firstTurn: true),
    ),
    const VisualScene('02-normal-turn'),
    const VisualScene('03-selected-piece', taps: ['square-12']),
    const VisualScene('04-legal-moves', taps: ['square-12']),
    const VisualScene('05-selected-card', taps: ['hand-shelter']),
    const VisualScene('06-targeting', taps: ['hand-shelter', 'square-12']),
    const VisualScene('07-pending-action'),
    VisualScene(
      '08-own-draw',
      fixture: () {
        var state = battleFixture(firstTurn: true);
        state = DeckManager.apply(state, const ChessMoveAction('e2e4'));
        return DeckManager.apply(state, const ChessMoveAction('e7e5'));
      },
    ),
    VisualScene(
      '09-opponent-draw',
      fixture: () {
        var state = DeckManager.apply(battleFixture(), const PassAction());
        return DeckManager.apply(state, const ChessMoveAction('e2e4'));
      },
    ),
    VisualScene('10-multiple-effects', fixture: () => effectFixture(all: true)),
    VisualScene(
      '11-check',
      fixture:
          () => editedFixture((draft) {
            draft.board = Board.fromFen('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1');
            draft.pieceIds = List.generate(
              64,
              (i) => draft.board.pieceAt(i) == null ? null : 'p$i',
            );
            draft.phase = BattlePhase.chess;
          }),
    ),
    VisualScene(
      '12-result',
      fixture:
          () => editedFixture((draft) {
            draft.phase = BattlePhase.terminal;
            draft.terminal = const TerminalState(
              'checkmate',
              winner: PieceColor.white,
            );
          }),
    ),
    VisualScene(
      '13-private-information',
      fixture: () => knowledgeFixture(false),
    ),
    const VisualScene('14-opponent-cards', taps: ['open-arsenal']),
    const VisualScene('15-small-screen', size: Size(320, 568)),
    const VisualScene('16-large-text', scale: 1.5),
    const VisualScene('17-tablet', size: Size(768, 1024)),
  ];
  for (final language in ['tr', 'en']) {
    for (final scene in scenes) {
      testWidgets('V214 battle required ${scene.name} $language', (
        tester,
      ) async {
        final hold =
            scene.name == '07-pending-action' ? Completer<void>() : null;
        final controller = await renderBattle(
          tester,
          state: scene.fixture?.call(),
          size: scene.size,
          textScale: scene.scale,
          language: language,
          theme: LunoTheme.darkFor(language),
          hold: hold,
        );
        if (hold != null) {
          await tester.ensureVisible(find.byKey(const ValueKey('pass-card')));
          await tester.tap(find.byKey(const ValueKey('pass-card')));
          await tester.pump();
          expect(controller.busy, isTrue);
        }
        for (final key in scene.taps) {
          await visualTap(tester, key);
        }
        if (scene.name == '04-legal-moves') {
          expect(
            tester.widget<BattleBoard>(find.byType(BattleBoard)).targets,
            isNotEmpty,
          );
        }
        if (scene.name == '13-private-information') {
          final button = find.byTooltip(
            language == 'tr' ? 'Ozel bilgiler' : 'Private knowledge',
          );
          final localized =
              language == 'tr' ? find.byTooltip('\u00d6zel bilgiler') : button;
          await tester.ensureVisible(localized);
          await tester.tap(localized);
          await tester.pumpAndSettle();
        }
        await surfaceCapture(
          tester,
          'battle-${scene.name}-$language',
          key: captureKey,
          note:
              scene.name.contains('draw')
                  ? 'Canonical settled post-draw state; not a frame-by-frame animation test'
                  : scene.name == '04-legal-moves'
                  ? 'Same piece selection surface, with legal-target assertion'
                  : null,
        );
        await tester.pumpWidget(const SizedBox());
        hold?.complete();
        await tester.pump();
      });
    }
  }
}

void responsiveTests() {
  final sizes = [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(768, 1024),
  ];
  for (final language in ['tr', 'en']) {
    for (final size in sizes) {
      for (final scale in [1.0, 1.3, 1.5]) {
        final label =
            '$language ${size.width.toInt()}x${size.height.toInt()} scale$scale';
        testWidgets('V214 exact responsive battle $label', (tester) async {
          await renderBattle(
            tester,
            state: battleFixture(firstTurn: true),
            size: size,
            textScale: scale,
            language: language,
            theme: LunoTheme.darkFor(language),
          );
          await surfaceCapture(
            tester,
            'matrix-battle-$language-${size.width.toInt()}-${(scale * 100).round()}',
            key: captureKey,
          );
          assertBoardAndHandVisible(tester, size, label);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
        testWidgets('V214 exact responsive intro $label', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.createForTesting();
          await tester.runAsync(store.load);
          for (final stage in [
            IntroductionStage.firstPiece,
            IntroductionStage.mana,
            IntroductionStage.mineConfirm,
            IntroductionStage.victory,
          ]) {
            store.introductionStep = stage.index;
            await tester.pumpWidget(
              shell(
                BattleIntroductionScreen(
                  key: ValueKey(stage),
                  playerStore: store,
                ),
                language: language,
                scale: scale,
                reduced: true,
              ),
            );
            await settle(tester);
            final board = tester.getRect(find.byType(BattleBoard));
            expect(
              board.bottom,
              lessThanOrEqualTo(size.height),
              reason: '$label ${stage.name}',
            );
            expect(
              find.byKey(const ValueKey('introduction-skip')).hitTestable(),
              findsOneWidget,
            );
            if (stage == IntroductionStage.firstPiece ||
                stage == IntroductionStage.mineConfirm) {
              await surfaceCapture(
                tester,
                'matrix-intro-${stage.name}-$language-${size.width.toInt()}-${(scale * 100).round()}',
              );
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$label ${stage.name}',
            );
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(store.save);
          }
          store.dispose();
        });
      }
    }
  }
}

void categoryTests() {
  for (final language in ['tr', 'en']) {
    testWidgets('V214 remaining screen categories $language', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final online = social.service();
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        shell(
          BlockedPlayersScreen(online: online),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      await settle(tester);
      expect(find.text('luno_friend'), findsOneWidget);
      await surfaceCapture(tester, 'category-blocked-content-$language');
      final unblock =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed!;
      unblock();
      unblock();
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await surfaceCapture(tester, 'category-unblock-modal-$language');
      await tester.tap(
        find.widgetWithText(
          TextButton,
          language == 'tr' ? 'Vazge\u00e7' : 'Cancel',
        ),
      );
      await settle(tester);
      expect(find.text('luno_friend'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      await tester.pumpWidget(
        shell(
          PublicPlayerProfileScreen(targetUid: 'target', online: online),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      await settle(tester);
      expect(find.byType(PlayerDetailsScreen), findsOneWidget);
      await surfaceCapture(
        tester,
        'category-player-details-$language',
        note:
            'PlayerDetailsScreen is the actual content of PublicPlayerProfileScreen',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    testWidgets('V214 confirmed active deck render $language', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, online, _) =
          (await tester.runAsync(
            () => active_deck.setup(
              (_) async => active_deck.reply(
                response(
                  deck: active_deck.active.map((card) => card.wire).toList(),
                ),
              ),
            ),
          ))!;
      store.firstSessionMatchesStarted = 2;
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await tester.runAsync(online.getBattleV1Deck);
      await tester.pumpWidget(
        shell(
          PlayModeScreen(online: online, playerStore: store),
          language: language,
          reduced: true,
        ),
      );
      await settle(tester);
      expect(
        find.text(language == 'tr' ? 'AKT\u0130F DESTEN' : 'ACTIVE DECK'),
        findsOneWidget,
      );
      expect(online.cachedBattleDeck, isNotNull);
      await surfaceCapture(
        tester,
        'category-confirmed-active-deck-$language',
        note: 'Confirmed mocked server deck, not singleton bootstrap fallback',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

void main() {
  final suite = Platform.environment['V214_REUSE_SUITE'];
  if (suite == null) {
    setupPracticeTestAssets();
    setUpAll(GameStore.instance.load);
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();
      GameStore.instance
        ..data = PlayerData.initial()
        ..loaded = true;
    });
    final set = Platform.environment['V214_RENDER_SET'];
    if (set == null || set == 'journey') firstSessionTests();
    if (set == null || set == 'battle') battleTests();
    if (set == null || set == 'responsive') responsiveTests();
    if (set == null || set == 'categories') categoryTests();
    return;
  }
  final root = Directory.current.absolute;
  final output = Directory('${root.path}/qa/v214/reused-$suite');
  output.createSync(recursive: true);
  group('V214 current reused $suite', () {
    setUpAll(() => Directory.current = output);
    tearDownAll(() => Directory.current = root);
    switch (suite) {
      case 'screens':
        rc_screens.main();
      case 'battle':
        rc_battle.main();
      case 'intro':
        intro.main();
      case 'journey':
        first_match.main();
      case 'social':
        social.main();
      default:
        throw ArgumentError.value(suite, 'V214_REUSE_SUITE');
    }
  });
}
