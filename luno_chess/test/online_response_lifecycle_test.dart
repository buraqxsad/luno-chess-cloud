import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const id = 'rm_0123456789abcdef0123456789abcdef';
Map<String, dynamic> matchView(int sequence) => {
  'matchId': id,
  'status': 'active',
  'sequence': sequence,
  'viewerColor': 'W',
  'turn': 'W',
  'phase': 'card',
  'player': {'uid': 'self', 'username': 'self'},
  'opponent': {'uid': 'other', 'username': 'other'},
  'board': List<dynamic>.filled(64, null),
  'hand': <String>[],
  'mana': {'W': 0, 'B': 0},
};

void main() {
  for (final endpoint in [
    '/getRankedMatch',
    '/heartbeatRankedMatch',
    '/submitMatchAction',
  ]) {
    for (final scenario in [
      'valid',
      'disposed',
      'account',
      'match',
      'owner',
      'stale',
    ]) {
      testWidgets('late $endpoint respects $scenario boundary', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.instance;
        final original = store.data;
        addTearDown(() => store.data = original);
        store.data = PlayerData.initial();
        store.loaded = true;
        final before = store.data.gold;
        String? uid = 'self';
        final response = Completer<Map<String, dynamic>>();
        var calls = 0;
        final paths = <String>[];
        final requestedMatchIds = <Object?>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: OnlineMatchScreen(
              matchId: id,
              initialView: matchView(2),
              uidOverride: () => uid,
              requestOverride: (path, body) {
                paths.add(path);
                requestedMatchIds.add(body['matchId']);
                if (path != endpoint) {
                  return Future.value({
                    'ok': true,
                    'matchId': id,
                    'view': matchView(2),
                  });
                }
                calls++;
                return response.future;
              },
            ),
          ),
        );
        if (endpoint == '/getRankedMatch') {
          await tester.pump(const Duration(seconds: 2));
        } else if (endpoint == '/heartbeatRankedMatch') {
          final dynamic state = tester.state(find.byType(OnlineMatchScreen));
          state.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();
          await tester.pump();
        } else {
          tester
              .widget<LunoButton>(
                find.byWidgetPredicate(
                  (w) => w is LunoButton && w.label == 'HAMLEYE GEÇ',
                ),
              )
              .onPressed!();
          await tester.pump();
        }
        expect(calls, 1, reason: 'Requests: $paths');
        expect(requestedMatchIds, everyElement(id));
        if (scenario == 'disposed') {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        if (scenario == 'account') uid = 'new-user';
        final next = matchView(scenario == 'stale' ? 1 : 3);
        if (scenario == 'owner') next['player'] = {'uid': 'other'};
        if (scenario == 'match') next['matchId'] = 'another-match';
        response.complete({
          'ok': true,
          'matchId': id,
          'view': next,
          'state': {'gold': 98765},
        });
        await tester.pump();
        expect(store.data.gold, scenario == 'valid' ? 98765 : before);
        if (scenario != 'disposed') {
          final dynamic state = tester.state(find.byType(OnlineMatchScreen));
          expect(state.view['sequence'], scenario == 'valid' ? 3 : 2);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
