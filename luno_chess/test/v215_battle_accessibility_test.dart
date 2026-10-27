import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_ui/visual_test.dart' show renderBattle;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final height in [568.0, 740.0]) {
      testWidgets(
        'narrow enlarged battle keeps readable board and guide $language $height',
        (tester) async {
          await renderBattle(
            tester,
            size: Size(320, height),
            language: language,
            textScale: 1.5,
            theme: LunoTheme.darkFor(language),
          );
          expect(
            tester.getSize(find.byType(BattleBoard)).width,
            greaterThanOrEqualTo(192),
          );
          final copy = find.byKey(const ValueKey('battle-next-action'));
          expect(copy, findsOneWidget);
          await tester.ensureVisible(copy);
          await tester.pumpAndSettle();
          expect(copy.hitTestable(), findsOneWidget);
          final text = tester.widget<Text>(copy);
          expect(text.maxLines, isNull);
          expect(text.data, isNotEmpty);
          expect(tester.getSize(copy).width, greaterThanOrEqualTo(280));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
