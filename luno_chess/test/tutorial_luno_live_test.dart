import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/mentor.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_welcome_screen.dart';
import 'package:luno_chess/widgets/luno_mentor_portrait.dart';
import 'package:luno_chess/widgets/tutorial_coach.dart';

import 'battle_ui/fixtures.dart' show battleFixture;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, boundaryKey;

Future<void> capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('LUNO_LIVE_CAPTURE_DIRECTORY');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setupPracticeTestAssets();

  testWidgets(
    'portrait atlas is transparent, bounded and contains distinct blink poses',
    (tester) async {
      await tester.runAsync(() async {
        final data = await rootBundle.load(LunoMentorPortrait.atlas);
        expect(data.lengthInBytes, lessThan(400000));
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        try {
          final image = (await codec.getNextFrame()).image;
          try {
            expect((image.width, image.height), (640, 640));
            expect(
              image.width * image.height * 4,
              LunoMentorPortrait.decodedBytes,
            );
            final rgba =
                (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List();
            expect(rgba[3], 0, reason: 'Background remains transparent.');
            // Compare visible eye scanlines in frame0 versus the closed-eye frame5.
            List<int> eye(int frame) {
              final originX = frame % 4 * 160, originY = frame ~/ 4 * 160;
              return [
                for (var y = 60; y < 70; y++)
                  for (var x = 64; x < 76; x++)
                    rgba[((originY + y) * 640 + originX + x) * 4],
              ];
            }

            expect(eye(0), isNot(equals(eye(5))));
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      });
    },
  );

  testWidgets(
    'cue animation settles, identical cues do not replay and newest cue wins',
    (tester) async {
      Widget mentor(String cue, {bool reduced = false, bool enabled = true}) =>
          shell(
            Scaffold(
              body: Center(
                child: TickerMode(
                  enabled: enabled,
                  child: BattleMentor(cue: cue, width: 120, height: 140),
                ),
              ),
            ),
            reduced: reduced,
          );
      await tester.pumpWidget(mentor('hello'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('luno-portrait-frame-5')),
        findsOneWidget,
      );
      await warm(tester);
      expect(tester.binding.hasScheduledFrame, false);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'luno-portrait-frame-',
              ),
        ),
        findsNothing,
      );
      await tester.pumpWidget(mentor('hello'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LunoMentorPortrait), findsOneWidget);
      expect(
        tester
            .widget<LunoMentorPortrait>(find.byType(LunoMentorPortrait))
            .progress,
        1,
      );
      // The rebuilt Material theme also has a finite transition.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(mentor('piece'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(mentor('square'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('luno-portrait-frame-1')),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(mentor('square', reduced: true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.hasScheduledFrame, false);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is ResizeImage &&
              (w.image as ResizeImage).imageProvider ==
                  const AssetImage(LunoMentorPortrait.atlas),
        ),
        findsNothing,
      );
      await tester.pumpWidget(mentor('hidden', enabled: false));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'idle gestures sleep, stop when hidden, and respect reduced motion',
    (tester) async {
      Widget stage({bool reduced = false, bool enabled = true}) => shell(
        Scaffold(
          body: TickerMode(
            enabled: enabled,
            child: BattleMentor(cue: 'idle', idle: !reduced),
          ),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(stage());
      await warm(tester);
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpWidget(
        stage(),
      ); // Same cue must keep its sleeping timer.
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<LunoMentorPortrait>(find.byType(LunoMentorPortrait))
            .progress,
        inExclusiveRange(0, 1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(
        tester
            .widget<LunoMentorPortrait>(find.byType(LunoMentorPortrait))
            .progress,
        1,
      );
      expect(tester.binding.hasScheduledFrame, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        tester
            .widget<LunoMentorPortrait>(find.byType(LunoMentorPortrait))
            .progress,
        1,
      );
      await tester.pumpWidget(stage(enabled: false));
      await tester.pump(const Duration(seconds: 8));
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(stage(reduced: true));
      await tester.pump(const Duration(seconds: 8));
      expect(
        tester
            .widget<LunoMentorPortrait>(find.byType(LunoMentorPortrait))
            .progress,
        1,
      );
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['tr', 'en']) {
    for (final scenario in ['close-card', 'special-move', 'ended']) {
      testWidgets(
        'next action agrees with available control $scenario $language',
        (tester) async {
          final p =
              BattlePracticeProgress(0, onboarding: true, guidedMatch: true)
                ..cast = true
                ..discarded = true;
          final state = battleFixture(hand: const [CardId.radar]);
          final draft = RuleDraft(state.rules);
          if (scenario == 'special-move') {
            draft.phase = BattlePhase.chess;
            draft.special = SpecialMoveAuthorization(CardId.pawnAdvance, 12, [
              'e2e3',
            ]);
          } else if (scenario == 'ended') {
            draft.phase = BattlePhase.terminal;
            draft.terminal = const TerminalState('resign');
          }
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SizedBox(
                  width: 296,
                  child: BattlePracticeCoach(
                    progress: p,
                    view: AuthoritativeBattleState(
                      draft.freeze(),
                      state.hidden,
                    ).view(PieceColor.white),
                    selected: scenario == 'close-card' ? CardId.radar : null,
                  ),
                ),
              ),
              language: language,
              reduced: true,
            ),
          );
          await warm(tester);
          final coach = tester.widget<TutorialCoach>(
            find.byType(TutorialCoach),
          );
          final expected =
              scenario == 'close-card'
                  ? (language == 'en' ? 'CLOSE CARD' : 'KARTI KAPAT')
                  : scenario == 'special-move'
                  ? (language == 'en' ? 'MARKED PIECE' : 'İŞARETLİ TAŞ')
                  : (language == 'en' ? 'ATTEMPT ENDED' : 'DENEME BİTTİ');
          expect(coach.heading, contains(expected));
          expect(p.complete, false);
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final language in ['tr', 'en']) {
    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(430, 932), 2.0),
      (const Size(768, 1024), 1.0),
    ]) {
      testWidgets(
        'welcome live mentor and CTA stay readable $language $size $scale',
        (tester) async {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.createForTesting();
          addTearDown(store.dispose);
          await tester.runAsync(store.load);
          await tester.pumpWidget(
            shell(
              BattleWelcomeScreen(playerStore: store),
              language: language,
              scale: scale,
            ),
          );
          await tester.pump(const Duration(milliseconds: 350));
          await tester.runAsync(() async {
            final context = tester.element(find.byType(BattleWelcomeScreen));
            for (final image
                in tester.widgetList<Image>(find.byType(Image)).toList()) {
              await precacheImage(image.image, context);
            }
          });
          await tester.pump();
          await capture(
            tester,
            'welcome-live-$language-${size.width.toInt()}-text$scale',
          );
          await warm(tester);
          for (var step = 0; step < 3; step++) {
            expect(
              tester
                  .widget<TutorialCoach>(find.byType(TutorialCoach))
                  .largePortrait,
              true,
            );
            expect(
              find.byKey(const ValueKey('welcome-next')).hitTestable(),
              findsOneWidget,
            );
            noOverflow(tester);
            await capture(
              tester,
              'welcome-$language-${size.width.toInt()}-text$scale-step$step',
            );
            await tester.tap(find.byKey(const ValueKey('welcome-next')));
            await tester.pumpAndSettle();
            expect(store.welcomeStep, step + 1);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(store.flush);
        },
      );
    }
    testWidgets(
      'first match gives one next action and preserves legal choices $language',
      (tester) async {
        final p = BattlePracticeProgress(
          0,
          onboarding: true,
          guidedMatch: true,
        );
        var state = DeckManager.newBattle(white: p.deck);
        Future<TutorialCoach> show({int? selectedPiece}) async {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SizedBox(
                  width: 296,
                  child: BattlePracticeCoach(
                    progress: p,
                    view: state.view(PieceColor.white),
                    selectedPiece: selectedPiece,
                  ),
                ),
              ),
              language: language,
              reduced: true,
            ),
          );
          await warm(tester);
          return tester.widget<TutorialCoach>(find.byType(TutorialCoach));
        }

        final before =
            BattleRulesCore.legalActions(
              state.view(PieceColor.white),
            ).map((a) => a.key).toList();
        var coach = await show();
        expect(
          coach.heading,
          contains(language == 'en' ? 'PICK A PIECE' : 'TAŞ SEÇ'),
        );
        expect(
          coach.text,
          contains(
            language == 'en' ? 'Tap any white piece' : 'beyaz taşına dokun',
          ),
        );
        coach = await show(selectedPiece: 12);
        expect(
          coach.heading,
          contains(language == 'en' ? 'PICK A SQUARE' : 'KARE SEÇ'),
        );
        expect(
          coach.text,
          contains(language == 'en' ? 'Now tap one' : 'Şimdi ışıklı'),
        );
        expect(
          BattleRulesCore.legalActions(
            state.view(PieceColor.white),
          ).map((a) => a.key),
          before,
        );
        final after = DeckManager.apply(state, const ChessMoveAction('e2e4'));
        p.accepted(
          const ChessMoveAction('e2e4'),
          state.view(PieceColor.white),
          after.view(PieceColor.white),
        );
        state = after;
        coach = await show();
        expect(
          coach.heading,
          contains(language == 'en' ? 'LUNO’S TURN' : 'SIRA LUNO’DA'),
        );
        expect(p.moves, 1);
        expect(p.complete, false);
        await capture(tester, 'first-move-$language');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
