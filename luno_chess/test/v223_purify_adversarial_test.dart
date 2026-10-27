import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_purify_cases.dart';

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor viewer,
  int version,
) {
  final response = v1Response(state: state, side: viewer, version: version);
  final public = response['view']['public'] as Map;
  public['players'] = {
    sideWire(viewer): {'uid': 'self', 'name': 'Self', 'bot': false},
    sideWire(viewer.opposite): {'uid': 'other', 'name': 'Other', 'bot': false},
  };
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  if (state.rules.terminal != null) {
    response['status'] = 'finished';
    public['result'] = {
      'reason': state.rules.terminal!.reason,
      'winner':
          state.rules.terminal!.winner == null
              ? null
              : sideWire(state.rules.terminal!.winner!),
      'finishedAt': 1000,
    };
    public['settlementStatus'] = 'pending';
  }
  return response;
}

Map<String, dynamic> _copy(Map<String, dynamic> body) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map);

AuthoritativeBattleState _restricted(PieceColor side) => purifyAddEffect(
  purifyPosition(
    side == purifyWhite
        ? '6k1/8/8/1p6/8/8/1R6/5K2 w - - 17 23'
        : '5k2/1r6/8/8/1P6/8/8/6K1 b - - 17 23',
  ),
  purifySquare(side == purifyWhite ? 'b2' : 'b7'),
  PieceEffectType.freeze,
);

void main() {
  for (final auditCase in purifyAuditCases()) {
    test('PURIFY mechanic: ${auditCase.name}', auditCase.run);
  }

  for (final side in PieceColor.values) {
    for (final recreate in [false, true]) {
      test(
        '${side.name}/Purify lost acknowledgement/recreate=$recreate',
        () async {
          var state = _restricted(side), version = 0;
          var loseFirstReply = true;
          String? saved;
          final calls = <Map<String, dynamic>>[];
          final receipts = <String, Map<String, dynamic>>{};
          final writes = <String?>[];

          Future<Map<String, dynamic>> request(
            String path,
            Map<String, dynamic> body,
          ) async {
            if (path == '/getBattleV1') return _response(state, side, version);
            expect(path, '/submitBattleV1Action');
            calls.add(_copy(body));
            final id = body['actionId'] as String;
            if (receipts.containsKey(id)) {
              expect(
                body,
                receipts[id],
                reason: 'retry must keep ID, version and exact effect target',
              );
            } else {
              expect(body['expectedStateVersion'], version);
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              receipts[id] = _copy(body);
              version++;
            }
            if (loseFirstReply) {
              loseFirstReply = false;
              throw StateError('reply-lost-after-commit');
            }
            return _response(state, side, version);
          }

          Future<void> persist(String? value) async {
            saved = value;
            writes.add(value);
          }

          var controller = BattleV1Controller(
            uid: 'self',
            matchId: v1MatchId,
            request: request,
            persistPending: persist,
            initialResponse: _response(state, side, version),
          );
          expect(
            await controller.submit(
              const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
            ),
            isFalse,
          );
          expect(controller.hasPendingIntent, isTrue);
          expect(controller.busy, isFalse);
          expect(
            controller.view!.rules.pieceEffects.single.type,
            PieceEffectType.freeze,
            reason: 'failed reply must not optimistically cleanse local rules',
          );
          expect(state.rules.mana[side], 5);
          expect(state.rules.pieceEffects, isEmpty);
          expect(version, 1);
          expect(await controller.submit(const PassAction()), isFalse);
          expect(
            calls.length,
            1,
            reason: 'unresolved Purify blocks a new intent',
          );
          final originalSaved = saved;
          expect(originalSaved, isNotNull);
          if (recreate) {
            controller.dispose();
            controller = BattleV1Controller(
              uid: 'self',
              matchId: v1MatchId,
              request: request,
              persistPending: persist,
              pendingJson: originalSaved,
              initialResponse: _response(state, side, version),
            );
          }
          addTearDown(controller.dispose);
          await controller.retryPending();
          expect(calls.length, 2);
          expect(calls[1], calls[0]);
          expect(controller.hasPendingIntent, isFalse);
          expect(controller.busy, isFalse);
          expect(controller.error, isNull);
          expect(saved, isNull);
          expect(writes.whereType<String>(), [originalSaved!]);
          expect(
            version,
            1,
            reason: 'receipt replay is not a second transition',
          );
          expect(controller.view!.rules.mana[side], 5);
          expect(controller.view!.rules.used[side], [CardId.purify]);
          expect(controller.view!.rules.handCounts[side], 2);
          expect(controller.view!.rules.drawCounts[side], 3);
          expect(controller.view!.rules.phase, BattlePhase.chess);
          expect(controller.view!.rules.pending, isNull);
          final move = side == purifyWhite ? 'b2b3' : 'b7b6';
          expect(await controller.submit(ChessMoveAction(move)), isTrue);
          expect(version, 2);
          expect(state.rules.ply, 1);
          expect(state.rules.board.turn, side.opposite);
          expect(state.rules.drawCounts[side], 4);
          expect(state.rules.mana[side], 5);
          expect(calls.last['intent'], {'type': 'move', 'uci': move});
        },
      );
    }

    test(
      '${side.name}/accepted Purify retries local pending removal only',
      () async {
        var state = _restricted(side), sends = 0, clears = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, 0),
          persistPending: (value) async {
            if (value == null && ++clears == 1) {
              throw StateError('storage-clear-failed');
            }
          },
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            sends++;
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(body['intent'] as Map),
            );
            return _response(state, side, 1);
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.view!.rules.mana[side], 5);
        expect(controller.view!.rules.pieceEffects, isEmpty);
        await controller.retryPending();
        expect(
          sends,
          1,
          reason: 'accepted effect removal must not be submitted again',
        );
        expect(clears, 2);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.busy, isFalse);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
        expect(state.rules.used[side], [CardId.purify]);
      },
    );

    test(
      '${side.name}/terminal rejection of queued Purify remains atomic',
      () async {
        var state = _restricted(side), sends = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, 0),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/getBattleV1') return _response(state, side, 1);
            sends++;
            state = purifyEdit(state, (draft) {
              draft.phase = BattlePhase.terminal;
              draft.terminal = TerminalState('timeout', winner: side.opposite);
            });
            throw const BattleV1Rejection('MATCH_TERMINAL');
          },
        );
        addTearDown(controller.dispose);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(state.rules.mana[side], 6, reason: 'rejected cast pays nothing');
        expect(state.rules.used[side], isEmpty);
        expect(state.rules.handCounts[side], 3);
        expect(state.rules.pieceEffects.single.type, PieceEffectType.freeze);
        await controller.reconnect();
        expect(controller.error, isNull);
        expect(controller.snapshot!.result?['reason'], 'timeout');
        expect(controller.legalActions, isEmpty);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.purify, target: 'v223-purify-target'),
          ),
          isFalse,
        );
        expect(
          sends,
          1,
          reason: 'terminal snapshot cannot strand a retry loop',
        );
      },
    );
  }
}
