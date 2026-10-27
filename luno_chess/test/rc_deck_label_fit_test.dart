import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';

import 'battle_deck_account_test.dart' show app;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('deck names keep whole words at 320px $language $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: SingleChildScrollView(
                child: BattleSelectedDeckGrid(cards: CardId.values),
              ),
            ),
            language,
            textScale: scale,
          ),
        );
        await tester.pump();
        final paragraphs = tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(BattleSelectedDeckGrid),
            matching: find.byType(RichText),
          ),
        );
        for (final paragraph in paragraphs) {
          final text = paragraph.text.toPlainText();
          if (int.tryParse(text) != null) continue;
          final widths = text.split(RegExp(r'\s+')).map((word) {
            final painter = TextPainter(
              text: TextSpan(text: word, style: paragraph.text.style),
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          });
          expect(
            paragraph.size.width + .1,
            greaterThanOrEqualTo(widths.reduce(math.max)),
            reason: 'Whole word does not fit: $text',
          );
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
