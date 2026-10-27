import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (var step = 0; step < 10; step++) {
      testWidgets('RC tutorial rendered step $step $language', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..tutorialStep = step;
        addTearDown(store.dispose);
        LunoSettings.instance.language =
            language == 'en'
                ? LunoSettings.languageEnglish
                : LunoSettings.languageTurkish;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            TutorialScreen(onboarding: true, playerStore: store),
            language: language,
            reduced: true,
          ),
        );
        await tester.pump();
        await capture(tester, 'tutorial-step-$step-$language');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
