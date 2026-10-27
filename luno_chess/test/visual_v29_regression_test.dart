import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'season displays modern server deadline and guards missing reward id',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      GameStore.instance.data = PlayerData.initial();
      GameStore.instance.loaded = true;
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const SeasonScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final dynamic state = tester.state(find.byType(SeasonScreen));
      state.setState(() {
        state.loading = false;
        state.error = null;
        state.season = <String, dynamic>{
          'status': 'active',
          'serverTime': 1800000000000,
          'seasonEndAt': 1800604800000,
          'nextTrophies': 300,
          'path': [
            {
              'title': 'Test',
              'canClaim': true,
              'state': 'unlocked',
              'reward': {'gold': 10},
            },
          ],
        };
      });
      await tester.pump();
      expect(find.textContaining('7 gün 0 saat kaldı'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Ödülü al',
        ),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
