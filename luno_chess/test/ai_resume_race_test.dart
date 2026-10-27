import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingAi extends MatchAi {
  final requests = <Completer<List<int>?>>[];
  final moves = <List<int>>[];

  @override
  String? maybeCard(MatchState m, AiLevel level) => null;

  @override
  Future<List<int>?> chooseMoveAsync(MatchState m, AiLevel level) {
    final request = Completer<List<int>?>();
    moves.add(List<int>.from(m.allLegal(m.turn).first));
    requests.add(request);
    return request.future;
  }

  void complete(int index) => requests[index].complete(moves[index]);
}

void main() {
  for (final scenario in ['old-first', 'new-first', 'dispose']) {
    testWidgets('pending AI decision survives lifecycle: $scenario', (
      tester,
    ) async {
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
      final ai = PendingAi();
      var now = DateTime(2026, 9, 28);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: GameScreen(
            level: aiLevels.first,
            aiOverride: ai,
            clockNow: () => now,
            timeControlMinutes: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(GameScreen));
      final MatchState match = state.m;
      final tap =
          tester.widget<MatchBoardView>(find.byType(MatchBoardView)).onTap;
      tap(Square.of(4, 1));
      tap(Square.of(4, 3));
      await tester.pump(const Duration(milliseconds: 500));
      expect(ai.requests.length, 1);
      expect(match.moveCount, 1);
      if (scenario == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
        ai.complete(0);
        await tester.pump(const Duration(seconds: 1));
        expect(match.moveCount, 1);
      } else {
        state.didChangeAppLifecycleState(AppLifecycleState.inactive);
        state.didChangeAppLifecycleState(AppLifecycleState.hidden);
        state.didChangeAppLifecycleState(AppLifecycleState.paused);
        now = now.add(const Duration(minutes: 10));
        await tester.pump(const Duration(seconds: 2));
        expect(match.moveCount, 1);
        expect(state.busy, isFalse);
        if (scenario == 'old-first') {
          ai.complete(0);
          await tester.pump();
          expect(match.moveCount, 1);
        }
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 500));
        expect(ai.requests.length, 2);
        expect(match.over, isFalse);
        ai.complete(1);
        await tester.pump();
        expect(match.moveCount, 2);
        expect(match.turn, PieceColor.white);
        expect(state.busy, isFalse);
        if (scenario == 'new-first') {
          ai.complete(0);
          await tester.pump();
        }
        expect(match.moveCount, 2);
        expect(state.busy, isFalse);
        // Human input works again; no stale decision has locked the board.
        tap(Square.of(3, 1));
        tap(Square.of(3, 3));
        await tester.pump();
        expect(match.moveCount, 3);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
