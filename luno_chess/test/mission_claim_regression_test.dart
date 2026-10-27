import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mission stale claim respects current reward state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const MissionsScreen()),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(MissionsScreen));
    final row = <String, dynamic>{
      'id': 'd1',
      'title': 'Zafer',
      'target': 1,
      'progress': 1,
      'reward': {'gold': 150},
    };
    state.setState(() {
      state.loading = false;
      state.error = null;
      state.missions = <String, List<Map<String, dynamic>>>{
        'daily': [row],
        'weekly': [],
        'special': [],
      };
    });
    await tester.pump();
    final callback =
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Ödülü al',
              ),
            )
            .onPressed!;
    for (final change in ['claimed', 'incomplete', 'removed']) {
      row['claimed'] = change == 'claimed';
      row['progress'] = change == 'incomplete' ? 0 : 1;
      if (change == 'removed') state.missions['daily']!.clear();
      callback();
      await tester.pump();
      expect(state.claiming, false);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    callback();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
