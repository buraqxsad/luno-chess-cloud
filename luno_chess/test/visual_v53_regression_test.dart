import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Restart asks first, cancel preserves board, confirm resets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
    GameStore.instance.hasCompletedTutorial = true;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: LunoTheme.dark,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.5)), child: child!),
      home: GameScreen(level: aiLevels.first, local: true),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    final dynamic state = tester.state(find.byType(GameScreen));
    state.m.moveCount = 8;
    for (final confirm in [false, true]) {
      await tester.tap(find.byTooltip('Maç menüsü'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yeniden başlat'));
      await tester.tap(find.text('Yeniden başlat'));
      await tester.pumpAndSettle();
      expect(state.m.moveCount, 8);
      await tester.tap(find.text(confirm ? 'YENİDEN BAŞLAT' : 'VAZGEÇ'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.m.moveCount, confirm ? 0 : 8);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
