import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    testWidgets(
      'next tutorial lesson starts at top after scrolling $language',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.createForTesting()..loaded = true;
        addTearDown(store.dispose);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            TutorialScreen(onboarding: true, playerStore: store),
            language: language,
            scale: 1.5,
            reduced: true,
          ),
        );
        await tester.pump();
        final scroll =
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
        expect(scroll.maxScrollExtent, greaterThan(20));
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pump();
        final next = tester.widget<LunoButton>(find.byType(LunoButton));
        next.onPressed!();
        await tester.pump();
        await tester.pump();
        expect(store.tutorialStep, 1);
        final nextScroll =
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
        expect(nextScroll.pixels, 0);
        nextScroll.jumpTo(nextScroll.maxScrollExtent);
        await tester.pump();
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text(language == 'tr' ? 'ÖNCEKİ' : 'PREVIOUS'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed!();
        await tester.pump();
        await tester.pump();
        expect(store.tutorialStep, 0);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          0,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
