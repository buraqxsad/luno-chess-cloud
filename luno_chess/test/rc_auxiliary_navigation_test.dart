import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/widgets/game_time_control_picker.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  setupPracticeTestAssets();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial();
  });

  for (final arena in [false, true]) {
    testWidgets(
      'play ${arena ? 'arena' : 'deck'} owns duplicate and stale entry',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(shell(const PlayModeScreen()));
        late VoidCallback action;
        if (arena) {
          final ink =
              find
                  .ancestor(
                    of: find.text('MEVCUT ARENA'),
                    matching: find.byType(InkWell),
                  )
                  .first;
          action = tester.widget<InkWell>(ink).onTap!;
        } else {
          action =
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is IconButton &&
                          widget.tooltip == 'Desteyi incele',
                    ),
                  )
                  .onPressed!;
        }
        action();
        action();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final target = find.byType(
          arena ? ArenasScreen : BattleDeckScreen,
          skipOffstage: false,
        );
        expect(target, findsOneWidget);
        action();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(target, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        action();
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('level rewards belong to the current account route', () {
    expect(const LevelRewardsScreen(), isA<LunoAccountScopedPage>());
  });

  testWidgets('level close never dismisses a covering route', (tester) async {
    await tester.pumpWidget(shell(const LevelRewardsScreen()));
    await tester.scrollUntilVisible(find.text('ANLADIM'), 300);
    final action =
        tester.widget<LunoButton>(find.byType(LunoButton)).onPressed!;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covering-level')),
      ),
    );
    await tester.pumpAndSettle();
    action();
    await tester.pumpAndSettle();
    expect(find.text('covering-level'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    action();
    expect(tester.takeException(), isNull);
  });

  testWidgets('time selection owns its sheet and cannot dismiss a cover', (
    tester,
  ) async {
    late BuildContext owner;
    await tester.pumpWidget(
      shell(
        Builder(
          builder: (context) {
            owner = context;
            return const Scaffold(body: Text('time-owner'));
          },
        ),
      ),
    );
    final result = showGameTimeControlPicker(owner);
    await tester.pumpAndSettle();
    final action = tester.widget<ListTile>(find.byType(ListTile).first).onTap!;
    final navigator = Navigator.of(owner);
    final cover = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('covering-time')),
    );
    navigator.push(cover);
    await tester.pumpAndSettle();
    action();
    await tester.pumpAndSettle();
    expect(find.text('covering-time'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    action();
    await tester.pumpAndSettle();
    expect(await result, 1);
    expect(find.text('time-owner'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    action();
    expect(tester.takeException(), isNull);
  });
}
