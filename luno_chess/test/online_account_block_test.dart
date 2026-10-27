import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'online_response_lifecycle_test.dart' show id, matchView;

void main() {
  for (final failure in const [
    LunoApiException('account-deleted', 403),
    LunoApiException('account-deletion-in-progress', 409),
  ]) {
    testWidgets(
      '${failure.code} stops polling across resume and permits back',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.instance;
        final original = store.data;
        addTearDown(() => store.data = original);
        store.data = PlayerData.initial();
        store.loaded = true;
        var requests = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: OnlineMatchScreen(
              matchId: id,
              initialView: matchView(2),
              uidOverride: () => 'self',
              requestOverride: (path, body) async {
                requests++;
                throw failure;
              },
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text(failure.accountAccessMessage!), findsOneWidget);
        final stoppedAt = requests;
        expect(stoppedAt, 1);
        final dynamic state = tester.state(find.byType(OnlineMatchScreen));
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump(const Duration(seconds: 20));
        expect(requests, stoppedAt);
        expect(
          tester
              .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
              .canPop,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
