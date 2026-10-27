import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, visibleTap, boundaryKey;
import 'battle_ui/interaction_test.dart' show Harness;
import 'interaction_clarity_v211_test.dart' show makeMove;

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(boundaryKey)).renderObject!
            as RenderRepaintBoundary;
    final rendered = await boundary.toImage(pixelRatio: 2);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v212').create(recursive: true);
    await File('qa/v212/$name.png').writeAsBytes(data!.buffer.asUint8List());
    rendered.dispose();
  });
}

Future<void> mountLesson(
  WidgetTester tester,
  int step, {
  String language = 'tr',
}) async {
  await tester.pumpWidget(
    shell(
      Scaffold(
        body: SingleChildScrollView(child: BattleLessonStage(step: step)),
      ),
      language: language,
      reduced: true,
    ),
  );
  await warm(tester);
}

void main() {
  setupPracticeTestAssets();
  test('starter avatar and Android splash use the new Luno, not old logo', () {
    expect(LunoAssets.avatar('av_pawn'), LunoAssets.lunoPortrait);
    expect(LunoAssets.avatar('unknown'), LunoAssets.lunoPortrait);
    for (final name in ['values-v31', 'values-night-v31']) {
      final xml =
          File('android/app/src/main/res/$name/styles.xml').readAsStringSync();
      expect(xml, contains('@drawable/luno_splash_v212'));
      expect(xml, isNot(contains('@drawable/luno_splash_icon')));
    }
    expect(
      File(
        'android/app/src/main/res/drawable-nodpi/luno_splash_v212.png',
      ).existsSync(),
      true,
    );
  });

  for (final language in ['tr', 'en']) {
    testWidgets(
      'profile does not present legacy 29 cards as battle ownership $language',
      (tester) async {
        await tester.pumpWidget(
          shell(const ProfileScreen(), language: language),
        );
        await warm(tester);
        expect(
          find.text(
            language == 'tr' ? 'Savaş kartı çeşitleri' : 'Battle card types',
          ),
          findsOneWidget,
        );
        expect(find.text('24'), findsOneWidget);
        expect(find.textContaining('/29'), findsNothing);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'battle button theme cannot paint the old face over new art $language',
      (tester) async {
        for (final primary in [false, true]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: BattleCommand(
                  label: 'Play',
                  icon: Icons.play_arrow,
                  primary: primary,
                  onPressed: () {},
                ),
              ),
              language: language,
            ),
          );
          await warm(tester);
          expect(find.byType(BattleSkin), findsNothing);
          final button = tester.widget<FilledButton>(find.byType(FilledButton));
          final child = const SizedBox(width: 10, height: 10);
          final face =
              button.style!.backgroundBuilder!(
                    tester.element(find.byType(FilledButton)),
                    {},
                    child,
                  )
                  as AnimatedContainer;
          final decoration = face.decoration! as BoxDecoration;
          expect(face.key, const ValueKey('battle-command-face'));
          expect(face.child, same(child));
          if (primary) {
            expect(
              decoration.image!.image,
              AssetImage(BattleArt.path('action-face')),
            );
            expect(
              decoration.image!.centerSlice,
              const Rect.fromLTRB(32, 12, 688, 121),
            );
            expect(decoration.image!.fit, BoxFit.fill);
          } else {
            expect(decoration.image, isNull);
          }
          expect(
            button.style!.backgroundColor!.resolve({}),
            Colors.transparent,
          );
          expect(
            button.style!.surfaceTintColor!.resolve({}),
            Colors.transparent,
          );
          expect(button.style!.elevation!.resolve({}), 0);
          expect(
            tester.getSize(find.byType(FilledButton)).height,
            greaterThanOrEqualTo(48),
          );
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      'tutorial discard preserves visible selectable chess move $language',
      (tester) async {
        await mountLesson(tester, 2, language: language);
        expect(find.byType(BattleCardTile), findsNWidgets(3));
        for (final tile in tester.widgetList<BattleCardTile>(
          find.byType(BattleCardTile),
        )) {
          expect(tester.getSize(find.byKey(tile.key!)).width, greaterThan(85));
        }
        await visibleTap(tester, 'hand-prophecy');
        await visibleTap(tester, 'lesson-discard');
        final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
        expect(board.view.rules.phase, BattlePhase.chess);
        expect(board.view.rules.board.turn, PieceColor.white);
        expect(board.enabled, true);
        expect(board.view.rules.discarded[PieceColor.white], [CardId.prophecy]);
        await makeMove(tester);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
          1,
        );
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('board seal does not choose or cast a random zone $language', (
      tester,
    ) async {
      await mountLesson(tester, 3, language: language);
      await visibleTap(tester, 'lesson-card-board_seal');
      tester
          .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
          .onChanged!(6);
      await tester.pump();
      final button = tester.widget<BattleCommand>(
        find.byKey(const ValueKey('lesson-play-card')),
      );
      expect(button.onPressed, isNull);
      expect(
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .rules
            .boardEffects,
        isEmpty,
      );
      await visibleTap(tester, 'square-35');
      expect(tester.widget<BattleBoard>(find.byType(BattleBoard)).preview, {
        35,
        36,
        43,
        44,
      });
      expect(
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .rules
            .boardEffects,
        isEmpty,
      );
      await visibleTap(tester, 'lesson-play-card');
      final after = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
      expect(after.rules.boardEffects.single.squares, [35, 36, 43, 44]);
      expect(after.rules.mana[PieceColor.white], 1);
      await makeMove(tester);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tutorial Prophecy swaps actual draw order $language', (
      tester,
    ) async {
      await mountLesson(tester, 7, language: language);
      await visibleTap(tester, 'lesson-card-prophecy');
      await visibleTap(tester, 'lesson-play-card');
      final pending = [
        ...tester
            .widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
            .view
            .knowledge
            .pendingCards,
      ];
      await visibleTap(tester, 'lesson-swap-order');
      await visibleTap(tester, 'lesson-resolve');
      expect(find.byKey(const ValueKey('lesson-resolve')), findsNothing);
      expect(
        find.byKey(const ValueKey('lesson-goal-information')),
        findsOneWidget,
      );
      expect(pending, hasLength(2));
      final view =
          tester
              .widget<BattleAudioFeedback>(find.byType(BattleAudioFeedback))
              .view;
      expect(view.knowledge.knownUpcomingCards, pending.reversed.toList());
      noOverflow(tester);
      await capture(tester, 'prophecy-reordered-$language');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final card in CardId.values) {
    testWidgets(
      'battle discard ${card.wire} then e2e4 is one valid chess move',
      (tester) async {
        final other = CardId.values.where((c) => c != card).take(2).toList();
        final h = Harness(hand: [card, ...other]);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(h.controller.dispose);
        await tester.pumpWidget(
          shell(
            BattleV1Screen(
              controllerOverride: h.controller,
              clockOverride: (_) => 300000,
            ),
            reduced: true,
          ),
        );
        await warm(tester);
        await visibleTap(tester, 'hand-${card.wire}');
        await tester.pumpAndSettle();
        if (find.byType(BattleSheet).evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Kapat').last);
          await tester.pumpAndSettle();
        }
        await visibleTap(tester, 'discard-card');
        await tester.pumpAndSettle();
        expect(h.state.rules.phase, BattlePhase.chess);
        expect(h.controller.view!.rules.board.turn, PieceColor.white);
        await visibleTap(tester, 'square-12');
        await visibleTap(tester, 'square-28');
        await tester.pumpAndSettle();
        expect(h.sent.map((a) => a.key), ['discard:${card.wire}', 'move:e2e4']);
        expect(h.state.rules.ply, 1);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('loading native text fits $size $language at 1.8 scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var shown = 0;
        await tester.pumpWidget(
          shell(
            Scaffold(body: LunoLoadingArtwork(onShown: () => shown++)),
            language: language,
            scale: 1.8,
          ),
        );
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(
              image.image,
              tester.element(find.byType(Scaffold)),
            );
          }
        });
        await tester.pump(const Duration(milliseconds: 100));
        expect(shown, greaterThan(0));
        expect(find.textContaining('7 ARENA'), findsNothing);
        noOverflow(tester);
        await capture(
          tester,
          'loading-${size.width.toInt()}-${size.height.toInt()}-$language',
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (var step = 0; step < 10; step++) {
    testWidgets(
      'render tutorial step $step with Luno speech and actual controls',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        GameStore.instance.tutorialStep = step;
        final before = GameStore.instance.data.toJson();
        await tester.pumpWidget(
          shell(TutorialScreen(onboarding: true), reduced: true),
        );
        await warm(tester);
        expect(find.text('LUNO'), findsWidgets);
        noOverflow(tester);
        await capture(tester, 'tutorial-$step');
        expect(GameStore.instance.data.toJson(), before);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
