import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/action_guide.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/target_motion.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_ui/fixtures.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture, captureKey;

const boundaryKey = ValueKey('v207-capture');
Widget shell(
  Widget child, {
  String language = 'tr',
  double scale = 1,
  bool reduced = false,
}) => MaterialApp(
  theme: LunoTheme.dark,
  locale: Locale(language),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: RepaintBoundary(key: boundaryKey, child: child!),
      ),
  home: child,
);

Future<void> warm(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> shot(
  WidgetTester tester,
  String name, {
  Key key = boundaryKey,
}) async {
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(key)).renderObject! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v207').create(recursive: true);
    await File('qa/v207/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void noOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is RenderParagraph && render.hasSize) {
      final text = render.text.toPlainText();
      if (text == 'Self' || text == 'Other') continue;
      expect(render.didExceedMaxLines, false, reason: text);
    }
  }
}

Future<void> visibleTap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.loaded = true;
    GameStore.instance.hasCompletedTutorial = false;
    GameStore.instance.tutorialStep = 0;
    GameStore.instance.practiceStage = null;
  });

  test('teaching examples do not duplicate cards across lessons', () {
    final cards = [
      for (final step in [3, 4, 5, 7]) ...battleLessonCards(step),
    ];
    expect(cards.toSet().length, cards.length);
    expect(cards.length, 10);
  });

  testWidgets('new card travels from its deck and settles without replay', (
    tester,
  ) async {
    final source = GlobalKey();
    const destination = ValueKey('arrival-card-content');
    Widget stage() => shell(
      Scaffold(
        body: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                key: source,
                width: 48,
                height: 48,
                child: const ColoredBox(color: Colors.amber),
              ),
            ),
            const SizedBox(height: 90),
            SizedBox(
              width: 90,
              height: 150,
              child: BattleCardArrival(
                card: CardId.radar,
                source: source,
                trigger: 1,
                child: const ColoredBox(key: destination, color: Colors.cyan),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(stage());
    await tester.pump();
    final origin = tester.getCenter(find.byKey(source));
    final start = tester.getCenter(find.byKey(destination));
    expect((start - origin).distance, lessThan(1));
    await tester.pump(const Duration(milliseconds: 200));
    final halfway = tester.getCenter(find.byKey(destination));
    expect((halfway - start).distance, greaterThan(20));
    await tester.pump(const Duration(milliseconds: 200));
    final end = tester.getCenter(find.byKey(destination));
    expect((end - halfway).distance, greaterThan(1));
    expect(find.byKey(const ValueKey('draw-source-radar')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
    final settled = tester.getCenter(find.byKey(destination));
    await tester.pumpWidget(stage());
    await tester.pump();
    expect(tester.getCenter(find.byKey(destination)), settled);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'insufficient mana remains a valid discard decision with truthful feedback',
    (tester) async {
      final h = Harness(
        hand: const [CardId.freeze, CardId.shelter, CardId.radar],
      );
      final draft = RuleDraft(h.state.rules)..mana[PieceColor.white] = 1;
      h.state = AuthoritativeBattleState(draft.freeze(), h.state.hidden);
      h.version++;
      await h.controller.reconnect();
      await tester.pumpWidget(
        shell(
          BattleV1Screen(
            controllerOverride: h.controller,
            clockOverride: (_) => 300000,
          ),
        ),
      );
      await warm(tester);
      await visibleTap(tester, 'hand-freeze');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Mana yetmiyor'), findsOneWidget);
      expect(
        tester
            .widget<BattleCommand>(find.byKey(const ValueKey('play-card')))
            .onPressed,
        isNull,
      );
      await visibleTap(tester, 'discard-card');
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.state.rules.mana[PieceColor.white], 1);
      expect(
        h.state.rules.discarded[PieceColor.white],
        contains(CardId.freeze),
      );
      expect(
        find.byKey(const ValueKey('discard-notice-freeze')),
        findsOneWidget,
      );
      expect(find.textContaining('Mana değişmedi'), findsOneWidget);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('battle visible workflow $size $language', (tester) async {
        await renderBattle(
          tester,
          size: size,
          language: language,
          state: battleFixture(
            hand: const [
              CardId.shadowContract,
              CardId.fateExchange,
              CardId.pawnDeviation,
              CardId.boardSeal,
            ],
          ),
        );
        noOverflow(tester);
        expect(find.byType(BattleActionGuide), findsOneWidget);
        final boardRect = tester.getRect(find.byType(BattleBoard));
        final guideRect = tester.getRect(find.byType(BattleActionGuide));
        if (size.width > size.height ||
            find
                .byKey(const ValueKey('battle-side-scroll'))
                .evaluate()
                .isNotEmpty) {
          expect(guideRect.left, greaterThanOrEqualTo(boardRect.right));
          expect(guideRect.right, lessThanOrEqualTo(size.width));
        } else {
          expect(guideRect.top, greaterThanOrEqualTo(boardRect.bottom));
        }
        if (size.height >= 640 && size.width <= 600) {
          expect(
            tester.getRect(find.byType(BattleHand)).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byKey(const ValueKey('pass-card'))).top,
            ),
          );
        }
        await shot(
          tester,
          'battle-${size.width.toInt()}-${size.height.toInt()}-$language',
          key: captureKey,
        );
        await closeCapture(tester);
      });
    }
  }

  testWidgets(
    'all tutorial stages keep state separate and render current controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final before = GameStore.instance.data.toJson();
      for (var step = 0; step < 10; step++) {
        GameStore.instance.tutorialStep = step;
        await tester.pumpWidget(
          shell(
            TutorialScreen(key: ValueKey(step), onboarding: true),
            reduced: true,
          ),
        );
        await warm(tester);
        noOverflow(tester);
        if (step == 4 || step == 5) {
          expect(
            find.byKey(const ValueKey('lesson-play-card')).hitTestable(),
            findsOneWidget,
            reason: 'The practice action must be visible before scrolling.',
          );
        }
        await shot(tester, 'tutorial-$step');
      }
      expect(GameStore.instance.data.toJson(), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('selected card commands fit $size $language at 1.8 text', (
        tester,
      ) async {
        await renderBattle(
          tester,
          size: size,
          language: language,
          textScale: 1.8,
        );
        await visibleTap(tester, 'hand-shelter');
        noOverflow(tester);
        for (final key in ['cancel-card', 'play-card', 'discard-card']) {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget, reason: key);
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0), reason: key);
          expect(rect.right, lessThanOrEqualTo(size.width), reason: key);
        }
        await closeCapture(tester);
      });
    }
  }

  for (final step in [3, 4, 5, 7]) {
    for (final card in battleLessonCards(step)) {
      testWidgets(
        'lesson $step ${card.wire} uses legal costs and transitions',
        (tester) async {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SingleChildScrollView(
                  child: BattleLessonStage(step: step),
                ),
              ),
              reduced: true,
            ),
          );
          await tester.pump();
          await visibleTap(tester, 'lesson-card-${card.wire}');
          if (step == 3 && cardDefinitions[card]!.cost > 3) {
            expect(
              tester
                  .widget<BattleCommand>(
                    find.byKey(const ValueKey('lesson-play-card')),
                  )
                  .onPressed,
              isNull,
            );
            tester
                .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
                .onChanged!(6);
            await tester.pump();
          }
          if (cardDefinitions[card]!.target == CardTargetType.opponentCard) {
            final target = tester
                .widgetList<OutlinedButton>(find.byType(OutlinedButton))
                .firstWhere(
                  (button) =>
                      button.key.toString().contains('lesson-opponent-'),
                );
            await tester.ensureVisible(find.byKey(target.key!));
            await tester.tap(find.byKey(target.key!));
            await tester.pump();
          } else if (cardDefinitions[card]!.target != CardTargetType.none) {
            final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
            expect(board.targets, isNotEmpty);
            await visibleTap(tester, 'square-${board.targets.first}');
          }
          final beforeMana =
              tester.widget<BattleMana>(find.byType(BattleMana)).value;
          await visibleTap(tester, 'lesson-play-card');
          expect(
            tester.widget<BattleMana>(find.byType(BattleMana)).value,
            beforeMana - cardDefinitions[card]!.cost,
          );
          if (step != 7) {
            final view =
                tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
            expect(view.rules.used[PieceColor.white], contains(card));
            expect(view.rules.phase, BattlePhase.chess);
            expect(
              BattleRulesCore.legalActions(view).whereType<ChessMoveAction>(),
              isNotEmpty,
            );
          } else if (card == CardId.prophecy) {
            expect(
              find.byKey(const ValueKey('lesson-resolve')),
              findsOneWidget,
            );
            await visibleTap(tester, 'lesson-resolve');
            expect(find.byKey(const ValueKey('lesson-resolve')), findsNothing);
          }
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'tutorial discard spends no mana and draw reaches a four-card hand',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 2)),
          ),
          reduced: true,
        ),
      );
      await tester.pump();
      final before = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
      await visibleTap(tester, 'lesson-discard');
      final after = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
      expect(after.rules.mana, before.rules.mana);
      expect(after.ownHand.length, before.ownHand.length - 1);
      expect(after.rules.phase, BattlePhase.chess);
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(
              child: BattleLessonStage(key: ValueKey('draw'), step: 6),
            ),
          ),
          reduced: true,
        ),
      );
      await tester.pump();
      await visibleTap(tester, 'lesson-pass');
      final drawView =
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
      final move =
          BattleRulesCore.legalActions(
            drawView,
          ).whereType<ChessMoveAction>().first;
      int square(String name) =>
          name.codeUnitAt(0) - 97 + 8 * (int.parse(name[1]) - 1);
      await visibleTap(tester, 'square-${square(move.uci.substring(0, 2))}');
      await visibleTap(tester, 'square-${square(move.uci.substring(2, 4))}');
      expect(
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .ownHand
            .length,
        4,
      );
      expect(find.byType(BattleCardTile), findsNWidgets(4));
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'target animation finishes and does not replay after backgrounding',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SizedBox.square(
              dimension: 320,
              child: BattleTargetArrival(
                squares: {12, 20},
                viewer: PieceColor.white,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final finder = find.byKey(const ValueKey('battle-target-arrival'));
      expect(
        (tester.widget<CustomPaint>(finder).painter! as BattleTargetPainter)
            .progress,
        lessThan(1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        (tester.widget<CustomPaint>(finder).painter! as BattleTargetPainter)
            .progress,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('real selected target and accepted freeze motion frames', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = Harness(
      hand: const [CardId.freeze, CardId.shelter, CardId.radar],
    );
    await tester.pumpWidget(
      shell(
        BattleV1Screen(
          controllerOverride: h.controller,
          clockOverride: (_) => 300000,
        ),
      ),
    );
    await warm(tester);
    await visibleTap(tester, 'hand-freeze');
    await shot(tester, 'battle-selected');
    await visibleTap(tester, 'square-57');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('card-preview-57')), findsOneWidget);
    expect(tester.widget<BattleBoard>(find.byType(BattleBoard)).preview, {57});
    expect(
      tester
          .widget<BattleCommand>(find.byKey(const ValueKey('play-card')))
          .onPressed,
      isNotNull,
    );
    await shot(tester, 'battle-target-ready');
    await visibleTap(tester, 'play-card');
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await shot(tester, 'motion-${frame.toString().padLeft(2, '0')}');
      noOverflow(tester);
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });
}
