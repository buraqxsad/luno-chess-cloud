import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/action_guide.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/fixtures.dart' show battleFixture;
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture, captureKey;
import 'visual_polish_v203_test.dart' show shell;

Future<void> capturePhase(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(captureKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('qa/v217/visual');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final scale in [1.0, 1.1, 1.5, 2.0]) {
      for (final firstTurn in [true, false]) {
        testWidgets('compact phase is readable $language $scale '
            '${firstTurn ? 'chess' : 'card'}', (tester) async {
          await renderBattle(
            tester,
            state: battleFixture(firstTurn: firstTurn),
            size: const Size(320, 568),
            language: language,
            textScale: scale,
            theme: LunoTheme.darkFor(language),
          );
          final guide = find.byType(BattleActionGuide);
          expect(
            tester.getSize(find.byType(BattleBoard)).width,
            greaterThanOrEqualTo(192),
            reason: 'Enlarged text must not shrink chess cells below 24px',
          );
          // This portrait layout keeps the board above a full-width status
          // scroll at every text scale. Narrow-guide behavior is checked below
          // with genuinely narrow constraints rather than inferred from scale.
          expect(tester.getSize(guide).width, greaterThanOrEqualTo(280));
          expect(
            find.byKey(const ValueKey('battle-compact-phase-label')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: guide,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.liveRegion == true,
              ),
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byType(BattleBoard));
          await tester.pumpAndSettle();
          final board = tester.getRect(find.byType(BattleBoard));
          expect(board.top, greaterThanOrEqualTo(24));
          expect(board.bottom, lessThanOrEqualTo(544));
          if (scale > 1.1) {
            await capturePhase(
              tester,
              'large-text-board-$language-${firstTurn ? 'chess' : 'card'}',
            );
          }
          final detail = find.byKey(const ValueKey('battle-next-action'));
          await tester.ensureVisible(detail);
          await tester.pumpAndSettle();
          expect(detail.hitTestable(), findsOneWidget);
          expect(tester.widget<Text>(detail).data, isNotEmpty);
          final instruction = tester.getRect(detail);
          expect(instruction.top, greaterThanOrEqualTo(24));
          expect(instruction.bottom, lessThanOrEqualTo(544));
          await capturePhase(
            tester,
            'compact-phase-$language-$scale-${firstTurn ? 'chess' : 'card'}',
          );
          expect(
            find.byKey(const ValueKey('battle-next-action')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await closeCapture(tester);
        });
        if (scale <= 1.1) {
          testWidgets(
            'narrow phase keeps label and instruction $language $scale '
            '${firstTurn ? 'chess' : 'card'}',
            (tester) async {
              tester.view.physicalSize = const Size(320, 568);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final semantics = tester.ensureSemantics();
              try {
                final phaseLabel =
                    firstTurn
                        ? (language == 'tr'
                            ? '2 · Taş hamlesi'
                            : '2 · Chess move')
                        : (language == 'tr' ? 'Kart / geç' : 'Card / skip');
                final instruction =
                    language == 'tr'
                        ? 'Sıradaki hamleni seç.'
                        : 'Choose your next action.';
                await tester.pumpWidget(
                  shell(
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 92,
                            child: BattleActionGuide(
                              phase:
                                  firstTurn
                                      ? BattlePhase.chess
                                      : BattlePhase.card,
                              ownTurn: true,
                              firstTurn: firstTurn,
                              instruction: instruction,
                            ),
                          ),
                        ],
                      ),
                    ),
                    language: language,
                    scale: scale,
                    reduced: true,
                  ),
                );
                await tester.pumpAndSettle();
                final compact = tester.widget<Text>(
                  find.byKey(const ValueKey('battle-compact-phase-label')),
                );
                expect(compact.softWrap, isFalse);
                expect(compact.maxLines, 2);
                expect(
                  compact.data,
                  firstTurn
                      ? (language == 'tr' ? '2\nHamle' : '2\nMove')
                      : (language == 'tr' ? '1\nKart' : '1\nCard'),
                );
                expect(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is Tooltip && widget.message == phaseLabel,
                  ),
                  findsOneWidget,
                );
                // The live-region parent can merge the phase and instruction
                // into one accessibility node; the full phase must remain read.
                expect(
                  find.bySemanticsLabel(RegExp(RegExp.escape(phaseLabel))),
                  findsOneWidget,
                );
                expect(
                  tester.getSize(find.byType(BattleActionGuide)).height,
                  lessThanOrEqualTo(
                    (12 * scale * 1.15).ceilToDouble() * 2 + 55,
                  ),
                  reason:
                      'The side rail must not fragment a phase into many lines',
                );
                final detail = find.byKey(
                  const ValueKey('battle-narrow-instruction'),
                );
                expect(detail.hitTestable(), findsOneWidget);
                await tester.tap(detail);
                await tester.pumpAndSettle();
                final expanded = find.byKey(
                  const ValueKey('battle-next-action'),
                );
                expect(expanded.hitTestable(), findsOneWidget);
                expect(tester.widget<Text>(expanded).data, instruction);
                expect(tester.takeException(), isNull);
                await closeCapture(tester);
              } finally {
                semantics.dispose();
              }
            },
          );
        }
      }
    }
  }
}
