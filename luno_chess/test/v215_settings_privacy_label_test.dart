import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    testWidgets('privacy settings words fit a narrow enlarged row $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = LunoSettings(deviceLocale: Locale(language));
      await tester.runAsync(settings.load);
      await tester.pumpWidget(
        shell(
          SettingsScreen(settings: settings),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      final row = find.byKey(const ValueKey('product-privacy-settings'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final copy = language == 'en' ? 'Privacy choices' : 'Veri tercihleri';
      final text = find.descendant(of: row, matching: find.text(copy));
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
      for (final word in RegExp(r'\S+').allMatches(copy)) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        );
        expect(
          boxes.map((box) => box.top).toSet(),
          hasLength(1),
          reason: word.group(0),
        );
      }
      expect(tester.widget<ListTile>(row).onTap, isNotNull);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
