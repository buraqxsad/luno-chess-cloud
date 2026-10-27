import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show visualOnline;

void expectWholeWord(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  final widths = label.split(RegExp(r'\s+')).map((word) {
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
    reason: 'Whole word does not fit: $label',
  );
  expect(paragraph.didExceedMaxLines, isFalse);
}

void main() {
  setupPracticeTestAssets();
  for (final page in ['settings', 'friends', 'arena', 'arena-tr']) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('$page keeps whole labels at 320px x$scale', (tester) async {
        SharedPreferences.setMockInitialValues({});
        GameStore.instance
          ..loaded = true
          ..data = (PlayerData.initial()..trophies = 450);
        LunoSettings.instance.language = LunoSettings.languageEnglish;
        final online = await visualOnline();
        addTearDown(online.dispose);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final screen = switch (page) {
          'settings' => SettingsScreen(online: online),
          'friends' => FriendsScreen(online: online),
          _ => const ArenasScreen(),
        };
        await tester.pumpWidget(
          shell(
            screen,
            language: page == 'arena-tr' ? 'tr' : 'en',
            scale: scale,
            reduced: true,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final label = switch (page) {
          'settings' => 'Language',
          'friends' => 'LEADERBOARD',
          'arena-tr' => 'HÜKÜMDAR · ARENA 3',
          _ => 'SOVEREIGN · ARENA 3',
        };
        expectWholeWord(tester, label);
        if (page == 'friends') {
          await Scrollable.ensureVisible(tester.element(find.text(label)));
          await tester.pump();
          await tester.tap(find.text(label));
          await tester.pump();
          final dynamic state = tester.state(find.byType(FriendsScreen));
          expect(state.tab, 2);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
