import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_break_seal_cases.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor viewer,
  int version,
) {
  final response = v1Response(state: state, side: viewer, version: version);
  final public = response['view']['public'] as Map;
  // The shared helper assigns self to White even for a Black private view.
  public['players'] = {
    sideWire(viewer): {'uid': 'self', 'name': 'Self', 'bot': false},
    sideWire(viewer.opposite): {'uid': 'other', 'name': 'Other', 'bot': false},
  };
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  if (state.rules.terminal case final terminal?) {
    response['status'] = 'finished';
    public['result'] = {
      'reason': terminal.reason,
      'winner': terminal.winner == null ? null : sideWire(terminal.winner!),
      'finishedAt': 1000,
    };
    public['settlementStatus'] = 'pending';
  }
  return response;
}

void main() {
  for (final auditCase in breakSealAuditCases()) {
    test('BREAK_SEAL mechanic: ${auditCase.name}', auditCase.run);
  }

  for (final side in PieceColor.values) {
    for (final recreate in [false, true]) {
      test(
        '${side.name}/Break Seal lost acknowledgement/recreate=$recreate',
        () async {
          var state = breakSealStack(side), version = 0, loseReply = true;
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
                reason: 'retry keeps exact target, ID and version',
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
            if (loseReply) {
              loseReply = false;
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
              const PlayCardAction(CardId.breakSeal, target: 'e1'),
            ),
            isFalse,
          );
          expect(controller.busy, isFalse);
          expect(controller.hasPendingIntent, isTrue);
          expect(
            controller.view!.rules.boardEffects.map((e) => e.id),
            ['e1', 'e10', 'e100', 'e101', 'own-mine'],
            reason:
                'lost reply does not optimistically remove the selected effect',
          );
          expect(state.rules.boardEffects.map((e) => e.id), [
            'e10',
            'e100',
            'own-mine',
          ]);
          expect(state.rules.mana[side], 5);
          expect(version, 1);
          expect(
            await controller.submit(
              const PlayCardAction(CardId.breakSeal, target: 'e10'),
            ),
            isFalse,
          );
          expect(await controller.submit(const PassAction()), isFalse);
          expect(
            calls,
            hasLength(1),
            reason: 'unresolved acknowledgement blocks a new intent',
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
          expect(calls, hasLength(2));
          expect(calls[1], calls[0]);
          expect(calls[0]['intent'], {
            'type': 'play',
            'card': 'break_seal',
            'target': 'e1',
          });
          expect(controller.hasPendingIntent, isFalse);
          expect(controller.busy, isFalse);
          expect(controller.error, isNull);
          expect(saved, isNull);
          expect(writes.whereType<String>(), [originalSaved!]);
          expect(
            version,
            1,
            reason: 'receipt replay does not remove a second board effect',
          );
          expect(controller.view!.rules.boardEffects.map((e) => e.id), [
            'e10',
            'e100',
            'own-mine',
          ]);
          expect(controller.view!.rules.mana[side], 5);
          expect(controller.view!.rules.used[side], [CardId.breakSeal]);
          expect(controller.view!.rules.handCounts[side], 2);
          expect(controller.view!.rules.drawCounts[side], 3);
          expect(controller.view!.rules.phase, BattlePhase.chess);
          expect(controller.view!.rules.pending, isNull);
          expect(
            await controller.submit(
              ChessMoveAction(breakSealChoose(side, 'b2a2', 'b7a7')),
            ),
            isTrue,
          );
          expect(version, 2);
          expect(state.rules.ply, 1);
          expect(state.rules.board.turn, side.opposite);
          expect(state.rules.boardEffects.map((e) => e.id), ['own-mine']);
          expect(state.rules.drawCounts[side], 4);
          expect(state.rules.mana[side], 5);
          breakSealInventory(state);
        },
      );
    }

    test(
      '${side.name}/Break Seal accepted cast retries pending-clear only',
      () async {
        var state = breakSealStack(side), sends = 0, clears = 0;
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
            const PlayCardAction(CardId.breakSeal, target: 'e10'),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.view!.rules.boardEffects.map((e) => e.id), [
          'e1',
          'e100',
          'own-mine',
        ]);
        await controller.retryPending();
        expect(
          sends,
          1,
          reason: 'accepted removal is not resubmitted after storage failure',
        );
        expect(clears, 2);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.busy, isFalse);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
        expect(state.rules.mana[side], 5);
        expect(state.rules.used[side], [CardId.breakSeal]);
      },
    );

    test(
      '${side.name}/Break Seal persistence failure sends nothing, exact retry recovers',
      () async {
        var state = breakSealStack(side), sends = 0, attempts = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, 0),
          persistPending: (value) async {
            if (value != null && ++attempts == 1) {
              throw StateError('storage-write-failed');
            }
          },
          request: (path, body) async {
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
            const PlayCardAction(CardId.breakSeal, target: 'e100'),
          ),
          isFalse,
        );
        expect(sends, 0);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isTrue);
        expect(state.rules.mana[side], 6);
        expect(state.rules.boardEffects, hasLength(5));
        await controller.retryPending();
        expect(sends, 1);
        expect(attempts, 2);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.busy, isFalse);
        expect(state.rules.boardEffects.map((e) => e.id), [
          'e1',
          'e10',
          'own-mine',
        ]);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
      },
    );

    test(
      '${side.name}/Break Seal duplicate submit while in flight cannot double-remove',
      () async {
        var state = breakSealStack(side), sends = 0;
        final entered = Completer<void>();
        final release = Completer<Map<String, dynamic>>();
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, 0),
          persistPending: (_) async {},
          request: (path, body) async {
            sends++;
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(body['intent'] as Map),
            );
            entered.complete();
            return release.future;
          },
        );
        addTearDown(controller.dispose);
        addTearDown(() {
          if (!release.isCompleted) release.complete(_response(state, side, 1));
        });
        final first = controller.submit(
          const PlayCardAction(CardId.breakSeal, target: 'e1'),
        );
        await entered.future;
        expect(controller.busy, isTrue);
        expect(
          await controller.submit(
            const PlayCardAction(CardId.breakSeal, target: 'e100'),
          ),
          isFalse,
        );
        expect(sends, 1);
        release.complete(_response(state, side, 1));
        expect(await first, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(state.rules.mana[side], 5);
        expect(state.rules.boardEffects.map((e) => e.id), [
          'e10',
          'e100',
          'own-mine',
        ]);
      },
    );

    for (final rejection in [
      'STALE_STATE',
      'INVALID_ACTION',
      'MATCH_TERMINAL',
    ]) {
      test(
        '${side.name}/Break Seal $rejection clears retry and reconnects',
        () async {
          var state = breakSealStack(side), sends = 0;
          final before = state;
          final controller = BattleV1Controller(
            uid: 'self',
            matchId: v1MatchId,
            initialResponse: _response(state, side, 0),
            persistPending: (_) async {},
            request: (path, body) async {
              if (path == '/getBattleV1') return _response(state, side, 1);
              sends++;
              if (sends > 1) {
                state = DeckManager.apply(
                  state,
                  BattleAction.fromJson(body['intent'] as Map),
                );
                return _response(state, side, 2);
              }
              if (rejection == 'STALE_STATE') {
                state = breakSealEdit(
                  state,
                  (draft) => draft.boardEffects.removeWhere(
                    (effect) => effect.id == 'e1',
                  ),
                );
              } else if (rejection == 'MATCH_TERMINAL') {
                state = breakSealEdit(state, (draft) {
                  draft.phase = BattlePhase.terminal;
                  draft.terminal = TerminalState(
                    'timeout',
                    winner: side.opposite,
                  );
                });
              }
              throw BattleV1Rejection(rejection);
            },
          );
          addTearDown(controller.dispose);
          expect(
            await controller.submit(
              const PlayCardAction(CardId.breakSeal, target: 'e1'),
            ),
            isFalse,
          );
          expect(controller.hasPendingIntent, isFalse);
          expect(controller.busy, isFalse);
          expect(
            state.rules.mana[side],
            6,
            reason: 'rejected action pays nothing',
          );
          expect(state.rules.used[side], isEmpty);
          expect(state.rules.handCounts[side], 3);
          expect(state.hidden.hands[side], before.hidden.hands[side]);
          await controller.retryPending();
          expect(sends, 1, reason: 'rejection cannot strand a resend loop');
          await controller.reconnect();
          expect(controller.error, isNull);
          expect(controller.busy, isFalse);
          if (rejection == 'MATCH_TERMINAL') {
            expect(controller.legalActions, isEmpty);
            expect(controller.snapshot!.result?['reason'], 'timeout');
          } else {
            expect(
              controller.legalActions.whereType<PassAction>(),
              hasLength(1),
            );
            expect(await controller.submit(const PassAction()), isTrue);
            expect(sends, 2);
            expect(controller.error, isNull);
            expect(controller.busy, isFalse);
            expect(
              controller.legalActions.whereType<ChessMoveAction>(),
              isNotEmpty,
              reason: 'rejected cast does not strand the recovered card window',
            );
          }
        },
      );
    }

    test(
      '${side.name}/Break Seal malformed actions are rejected before network or persistence',
      () async {
        final state = breakSealStack(side);
        var sends = 0, writes = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(state, side, 0),
          persistPending: (_) async {
            writes++;
          },
          request: (_, _) async {
            sends++;
            throw StateError('unexpected-network');
          },
        );
        addTearDown(controller.dispose);
        for (final target in <Object?>[
          null,
          false,
          1,
          1.0,
          [],
          {'id': 'e1'},
          '',
          'own-mine',
          'E1',
          'e1 ',
        ]) {
          expect(
            await controller.submit(
              PlayCardAction(CardId.breakSeal, target: target),
            ),
            isFalse,
          );
        }
        expect(
          await controller.submit(
            const PlayCardAction(
              CardId.breakSeal,
              target: 'e1',
              sacrifice: CardId.chain,
            ),
          ),
          isFalse,
        );
        expect(sends, 0);
        expect(writes, 0);
        expect(controller.error, isNull);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(
          controller.legalActions.whereType<PlayCardAction>().where(
            (action) => action.card == CardId.breakSeal,
          ),
          hasLength(4),
        );
        expect(
          jsonEncode(controller.view!.rules.toJson()),
          jsonEncode(state.rules.toJson()),
        );
      },
    );

    test(
      '${side.name}/Break Seal rejects ambiguous duplicate effect identity',
      () {
        final state = breakSealEdit(breakSealPosition(side), (draft) {
          draft.boardEffects.addAll([
            breakSealEffect('duplicate', BoardEffectType.mine, side.opposite, [
              18,
            ]),
            breakSealEffect(
              'duplicate',
              BoardEffectType.lockedSquare,
              side.opposite,
              [19],
            ),
            breakSealEffect('duplicate', BoardEffectType.mine, side, [20]),
          ]);
        });
        final decoded = breakSealRoundTrip(state);
        expect(breakSealTargets(decoded, side), isEmpty);
        breakSealRejects(
          decoded,
          const PlayCardAction(CardId.breakSeal, target: 'duplicate'),
        );
        expect(decoded.rules.boardEffects, hasLength(3));
        expect(decoded.rules.mana[side], 6);
      },
    );
  }
}
