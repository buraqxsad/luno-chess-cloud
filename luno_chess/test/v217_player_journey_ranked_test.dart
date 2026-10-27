import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'helpers/battle_v1_response.dart';
import 'v217_player_journey_support.dart';

Map<String, dynamic> journeyRank(String uid, int trophies) => {
  'protocolVersion': battleV1Protocol,
  'uid': uid,
  'trophies': trophies,
  'arenaIdx': arenaIndexForTrophies(trophies),
};

void main() {
  setupPracticeTestAssets();
  setUp(() async {
    await SharedPreferences.getInstance();
  });
  final store = GameStore.instance;
  setUpAll(store.load);

  for (final (outcome, side, fen, move, delta) in [
    ('win', PieceColor.white, '7k/8/5KQ1/8/8/8/8/8 w - - 0 1', 'g6g7', 32),
    ('loss', PieceColor.black, '7k/8/5KQ1/8/8/8/8/8 w - - 0 1', 'g6g7', -8),
    ('draw', PieceColor.white, '7k/5K2/8/6Q1/8/8/8/8 w - - 0 1', 'g5g6', 0),
  ]) {
    testWidgets('V217 real core $outcome -> ranked result receipt -> '
        'authoritative refresh -> arena -> account restart', (tester) async {
      journeyViewport(tester);
      final uid = side == PieceColor.white ? 'self' : 'other';
      await journeyAwait(tester, () async {
        await store.bindAccount('v217-rank-parking-$outcome');
        await store.bindAccount(uid);
      });
      final transport = JourneyTransport(store);
      transport.extraState['battleV1Rank'] = journeyRank(uid, 96);
      final online = transport.service();
      addTearDown(online.dispose);
      await journeyAwait(tester, () async {
        await online.start();
        await online.refreshState();
      });
      final gold = store.data.gold;
      var authority = DeckManager.newBattle(board: Board.fromFen(fen));
      var version = 0;
      Map<String, dynamic> projection() {
        final response = v1Response(
          state: authority,
          version: version,
          uid: uid,
          side: side,
        );
        final terminal = authority.rules.terminal;
        if (terminal != null) {
          response['status'] = 'finished';
          final view = response['view'] as Map;
          (view['public'] as Map)
            ..['result'] = terminal.toJson()
            ..['settlementStatus'] = 'complete';
          (view['private'] as Map)['settlementJson'] = jsonEncode({
            'protocolVersion': battleV1Protocol,
            'matchId': v1MatchId,
            'rated': true,
            'trophyDelta': delta,
            'newTrophies': 96 + delta,
          });
        }
        return response;
      }

      final controller = BattleV1Controller(
        uid: uid,
        matchId: v1MatchId,
        initialResponse: projection(),
        persistPending: (_) async {},
        request: (path, _) async {
          if (path != '/getBattleV1') {
            throw StateError('Unexpected ranked fixture request: $path');
          }
          return projection();
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        shell(
          BattleV1Screen(
            controllerOverride: controller,
            clockOverride: (_) => 300000,
          ),
          language: 'en',
          reduced: true,
        ),
      );
      await journeyPump(tester);
      final action = ChessMoveAction(move);
      expect(
        BattleRulesCore.legalActions(
          authority.view(PieceColor.white),
        ).map((candidate) => candidate.key),
        contains(action.key),
      );
      authority = DeckManager.apply(authority, action);
      version++;
      expect(authority.rules.terminal, isNotNull);
      expect(
        authority.rules.terminal!.reason,
        outcome == 'draw' ? 'stalemate' : 'checkmate',
      );
      await journeyAwait(tester, controller.reconnect);
      await journeyPump(tester);
      final heading = tester.widget<BattleResultHeading>(
        find.byType(BattleResultHeading),
      );
      expect(heading.winner, outcome == 'draw' ? isNull : PieceColor.white);
      expect(heading.own, side);
      expect(controller.snapshot!.settlement!.trophyDelta, delta);
      expect(
        store.data.gold,
        gold,
        reason: 'A displayed result receipt is not a local currency grant',
      );
      expect(
        store.rankTrophies,
        96,
        reason: 'Rank must come from player-state refresh, not local addition',
      );

      // The server receipt and player state are separate public contracts.
      // Explicit refresh is necessary here because BattleV1Screen currently
      // refreshes its production singleton, not the injected request fixture.
      transport.extraState['battleV1Rank'] = journeyRank(uid, 96 + delta);
      await journeyAwait(tester, () async {
        await online.refreshState();
        await online.refreshState();
      });
      expect(store.rankTrophies, 96 + delta);
      expect(store.data.gold, gold);
      await tester.pumpWidget(
        shell(const ArenasScreen(), language: 'en', reduced: true),
      );
      await journeyPump(tester);
      expect(
        find.byKey(const ValueKey('arena-progress-value')),
        findsOneWidget,
      );
      expect(store.rankArenaIdx, arenaIndexForTrophies(96 + delta));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(arenaProgress(96 + delta, store.rankArenaIdx), .0001),
      );
      await tester.pumpWidget(const SizedBox());
      await journeyFlush(tester, store);
      final restored = GameStore.createForTesting();
      addTearDown(restored.dispose);
      await journeyAwait(tester, restored.load);
      expect(restored.rankTrophies, 96 + delta);
      expect(restored.accountUid, uid);
      expect(tester.takeException(), isNull);
    });
  }
}
