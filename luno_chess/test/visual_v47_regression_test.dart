import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Level rewards update live and fit narrow large-text layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore.instance;
    await store.load();
    final oldLevel = store.data.lvl;
    addTearDown(() => store.data.lvl = oldLevel);
    store.data.lvl = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
        home: const LevelRewardsScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Şu an Seviye 1'), findsOneWidget);
    store.applyServerState({'lvl': 51});
    await tester.pump();
    expect(find.text('Şu an Seviye 51'), findsOneWidget);
    expect(find.text('Seviye 52'), findsOneWidget);
    expect(find.text('+1140 altın'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('ANLADIM'), 200);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
