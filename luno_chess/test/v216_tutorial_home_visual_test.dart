import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_introduction_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, boundaryKey, warm, noOverflow;

const phase = String.fromEnvironment('V216_PHASE', defaultValue: 'after');

Future<void> capture(
  WidgetTester tester,
  String name, {
  bool settle = true,
}) async {
  if (settle) await warm(tester);
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    final providers = <ImageProvider>{};
    void include(Decoration? decoration) {
      if (decoration is BoxDecoration && decoration.image != null) {
        providers.add(decoration.image!.image);
      }
    }

    for (final widget in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      include(widget.decoration);
    }
    for (final widget in tester.widgetList<Container>(find.byType(Container))) {
      include(widget.decoration);
    }
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(boundaryKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('qa/v216/$phase/tutorial-home');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true
      ..hasCompletedTutorial = false
      ..hasChosenUsername = false
      ..firstSessionMatchesStarted = 0;
  });
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      testWidgets('V216 $phase tutorial/home $language ${size.width} text150', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final suffix = '$language-${size.width.toInt()}-text150';
        for (final stage in IntroductionStage.values) {
          GameStore.instance.introductionStep = stage.index;
          await tester.pumpWidget(
            shell(
              const BattleIntroductionScreen(),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await capture(tester, 'intro-${stage.name}-$suffix');
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(GameStore.instance.save);
        }
        if (phase == 'after') {
          GameStore.instance.introductionStep = 0;
          await tester.pumpWidget(
            shell(
              const BattleIntroductionScreen(),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(63);
          await capture(tester, 'intro-wrongTap-$suffix');
          expect(
            tester.widget<TutorialCoach>(find.byType(TutorialCoach)).feedback,
            isTrue,
          );
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());

          GameStore.instance.introductionStep =
              IntroductionStage.mineConfirm.index;
          await tester.pumpWidget(
            shell(
              const BattleIntroductionScreen(),
              language: language,
              scale: 1.5,
            ),
          );
          await warm(tester);
          tester
              .widget<LunoButton>(
                find.byKey(const ValueKey('introduction-command-mineConfirm')),
              )
              .onPressed!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          expect(
            find.byKey(const ValueKey('card-flight-mine')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<BattleBoard>(find.byType(BattleBoard))
                .view
                .rules
                .mana[PieceColor.white],
            0,
          );
          await capture(tester, 'motion-mine-flight-$suffix', settle: false);
          await tester.pump(const Duration(milliseconds: 140));
          expect(find.byKey(const ValueKey('spell-mine-0')), findsOneWidget);
          await capture(tester, 'motion-mine-impact-$suffix', settle: false);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byKey(const ValueKey('card-flight-mine')), findsNothing);
          expect(
            find.byKey(const ValueKey('introduction-mana-result')),
            findsOneWidget,
          );
          await capture(tester, 'motion-mine-settled-$suffix');
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());

          GameStore.instance.introductionStep =
              IntroductionStage.firstDestination.index;
          await tester.pumpWidget(
            shell(
              const BattleIntroductionScreen(),
              language: language,
              scale: 1.5,
            ),
          );
          await warm(tester);
          tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap(16);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          expect(find.byKey(const ValueKey('hand-shelter')), findsOneWidget);
          expect(
            tester
                .widget<Opacity>(
                  find
                      .descendant(
                        of: find.byType(BattleCardArrival),
                        matching: find.byType(Opacity),
                      )
                      .first,
                )
                .opacity,
            1,
          );
          expect(
            find.byKey(const ValueKey('draw-source-shelter')),
            findsOneWidget,
          );
          expect(
            tester.widget<BattleBoard>(find.byType(BattleBoard)).view.ownHand,
            hasLength(4),
          );
          await capture(tester, 'motion-deck-draw-$suffix', settle: false);
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        }
        GameStore.instance.hasCompletedTutorial = true;
        await tester.pumpWidget(
          shell(
            const HomeScreen(),
            language: language,
            scale: 1.5,
            reduced: true,
          ),
        );
        await capture(tester, 'home-$suffix');
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        for (final step in phase == 'after' ? [1, 2, 3, 4, 5, 6, 7] : [3, 7]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: BattleLessonStage(step: step),
                ),
              ),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await capture(tester, 'academy-$step-$suffix');
          noOverflow(tester);
          if (phase == 'after' && step == 3) {
            final target = find.byKey(const ValueKey('lesson-opponent-chain'));
            expect(
              tester.getRect(target).bottom,
              lessThanOrEqualTo(size.height),
            );
            tester.widget<OutlinedButton>(target).onPressed!();
            await capture(tester, 'academy-3-target-$suffix');
            tester
                .widget<BattleCommand>(
                  find.byKey(const ValueKey('lesson-play-card')),
                )
                .onPressed!();
            await capture(tester, 'academy-3-spent-$suffix');
            noOverflow(tester);
          }
          if (phase == 'after' && step == 7) {
            tester
                .widget<OutlinedButton>(
                  find.byKey(const ValueKey('lesson-card-prophecy')),
                )
                .onPressed!();
            await tester.pump();
            tester
                .widget<BattleCommand>(
                  find.byKey(const ValueKey('lesson-play-card')),
                )
                .onPressed!();
            await capture(tester, 'academy-7-pending-$suffix');
            tester
                .widget<BattleCommand>(
                  find.byKey(const ValueKey('lesson-resolve')),
                )
                .onPressed!();
            await capture(tester, 'academy-7-result-$suffix');
            noOverflow(tester);
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
