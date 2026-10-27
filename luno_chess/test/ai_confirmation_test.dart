import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final action in ['restart', 'resign']) {
    testWidgets('AI finishes beneath $action confirmation', (tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final channel in [
        'xyz.luan/audioplayers.global/events',
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers',
        for (final id in [
          'luno_music',
          'luno_sfx_0',
          'luno_sfx_1',
          'luno_sfx_2',
        ])
          'xyz.luan/audioplayers/events/$id',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (_) async => null,
        );
      }
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial();
      store.loaded = true;
      store.hasCompletedTutorial = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: GameScreen(level: aiLevels.first),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(GameScreen));
      final MatchState match = state.m;
      // Isolate the chess decision from random card use in this lifecycle test.
      match.blackHand.clear();
      final tap =
          tester.widget<MatchBoardView>(find.byType(MatchBoardView)).onTap;
      tap(Square.of(4, 1));
      tap(Square.of(4, 3));
      await tester.pump();
      expect(match.moveCount, 1);
      if (action == 'restart') {
        await tester.tap(find.byTooltip('Yeniden başlat'));
      } else {
        await tester.tap(find.byTooltip('Maç menüsü'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Teslim ol'));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      for (var i = 0; i < 40 && match.turn != PieceColor.white; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pump();
      expect(match.turn, PieceColor.white);
      expect(match.moveCount, 2);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.text(action == 'restart' ? 'YENİDEN BAŞLAT' : 'ONAYLA'),
      );
      await tester.pumpAndSettle();
      if (action == 'restart') {
        final MatchState fresh = state.m;
        expect(identical(fresh, match), isFalse);
        expect(fresh.moveCount, 0);
        expect(fresh.turn, PieceColor.white);
        await tester.pump(const Duration(seconds: 2));
        expect(fresh.moveCount, 0);
      } else {
        expect(match.result, MatchResult.blackWins);
        expect(find.byType(ResultScreen), findsOneWidget);
        expect(find.byType(GameScreen, skipOffstage: false), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
