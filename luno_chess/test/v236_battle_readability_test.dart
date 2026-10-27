import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart'
    show renderBattle, captureKey, expectNoBattleLayoutError;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  const stage = String.fromEnvironment(
    'LUNO_V236_CAPTURE_STAGE',
    defaultValue: 'after',
  );
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        final name =
            '$language ${size.width.toInt()}x${size.height.toInt()} $scale';
        testWidgets('board readable $name', (tester) async {
          await renderBattle(
            tester,
            size: size,
            language: language,
            textScale: scale,
            longNames: true,
          );
          await capture(
            tester,
            name.replaceAll(' ', '-'),
            repaintKey: captureKey,
            outputDirectory: 'qa/v236/battle-$stage',
          );
          final board = tester.getRect(find.byType(BattleBoard));
          expect(
            board.width,
            greaterThanOrEqualTo(math.min(560, size.width) - 16 - .01),
            reason:
                'Secondary information must not squeeze the board into a phone sidebar',
          );
          expect(board.top, greaterThanOrEqualTo(24));
          expect(board.bottom, lessThanOrEqualTo(size.height - 24 + .01));
          final hand = find.byType(BattleHand);
          await tester.ensureVisible(hand);
          await tester.pumpAndSettle();
          expectNoBattleLayoutError(tester);
          final boardAfter = tester.getRect(find.byType(BattleBoard));
          expect(
            boardAfter,
            board,
            reason: 'Browsing the hand must not scroll the board off screen',
          );
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
