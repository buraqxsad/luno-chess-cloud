import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final endReward in [false, true]) {
    testWidgets('season stale claim is guarded, end=$endReward', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      GameStore.instance.data = PlayerData.initial();
      GameStore.instance.loaded = true;
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const SeasonScreen()),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(SeasonScreen));
      final row = <String, dynamic>{
        'id': 'tier1',
        'title': 'İlk adım',
        'state': 'claimable',
        'canClaim': true,
        'minTrophies': 0,
        'reward': {'gold': 100},
      };
      state.setState(() {
        state.loading = false;
        state.error = null;
        state.season = <String, dynamic>{
          'status': endReward ? 'ended' : 'active',
          'seasonNumber': 1,
          'path': [row],
          'endReward': {
            'tier': 'Bronz',
            'reward': {'gold': 200},
          },
        };
      });
      await tester.pump();
      final VoidCallback callback;
      if (endReward) {
        callback =
            tester
                .widget<LunoButton>(
                  find.widgetWithText(LunoButton, 'SEZON SONU ÖDÜLÜNÜ AL'),
                )
                .onPressed!;
      } else {
        callback =
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Ödülü al',
                  ),
                )
                .onPressed!;
      }
      for (final change in ['status', 'claimed', 'locked', 'missing']) {
        state.season['status'] = change == 'status' ? 'syncing' : 'active';
        row['state'] = change == 'claimed' ? 'claimed' : 'claimable';
        row['canClaim'] = change != 'locked';
        if (change == 'missing') {
          state.season['path'] = [];
          state.season['status'] = endReward ? 'ended' : 'active';
          state.season.remove('endReward');
        }
        callback();
        await tester.pump();
        expect(state.claiming, false);
        expect(state.claimingEnd, false);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      callback();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
