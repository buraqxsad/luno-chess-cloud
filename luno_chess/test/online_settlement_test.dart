import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'online_response_lifecycle_test.dart' show id, matchView;

Map<String, dynamic> finished() => {
  ...matchView(3),
  'status': 'finished',
  'result': {'winner': 'W'},
};
Map<String, dynamic> settled() => {
  'ok': true,
  'matchId': id,
  'view': finished(),
  'state': {
    'gold': 1234,
    'trophies': 321,
    'stats': {'wins': 7, 'losses': 2, 'draws': 1},
  },
};

void main() {
  for (final mode in ['action', 'heartbeat', 'restored', 'retry']) {
    testWidgets('online terminal state synchronizes once via $mode', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial();
      store.loaded = true;
      var terminal = mode == 'restored' || mode == 'retry';
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: OnlineMatchScreen(
            matchId: id,
            initialView: terminal ? finished() : matchView(2),
            uidOverride: () => 'self',
            requestOverride: (path, body) async {
              if (path == '/submitMatchAction') {
                terminal = true;
                return settled();
              }
              if (path == '/heartbeatRankedMatch') {
                terminal = true;
                return {'ok': true, 'matchId': id, 'view': finished()};
              }
              reads++;
              if (mode == 'retry' && reads == 1) {
                throw StateError('temporary network failure');
              }
              return terminal
                  ? settled()
                  : {'ok': true, 'matchId': id, 'view': matchView(2)};
            },
          ),
        ),
      );
      if (mode == 'action') {
        tester
            .widget<LunoButton>(
              find.byWidgetPredicate(
                (w) => w is LunoButton && w.label == 'HAMLEYE GEÇ',
              ),
            )
            .onPressed!();
      } else if (mode == 'heartbeat') {
        final dynamic state = tester.state(find.byType(OnlineMatchScreen));
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      if (mode == 'retry') {
        expect(store.data.gold, isNot(1234));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      }
      expect(store.data.gold, 1234);
      expect(store.data.trophies, 321);
      expect(store.data.wins, 7);
      expect(store.data.gamesPlayed, 10);
      final finalReads = reads;
      await tester.pump(const Duration(seconds: 8));
      expect(reads, finalReads);
      expect(store.data.gold, 1234);
      expect(store.data.gamesPlayed, 10);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
