import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/navigation/luno_route.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:luno_chess/widgets/luno_polish.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, noOverflow, visibleTap, boundaryKey;

const target = ValueKey('press-target');

Widget pressShell({
  bool enabled = true,
  bool ticking = true,
  bool reduced = false,
  VoidCallback? onTap,
}) => shell(
  Scaffold(
    body: Center(
      child: TickerMode(
        enabled: ticking,
        child: LunoPressFeedback(
          enabled: enabled,
          child: SizedBox(
            width: 180,
            height: 70,
            child: InkWell(
              key: target,
              onTap: onTap,
              child: const Text('Press'),
            ),
          ),
        ),
      ),
    ),
  ),
  reduced: reduced,
);

AnimatedScale pressState(WidgetTester tester) => tester.widget<AnimatedScale>(
  find
      .descendant(
        of: find.byType(LunoPressFeedback),
        matching: find.byType(AnimatedScale),
      )
      .first,
);

String goalState(WidgetTester tester, String id) =>
    tester
        .widget<Semantics>(find.byKey(ValueKey('lesson-goal-$id')))
        .properties
        .value!;

Future<void> capture(WidgetTester tester, String name) async {
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(boundaryKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v211').create(recursive: true);
    await File('qa/v211/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> lesson(
  WidgetTester tester,
  int step, {
  String language = 'en',
  double scale = 1,
}) async {
  await tester.pumpWidget(
    shell(
      Scaffold(
        body: SingleChildScrollView(child: BattleLessonStage(step: step)),
      ),
      language: language,
      scale: scale,
      reduced: true,
    ),
  );
  await warm(tester);
}

Future<void> makeMove(WidgetTester tester) async {
  final view = tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
  final action =
      BattleRulesCore.legalActions(view).whereType<ChessMoveAction>().first;
  int square(String name) =>
      name.codeUnitAt(0) - 97 + 8 * (int.parse(name[1]) - 1);
  await visibleTap(tester, 'square-${square(action.uci.substring(0, 2))}');
  await visibleTap(tester, 'square-${square(action.uci.substring(2, 4))}');
}

void main() {
  setupPracticeTestAssets();

  testWidgets(
    'press begins immediately, animates in 70ms and activates only on up',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(pressShell(onTap: () => taps++));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(target)),
      );
      await tester.pump();
      expect(pressState(tester).scale, .985);
      expect(pressState(tester).duration, LunoMotion.pressDown);
      expect(taps, 0);
      await gesture.up();
      await tester.pump();
      expect(pressState(tester).scale, 1);
      expect(pressState(tester).duration, LunoMotion.press);
      expect(taps, 1);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('second pointer cannot release the first pointer press', (
    tester,
  ) async {
    await tester.pumpWidget(pressShell(onTap: () {}));
    final at = tester.getCenter(find.byKey(target));
    final first = await tester.startGesture(at, pointer: 11);
    final second = await tester.startGesture(
      at + const Offset(10, 0),
      pointer: 12,
    );
    await second.up();
    await tester.pump();
    expect(pressState(tester).scale, .985);
    await first.up();
    await tester.pumpAndSettle();
    expect(pressState(tester).scale, 1);
  });

  testWidgets(
    'drag cancels visual press and native tap, returning does not reactivate',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(pressShell(onTap: () => taps++));
      final at = tester.getCenter(find.byKey(target));
      final gesture = await tester.startGesture(at);
      await tester.pump();
      await gesture.moveTo(at + const Offset(0, 60));
      await tester.pump();
      expect(pressState(tester).scale, 1);
      await gesture.moveTo(at);
      await tester.pump();
      expect(pressState(tester).scale, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    },
  );

  testWidgets('pointer cancellation releases press without activation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(pressShell(onTap: () => taps++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(target)),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(pressState(tester).scale, 1);
    expect(taps, 0);
  });

  for (final mode in ['disabled', 'hidden', 'background', 'reduced']) {
    testWidgets('$mode resets a held press and allows a fresh enabled press', (
      tester,
    ) async {
      await tester.pumpWidget(pressShell(onTap: () {}));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(target)),
      );
      await tester.pump();
      expect(pressState(tester).scale, .985);
      if (mode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
      } else {
        await tester.pumpWidget(
          pressShell(
            enabled: mode != 'disabled',
            ticking: mode != 'hidden',
            reduced: mode == 'reduced',
            onTap: () {},
          ),
        );
      }
      expect(pressState(tester).scale, 1);
      await gesture.cancel();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(pressShell(onTap: () {}));
      final fresh = await tester.startGesture(
        tester.getCenter(find.byKey(target)),
      );
      await tester.pump();
      expect(pressState(tester).scale, .985);
      await fresh.cancel();
      await tester.pumpAndSettle();
      noOverflow(tester);
    });
  }

  testWidgets('secondary mouse button cannot imitate a primary press', (
    tester,
  ) async {
    await tester.pumpWidget(pressShell(onTap: () {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(target)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(pressState(tester).scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  for (final language in ['tr', 'en']) {
    testWidgets('shared loading CTA is localized and disabled in $language', (
      tester,
    ) async {
      var taps = 0;
      final label = language == 'en' ? 'CONTINUE' : 'DEVAM ET';
      Widget button(bool loading) => shell(
        Scaffold(
          body: Center(
            child: LunoButton(
              label: label,
              loading: loading,
              onPressed: () => taps++,
            ),
          ),
        ),
        language: language,
        reduced: true,
      );
      await tester.pumpWidget(button(false));
      await warm(tester);
      final size = tester.getSize(find.byType(LunoButton));
      await tester.pumpWidget(button(true));
      await warm(tester);
      final copy = language == 'en' ? 'PREPARING...' : 'HAZIRLANIYOR...';
      // Loading preserves the action's visible label and geometry. Its pending
      // state is localized in semantics and indicated by the reduced-motion icon.
      expect(find.text(label), findsOneWidget);
      expect(tester.getSize(find.byType(LunoButton)), size);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final semantics =
          tester
              .widgetList<Semantics>(find.byType(Semantics))
              .where((s) => s.properties.value == copy)
              .single;
      expect(semantics.properties.enabled, false);
      expect(semantics.properties.liveRegion, true);
      expect(semantics.properties.label, label);
      expect(
        tester.getSemantics(find.byWidget(semantics)),
        matchesSemantics(
          label: label,
          value: copy,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );
      await tester.tap(find.byType(LunoButton));
      await tester.pump();
      expect(taps, 0);
      await tester.pumpWidget(button(false));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
      expect(
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byType(LunoButton),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNotNull,
      );
      await tester.tap(find.byType(LunoButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      noOverflow(tester);
    });
  }

  testWidgets(
    'actual battle drag never selects or submits; taps and confirmation remain distinct',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness(
        hand: const [
          CardId.shelter,
          CardId.chain,
          CardId.lockedSquare,
          CardId.freeze,
        ],
      );
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(
        shell(
          BattleV1Screen(
            controllerOverride: h.controller,
            clockOverride: (_) => 300000,
          ),
        ),
      );
      await warm(tester);
      final card = find.byKey(const ValueKey('hand-shelter'));
      final at = tester.getCenter(card);
      final drag = await tester.startGesture(at);
      await tester.pump();
      final press = find.descendant(
        of: card,
        matching: find.byType(AnimatedScale),
      );
      expect(tester.widget<AnimatedScale>(press.first).scale, .94);
      await drag.moveTo(at + const Offset(0, -40));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(press.first).scale, 1);
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.widget<BattleCardTile>(card).selected, false);
      expect(h.sent, isEmpty);
      await capture(tester, 'battle-ready');
      final touch = await tester.startGesture(at);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
        await capture(
          tester,
          'battle-touch-${frame.toString().padLeft(2, '0')}',
        );
      }
      expect(h.sent, isEmpty);
      await touch.up();
      for (var frame = 4; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
        await capture(
          tester,
          'battle-touch-${frame.toString().padLeft(2, '0')}',
        );
      }
      expect(tester.widget<BattleCardTile>(card).selected, true);
      expect(h.sent, isEmpty);
      await visibleTap(tester, 'square-12');
      expect(h.sent, isEmpty);
      await visibleTap(tester, 'play-card');
      expect(h.sent.map((action) => action.key), ['play:shelter:12:']);
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await capture(
          tester,
          'battle-cast-${frame.toString().padLeft(2, '0')}',
        );
      }
      await capture(tester, 'battle-after-cast');
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'route ignores invisible and departing taps; reduced=$reduced',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: child!,
                ),
            home: const Scaffold(body: Text('Home')),
          ),
        );
        navigator.currentState!.push(
          lunoRoute<void>(
            Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Destination'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.tap(find.text('Destination'), warnIfMissed: false);
        expect(taps, 0);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Destination'));
        expect(taps, 1);
        navigator.currentState!.pop();
        await tester.pump();
        await tester.tap(find.text('Destination'), warnIfMissed: false);
        expect(taps, 1);
        await tester.pumpAndSettle();
        expect(find.text('Destination'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['tr', 'en']) {
    final complete = language == 'en' ? 'Complete' : 'Tamamlandı';
    final pending = language == 'en' ? 'Pending' : 'Bekliyor';
    for (final step in [1, 2, 6]) {
      testWidgets(
        'lesson $step tracks actual phase and move completion in $language',
        (tester) async {
          await lesson(tester, step, language: language);
          final finalGoal = step == 6 ? 'draw' : 'move';
          expect(goalState(tester, finalGoal), pending);
          if (step != 1) {
            expect(goalState(tester, 'card'), pending);
            await visibleTap(
              tester,
              step == 2 ? 'lesson-discard' : 'lesson-pass',
            );
            expect(goalState(tester, 'card'), complete);
            expect(goalState(tester, finalGoal), pending);
          }
          await makeMove(tester);
          expect(goalState(tester, finalGoal), complete);
          if (step != 1) expect(goalState(tester, 'card'), complete);
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    for (final step in [3, 4, 5, 7]) {
      for (final card in battleLessonCards(step)) {
        testWidgets(
          'lesson $step ${card.wire} goals follow the rule engine in $language',
          (tester) async {
            await lesson(tester, step, language: language);
            await visibleTap(tester, 'lesson-card-${card.wire}');
            expect(goalState(tester, 'card'), pending);
            if (step == 3) {
              tester
                  .widget<Slider>(find.byKey(const ValueKey('lesson-mana')))
                  .onChanged!(6);
              await tester.pump();
            }
            if (cardDefinitions[card]!.target == CardTargetType.opponentCard) {
              final options = tester.widgetList<OutlinedButton>(
                find.byType(OutlinedButton),
              );
              final targetButton = options.firstWhere(
                (button) => button.key.toString().contains('lesson-opponent-'),
              );
              await tester.ensureVisible(find.byKey(targetButton.key!));
              await tester.tap(find.byKey(targetButton.key!));
              await tester.pump();
            } else if (cardDefinitions[card]!.target != CardTargetType.none) {
              final view =
                  tester.widget<BattleBoard>(find.byType(BattleBoard)).view;
              final target =
                  BattleRulesCore.legalActions(view)
                          .whereType<PlayCardAction>()
                          .firstWhere((a) => a.card == card)
                          .target!
                      as int;
              await visibleTap(tester, 'square-$target');
            }
            await visibleTap(tester, 'lesson-play-card');
            expect(goalState(tester, 'card'), complete);
            if (step == 7) {
              expect(find.byType(BattleBoard), findsNothing);
              expect(
                find.textContaining(
                  language == 'en' ? 'Now tap your piece' : 'Şimdi bir taşına',
                ),
                findsNothing,
              );
              if (card == CardId.prophecy) {
                expect(goalState(tester, 'information'), pending);
                await visibleTap(tester, 'lesson-resolve');
              }
              expect(goalState(tester, 'information'), complete);
              expect(
                find.text(
                  language == 'en'
                      ? 'Information card complete. Continue to the next lesson.'
                      : 'Bilgi kartı tamamlandı. Sonraki adıma geçebilirsin.',
                ),
                findsOneWidget,
              );
            } else {
              expect(goalState(tester, 'move'), pending);
              await makeMove(tester);
              expect(goalState(tester, 'move'), complete);
            }
            await tester.ensureVisible(
              find.byTooltip(language == 'en' ? 'Try again' : 'Yeniden dene'),
            );
            await tester.tap(
              find.byTooltip(language == 'en' ? 'Try again' : 'Yeniden dene'),
            );
            await tester.pumpAndSettle();
            expect(goalState(tester, 'card'), pending);
            expect(
              goalState(tester, step == 7 ? 'information' : 'move'),
              pending,
            );
            noOverflow(tester);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    for (final language in ['tr', 'en']) {
      for (final step in [4, 7]) {
        testWidgets('lesson $step layout $size $language at 1.8 text scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await lesson(tester, step, language: language, scale: 1.8);
          await capture(
            tester,
            'lesson-$step-${size.width.toInt()}-${size.height.toInt()}-$language',
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('lesson-goal-card')),
          );
          await tester.pumpAndSettle();
          await capture(
            tester,
            'lesson-$step-${size.width.toInt()}-${size.height.toInt()}-$language-scrolled',
          );
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
