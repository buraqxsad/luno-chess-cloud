import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/home_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final size in [const Size(640, 360), const Size(844, 390)]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('home landscape $language $size scale $scale', (
          tester,
        ) async {
          GameStore.instance.data =
              PlayerData.initial()
                ..username = 'luno_player'
                ..trophies = 12345
                ..gold = 123456
                ..gems = 1234;
          GameStore.instance.loaded = true;
          GameStore.instance.firstSessionMatchesStarted = 2;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              const HomeScreen(),
              language: language,
              scale: scale,
              reduced: true,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final battle = find.text(
            language == 'en' ? 'ENTER BATTLE' : 'SAVAŞA GİR',
          );
          expect(battle, findsOneWidget);
          final rect = tester.getRect(battle);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          for (final element in find.byType(RichText).evaluate()) {
            if (element.renderObject case final RenderParagraph paragraph) {
              expect(
                paragraph.didExceedMaxLines,
                false,
                reason: paragraph.text.toPlainText(),
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
