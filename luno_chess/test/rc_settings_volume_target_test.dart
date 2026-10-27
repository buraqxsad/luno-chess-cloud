import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  for (final width in [320.0, 768.0]) {
    testWidgets('volume labels retain game font and 48px targets at $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      LunoSettings.instance.language = LunoSettings.languageEnglish;
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell(const SettingsScreen(), language: 'en'));
      await tester.pump();
      if (width > 330) {
        for (final button in tester.widgetList<SegmentedButton<int>>(
          find.byType(SegmentedButton<int>),
        )) {
          expect(
            button.style?.backgroundColor?.resolve({WidgetState.selected}),
            LunoColors.goldDeep,
          );
        }
      }
      for (final label in ['LOW', 'MEDIUM', 'HIGH']) {
        for (final element in find.text(label).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(paragraph.text.style?.fontFamily, 'Nunito');
          final target =
              find
                  .ancestor(
                    of: find.byElementPredicate((e) => e == element),
                    matching: find.byType(InkWell),
                  )
                  .first;
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
        }
        expect(find.text(label), findsNWidgets(2));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
