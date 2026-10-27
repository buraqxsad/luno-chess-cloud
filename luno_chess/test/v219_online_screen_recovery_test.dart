import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'helpers/battle_v1_response.dart';

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
    await GameStore.instance.load();
  });

  testWidgets('terminal screen permits pending cleanup without resending acceptance', (tester) async {
    var removalSucceeds = false, sends = 0;
    final terminal = v1Response(version: 1)..['status'] = 'finished';
    final public = (terminal['view'] as Map)['public'] as Map;
    public['result'] = {'reason': 'resign', 'winner': 'b'};
    public['settlementStatus'] = 'complete';
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: v1Response(),
      persistPending: (value) async {
        if (value == null && !removalSucceeds) throw StateError('remove failed');
      },
      request: (path, _) async {
        if (path == '/resignBattleV1') sends++;
        return terminal;
      },
    );
    addTearDown(controller.dispose);
    await controller.resign();
    await tester.pumpWidget(shell(BattleV1Screen(controllerOverride: controller), reduced: true));
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('terminal-pending-retry'));
    expect(retry, findsOneWidget);
    removalSucceeds = true;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(controller.hasPendingIntent, isFalse);
    expect(sends, 1);
    expect(find.byKey(const ValueKey('terminal-pending-retry')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real battle screen forwards synchronization epoch to cast notice', (tester) async {
    final response = v1Response();
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: response,
      persistPending: (_) async {},
      request: (_, _) async => response,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(shell(BattleV1Screen(controllerOverride: controller), reduced: true));
    await tester.pumpAndSettle();
    expect(tester.widget<BattleCastNotice>(find.byType(BattleCastNotice)).synchronizationEpoch, 0);
    await controller.reconnect();
    await tester.pump();
    expect(tester.widget<BattleCastNotice>(find.byType(BattleCastNotice)).synchronizationEpoch, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
