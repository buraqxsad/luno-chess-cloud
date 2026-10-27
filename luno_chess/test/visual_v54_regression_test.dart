import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
  ]) {
    testWidgets('Mana HUD clamps display and fits large text at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      GameStore.instance.data = PlayerData.initial();
      GameStore.instance.loaded = true;
      GameStore.instance.hasCompletedTutorial = true;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  disableAnimations: true,
                ),
                child: child!,
              ),
          home: GameScreen(level: aiLevels.first, local: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final dynamic state = tester.state(find.byType(GameScreen));
      for (final value in [-3, 0, 5, 10, 30]) {
        state.setState(() {
          state.m.mana[PieceColor.white] = value;
          state.m.mana[PieceColor.black] = value;
        });
        await tester.pump();
        expect(find.text('${value.clamp(0, 10)}/10'), findsWidgets);
        expect(
          state.m.mana[PieceColor.white],
          value,
          reason: 'HUD display must not mutate engine mana',
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
