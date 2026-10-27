import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/navigation/online_match_recovery.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'helpers/battle_v1_response.dart';

Map<String, dynamic> response() => v1Response();

void main() {
  for (final scenario in [
    'valid',
    'account',
    'id',
    'owner',
    'board',
    'status',
    'covered',
    'disposed',
  ]) {
    testWidgets('online recovery validates $scenario and preserves home', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: Builder(
            builder: (context) {
              home = context;
              return const Scaffold(body: Text('HOME'));
            },
          ),
        ),
      );
      final data = response();
      final view = data['view'] as Map<String, dynamic>;
      if (scenario == 'id') (view['public'] as Map)['matchId'] = 'wrong';
      if (scenario == 'owner') (view['private'] as Map)['viewer'] = 'b';
      if (scenario == 'board') {
        (view['public'] as Map)['rulesJson'] = '{"fen":"invalid"}';
      }
      if (scenario == 'status') data['status'] = 'idle';
      if (scenario == 'covered') {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('COVER')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      final opened = openRecoveredOnlineMatch(
        home,
        data,
        requestedUid: 'self',
        currentUid: scenario == 'account' ? 'other' : 'self',
      );
      expect(opened, scenario == 'valid');
      await tester.pumpAndSettle();
      if (scenario == 'valid') {
        expect(find.byType(BattleV1Screen), findsOneWidget);
        expect(find.text('HOME', skipOffstage: false), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('HOME'), findsOneWidget);
        expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
      } else {
        expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
