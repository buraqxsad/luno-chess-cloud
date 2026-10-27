import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_pawn_advance_cases.dart';

// This is a controller transport double, not an execution of the TS authority.
class _AdvanceAuthority {
  AuthoritativeBattleState state;
  final PieceColor side;
  final requests = <Map<String, dynamic>>[];
  final accepted = <BattleAction>[];
  final persisted = <String?>[];
  final receipts = <String, String>{};
  int version = 0;
  bool loseCardResponse = false,
      loseMoveResponse = false,
      failClearOnce = false;
  Completer<void>? hold;
  final entered = Completer<void>();
  late BattleV1Controller controller;

  _AdvanceAuthority(this.side, {AuthoritativeBattleState? initial})
    : state = initial ?? advanceFixture(side: side) {
    controller = makeController();
  }

  BattleV1Controller makeController({String? pendingJson}) =>
      BattleV1Controller(
        uid: side.isWhite ? 'self' : 'other',
        matchId: v1MatchId,
        initialResponse: response(),
        pendingJson: pendingJson,
        persistPending: (json) async {
          persisted.add(json);
          if (json == null && failClearOnce) {
            failClearOnce = false;
            throw StateError('simulated-pending-clear-failure');
          }
        },
        request: request,
      );

  Map<String, dynamic> response() {
    final result = v1Response(state: state, side: side, version: version);
    final public = (result['view'] as Map)['public'] as Map;
    (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
    if (state.rules.terminal case final terminal?) {
      result['status'] = 'finished';
      public['result'] = {
        'reason': terminal.reason,
        'winner': terminal.winner == null ? null : sideWire(terminal.winner!),
      };
      public['settlementStatus'] = 'pending';
    }
    return result;
  }

  Future<Map<String, dynamic>> request(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (path != '/submitBattleV1Action') return response();
    requests.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    if (!entered.isCompleted) entered.complete();
    if (hold case final gate?) await gate.future;
    final id = body['actionId'] as String;
    final intent = jsonEncode(body['intent']);
    final previous = receipts[id];
    if (previous != null) {
      if (previous != intent) {
        throw const BattleV1Rejection('ACTION_ID_CONFLICT');
      }
      return response();
    }
    if (state.rules.terminal != null) {
      throw const BattleV1Rejection('MATCH_TERMINAL');
    }
    if (body['expectedStateVersion'] != version) {
      throw const BattleV1Rejection('STALE_STATE');
    }
    final action = BattleAction.fromJson(body['intent'] as Map);
    state = DeckManager.apply(state, action);
    accepted.add(action);
    version++;
    receipts[id] = intent;
    if (action is PlayCardAction && loseCardResponse) {
      loseCardResponse = false;
      throw StateError('simulated-lost-card-response');
    }
    if (action is ChessMoveAction && loseMoveResponse) {
      loseMoveResponse = false;
      throw StateError('simulated-lost-move-response');
    }
    return response();
  }
}

void main() {
  group('V223 pawn_advance independent mechanics', () {
    for (final scenario in pawnAdvanceCases()) {
      test(scenario.name, scenario.run);
    }
  });

  for (final side in PieceColor.values) {
    final from = advanceSquare(advanceFrom(side));
    final to = advanceSquare(side.isWhite ? 'c6' : 'c3');
    final card = PlayCardAction(CardId.pawnAdvance, target: from);
    final move = ChessMoveAction(advanceUci(side));

    test(
      '${side.name}: selection, accepted authorization and manual continuation never strand',
      () {
        final state = advanceFixture(side: side);
        final interaction = BattleInteraction();
        var view = state.view(side);
        var actions = BattleRulesCore.legalActions(view);
        interaction.synchronize(view, 0);
        interaction.select(CardId.pawnAdvance, actions);
        interaction.tap(from, view, actions);
        expect(interaction.play?.key, card.key);
        expect(interaction.moves(view, actions).map((a) => a.uci), [
          advanceUci(side),
        ]);
        interaction.tap(to, view, actions);
        expect(interaction.specialDestination?.uci, advanceUci(side));
        final cast = DeckManager.apply(state, interaction.play!);
        view = cast.view(side);
        actions = BattleRulesCore.legalActions(view);
        interaction.synchronize(view, 1);
        expect(interaction.card, isNull);
        expect(interaction.piece, from);
        // Reselecting another own piece cannot escape or erase the bound pawn.
        interaction.tap(
          advanceSquare(side.isWhite ? 'e1' : 'e8'),
          view,
          actions,
        );
        expect(interaction.piece, from);
        final continuation = interaction.tap(to, view, actions);
        expect(continuation.map((a) => a.key), [move.key]);
        final after = DeckManager.apply(cast, continuation.single);
        expect(after.rules.special, isNull);
        expect(after.rules.board.turn, side.opposite);
      },
    );

    test(
      '${side.name}: lost cast reply retries same request and pays only once',
      () async {
        final h = _AdvanceAuthority(side)..loseCardResponse = true;
        addTearDown(() => h.controller.dispose());
        expect(await h.controller.submit(card), isFalse);
        expect(h.controller.hasPendingIntent, isTrue);
        expect(h.controller.busy, isFalse);
        expect(h.controller.snapshot!.stateVersion, 0);
        expect(h.version, 1);
        expect(h.state.rules.mana[side], 4);
        expect(h.state.rules.handCounts[side], 2);
        expect(h.accepted.length, 1);
        expect(await h.controller.submit(move), isFalse);
        await h.controller.retryPending();
        expect(h.requests.length, 2);
        expect(h.requests[1], h.requests[0]);
        expect(h.accepted.length, 1);
        expect(h.controller.snapshot!.stateVersion, 1);
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.error, isNull);
        expect(h.controller.legalActions.map((a) => a.key), [move.key]);
        expect(await h.controller.submit(move), isTrue);
        expect(h.version, 2);
        expect(h.state.rules.mana[side], 4);
        expect(h.state.rules.drawCounts[side], 4);
        expect(h.accepted.map((a) => a.key), [card.key, move.key]);
        advanceInventory(h.state);
      },
    );

    test(
      '${side.name}: lost chess reply cannot duplicate pawn move, draw or turn',
      () async {
        final h = _AdvanceAuthority(side);
        addTearDown(() => h.controller.dispose());
        expect(await h.controller.submit(card), isTrue);
        h.loseMoveResponse = true;
        expect(await h.controller.submit(move), isFalse);
        expect(h.controller.hasPendingIntent, isTrue);
        expect(h.controller.view!.rules.special, isNotNull);
        final acceptedState = jsonEncode(canonicalObject(h.state.toJson()));
        await h.controller.retryPending();
        expect(h.requests.length, 3);
        expect(h.requests[2], h.requests[1]);
        expect(h.accepted.length, 2);
        expect(h.version, 2);
        expect(jsonEncode(canonicalObject(h.state.toJson())), acceptedState);
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.busy, isFalse);
        expect(h.controller.error, isNull);
        expect(h.controller.view!.rules.special, isNull);
        expect(h.state.rules.ply, 39);
        expect(h.state.rules.ownTurns[side.opposite], 4);
        expect(h.state.rules.drawCounts[side], 4);
        expect(await h.controller.submit(move), isFalse);
        expect(h.requests.length, 3);
      },
    );

    test(
      '${side.name}: persisted cast restart recovers original identity before chess',
      () async {
        final h = _AdvanceAuthority(side)..loseCardResponse = true;
        addTearDown(() => h.controller.dispose());
        expect(await h.controller.submit(card), isFalse);
        final saved = h.persisted.whereType<String>().single;
        final original = Map<String, dynamic>.from(h.requests.single);
        h.controller.dispose();
        h.controller = h.makeController(pendingJson: saved);
        expect(h.controller.snapshot!.stateVersion, 1);
        expect(h.controller.hasPendingIntent, isTrue);
        expect(await h.controller.submit(move), isFalse);
        await h.controller.retryPending();
        expect(h.requests.last, original);
        expect(h.accepted.length, 1);
        expect(h.state.rules.mana[side], 4);
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.legalActions.map((a) => a.key), [move.key]);
        expect(await h.controller.submit(move), isTrue);
        expect(h.accepted.length, 2);
        advanceInventory(h.state);
      },
    );

    test(
      '${side.name}: storage clear retry sends no second cast and unblocks chess',
      () async {
        final h = _AdvanceAuthority(side)..failClearOnce = true;
        addTearDown(() => h.controller.dispose());
        expect(await h.controller.submit(card), isFalse);
        expect(h.controller.hasPendingIntent, isTrue);
        expect(h.controller.snapshot!.stateVersion, 1);
        expect(h.controller.busy, isFalse);
        expect(await h.controller.submit(move), isFalse);
        await h.controller.retryPending();
        expect(h.requests.length, 1);
        expect(h.accepted.length, 1);
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.error, isNull);
        expect(await h.controller.submit(move), isTrue);
        expect(h.requests.length, 2);
        expect(h.state.rules.mana[side], 4);
        expect(h.state.rules.drawCounts[side], 4);
      },
    );

    test(
      '${side.name}: in-flight cast rejects parallel cast and chess without freezing',
      () async {
        final h = _AdvanceAuthority(side)..hold = Completer<void>();
        addTearDown(() => h.controller.dispose());
        final casting = h.controller.submit(card);
        await h.entered.future;
        expect(h.controller.busy, isTrue);
        expect(await h.controller.submit(card), isFalse);
        expect(await h.controller.submit(move), isFalse);
        h.hold!.complete();
        expect(await casting, isTrue);
        expect(h.requests.length, 1);
        expect(h.controller.busy, isFalse);
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.legalActions.map((a) => a.key), [move.key]);
        expect(await h.controller.submit(move), isTrue);
        expect(h.accepted.length, 2);
      },
    );

    test(
      '${side.name}: terminal-bound double with lost reply settles once',
      () async {
        final h = _AdvanceAuthority(
          side,
          initial: advanceFixture(side: side, fen: pawnAdvanceMateFens[side]),
        );
        addTearDown(() => h.controller.dispose());
        final mateCard = PlayCardAction(
          CardId.pawnAdvance,
          target: advanceSquare(side.isWhite ? 'c5' : 'c4'),
        );
        final mateMove = ChessMoveAction(side.isWhite ? 'c5c7' : 'c4c2');
        expect(await h.controller.submit(mateCard), isTrue);
        h.loseMoveResponse = true;
        expect(await h.controller.submit(mateMove), isFalse);
        expect(h.state.rules.terminal!.reason, 'checkmate');
        expect(h.state.rules.handCounts[side], 2);
        expect(h.state.rules.drawCounts[side], 3);
        await h.controller.retryPending();
        expect(h.requests.last, h.requests[h.requests.length - 2]);
        expect(h.accepted.length, 2);
        expect(h.controller.snapshot!.result!['reason'], 'checkmate');
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.busy, isFalse);
        expect(h.controller.legalActions, isEmpty);
        expect(await h.controller.submit(mateMove), isFalse);
        expect(h.state.rules.used[side], [CardId.pawnAdvance]);
        expect(h.state.rules.special, isNull);
        advanceInventory(h.state);
      },
    );

    test(
      '${side.name}: timeout after cast clears rejected intent and exposes terminal',
      () async {
        final h = _AdvanceAuthority(side);
        addTearDown(() => h.controller.dispose());
        expect(await h.controller.submit(card), isTrue);
        h.state = advanceEdit(h.state, (d) {
          d.phase = BattlePhase.terminal;
          d.terminal = TerminalState('timeout', winner: side.opposite);
        });
        h.version++;
        expect(await h.controller.submit(move), isFalse);
        expect(h.controller.hasPendingIntent, isFalse);
        expect(h.controller.busy, isFalse);
        expect(h.controller.error, isA<BattleV1Rejection>());
        await h.controller.reconnect();
        expect(h.controller.error, isNull);
        expect(h.controller.snapshot!.result!['reason'], 'timeout');
        expect(h.controller.legalActions, isEmpty);
        expect(h.accepted.length, 1);
        expect(h.state.rules.mana[side], 4);
        expect(h.state.rules.pieceIds[from], isNotNull);
        expect(h.state.rules.pieceIds[to], isNull);
        expect(h.state.rules.drawCounts[side], 3);
      },
    );
  }
}
