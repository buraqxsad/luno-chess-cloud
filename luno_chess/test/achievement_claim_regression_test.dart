import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('achievement stale callbacks recheck eligibility and claims', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const AchievementsScreen()),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(AchievementsScreen));
    final row = <String, dynamic>{
      'id': 'first_win',
      'title': 'İlk Zafer',
      'target': 1,
      'progress': 1,
      'statKey': 'wins',
      'reward': {'gold': 100},
    };
    state.setState(() {
      state.loading = false;
      state.error = null;
      state.serverAchievements = <Map<String, dynamic>>[row];
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
    for (final change in [
      'row-claimed',
      'state-claimed',
      'incomplete',
      'removed',
    ]) {
      row['claimed'] = change == 'row-claimed';
      row['progress'] = change == 'incomplete' ? 0 : 1;
      state.state = <String, dynamic>{
        if (change == 'state-claimed')
          'achievementsClaimed': {'first_win': 123},
      };
      if (change == 'removed') {
        state.serverAchievements = <Map<String, dynamic>>[
          {'id': 'other', 'target': 1, 'progress': 0},
        ];
      }
      callback();
      await tester.pump();
      expect(state.claiming, isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    callback();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
