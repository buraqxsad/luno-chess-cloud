import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/action_guide.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/fixtures.dart' show battleFixture;
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture, captureKey;

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
          if (scale <= 1.1) {
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
                    widget is Tooltip &&
                    widget.message ==
                        (firstTurn
                            ? (language == 'tr'
                                ? '2 · Taş hamlesi'
                                : '2 · Chess move')
                            : (language == 'tr'
                                ? 'Kart / geç'
                                : 'Card / skip')),
              ),
              findsOneWidget,
            );
            expect(
              tester.getSize(guide).height,
              lessThanOrEqualTo((12 * scale * 1.15).ceilToDouble() * 2 + 55),
              reason: 'The side rail must not fragment a phase into many lines',
            );
          } else {
            expect(tester.getSize(guide).width, greaterThanOrEqualTo(280));
            await tester.ensureVisible(find.byType(BattleBoard));
            await tester.pumpAndSettle();
            final board = tester.getRect(find.byType(BattleBoard));
            expect(board.top, greaterThanOrEqualTo(24));
            expect(board.bottom, lessThanOrEqualTo(544));
            await capturePhase(
              tester,
              'large-text-board-$language-${firstTurn ? 'chess' : 'card'}',
            );
          }
          final detail = find.byKey(
            ValueKey(
              scale <= 1.1 ? 'battle-narrow-instruction' : 'battle-next-action',
            ),
          );
          await tester.ensureVisible(detail);
          await tester.pumpAndSettle();
          expect(detail.hitTestable(), findsOneWidget);
          await capturePhase(
            tester,
            'compact-phase-$language-$scale-${firstTurn ? 'chess' : 'card'}',
          );
          if (scale <= 1.1) {
            await tester.tap(detail);
            await tester.pumpAndSettle();
          }
          expect(
            find.byKey(const ValueKey('battle-next-action')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await closeCapture(tester);
        });
      }
    }
  }
}
