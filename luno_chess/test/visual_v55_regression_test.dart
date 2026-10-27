import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> openGame(WidgetTester tester, AiLevel level) async {
  SharedPreferences.setMockInitialValues({});
  GameStore.instance.data = PlayerData.initial()..avatarEmoji = 'av_knight';
  GameStore.instance.loaded = true;
  GameStore.instance.hasCompletedTutorial = true;
  tester.view.physicalSize = const Size(320, 568);
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
      home: GameScreen(level: level),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final portraits = [
    LunoAssets.aiBebek,
    LunoAssets.aiComez,
    LunoAssets.aiSovalye,
    LunoAssets.aiBilge,
    LunoAssets.aiUsta,
    LunoAssets.aiEfsane,
  ];
  for (var i = 0; i < aiLevels.length; i++) {
    testWidgets('Match shows correct identity for ${aiLevels[i].id}', (
      tester,
    ) async {
      await openGame(tester, aiLevels[i]);
      expect(find.text(aiLevels[i].name), findsOneWidget);
      expect(find.text(aiLevels[i].persona), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is LunoArt && w.path == portraits[i]),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is LunoArt && w.path == LunoAssets.avatar('av_knight'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets(
    'Restart shortcut confirms once and cancellation preserves match',
    (tester) async {
      await openGame(tester, aiLevels.first);
      final dynamic state = tester.state(find.byType(GameScreen));
      state.m.moveCount = 8;
      for (final confirm in [false, true]) {
        final action =
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Yeniden başlat',
                  ),
                )
                .onPressed!;
        action();
        action();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(state.m.moveCount, 8);
        await tester.tap(find.text(confirm ? 'YENİDEN BAŞLAT' : 'VAZGEÇ'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.m.moveCount, confirm ? 0 : 8);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
