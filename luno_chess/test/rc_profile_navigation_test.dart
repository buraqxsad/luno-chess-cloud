import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

void main() {
  setupPracticeTestAssets();
  for (final edit in [false, true]) {
    testWidgets(
      'profile ${edit ? 'edit' : 'settings'} ignores duplicate and covered callbacks',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        GameStore.instance
          ..loaded = true
          ..data = PlayerData.initial();
        await tester.pumpWidget(
          MaterialApp(theme: LunoTheme.dark, home: const ProfileScreen()),
        );
        final button = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.tooltip == (edit ? 'Profili düzenle' : 'Ayarlar'),
        );
        final action = tester.widget<IconButton>(button).onPressed!;
        action();
        action();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        final target = find.byType(
          edit ? EditProfileScreen : SettingsScreen,
          skipOffstage: false,
        );
        expect(target, findsOneWidget);
        action();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(target, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        action();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
