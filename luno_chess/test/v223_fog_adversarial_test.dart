import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/v223_fog_cases.dart';

const _matchId = 'bv1_0123456789abcdef0123456789abcdef';

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor viewer,
  int version,
) => {
  'ok': true,
  'matchId': _matchId,
  'status': 'active',
  'serverNow': 1000,
  'view': {
    'public': {
      'matchId': _matchId,
      'protocolVersion': battleV1Protocol,
      'rulesetVersion': 1,
      'stateVersion': version,
      'participants': {'self': true, 'other': true},
      'players': {
        sideWire(viewer): {'uid': 'self', 'name': 'Self', 'bot': false},
        sideWire(viewer.opposite): {
          'uid': 'other',
          'name': 'Other',
          'bot': false,
        },
      },
      'rulesJson': jsonEncode(state.rules.toJson()),
      'clock': {
        'w': 300000,
        'b': 300000,
        'activeSide': sideWire(state.rules.board.turn),
        'startedAt': 1000,
        'incrementMs': 2000,
      },
      'result': null,
      'settlementStatus': 'none',
      'rated': false,
      'createdAt': 1000,
      'lastEvent': null,
    },
    'private': {
      'stateVersion': version,
      'viewer': sideWire(viewer),
      'handJson': jsonEncode(
        state.hidden.hands[viewer]!.map((card) => card.wire).toList(),
      ),
      'knowledgeJson': jsonEncode(state.hidden.knowledge[viewer]!.toJson()),
    },
  },
};

void main() {
  for (final audit in fogAuditCases()) {
    test('FOG ${audit.name}', audit.run);
  }

  for (final side in PieceColor.values) {
    test(
      'FOG ${side.name}/controller-rejects-malformed-cast-without-locking',
      () async {
        var state = fogScenario(side: side), version = 20;
        final requests = <Map<String, dynamic>>[];
        final persisted = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: _matchId,
          initialResponse: _response(state, side, version),
          persistPending: (value) async {
            persisted.add(value);
          },
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            requests.add(body);
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(body['intent'] as Map),
            );
            return _response(state, side, ++version);
          },
        );
        addTearDown(controller.dispose);
        for (final target in <Object?>[
          null,
          -1,
          7,
          56,
          63,
          64,
          27.0,
          'd4',
          true,
          <int>[27],
        ]) {
          expect(
            await controller.submit(PlayCardAction(CardId.fog, target: target)),
            isFalse,
          );
          expect(controller.busy, isFalse);
          expect(controller.hasPendingIntent, isFalse);
          expect(controller.error, isNull);
          expect(controller.snapshot!.stateVersion, 20);
        }
        expect(requests, isEmpty);
        expect(persisted, isEmpty);
        expect(
          await controller.submit(
            PlayCardAction(CardId.fog, target: fogAnchor('d4', side)),
          ),
          isTrue,
        );
        expect(requests, hasLength(1));
        expect(persisted.whereType<String>(), hasLength(1));
        expect(persisted.last, isNull);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.view!.rules.phase, BattlePhase.chess);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
        expect(
          controller.view!.rules.boardEffects.single.squares,
          fogExpectedZone('d4', side),
        );
      },
    );

    test(
      'FOG ${side.name}/blocked-direct-target-does-not-strand-opponent',
      () async {
        final viewer = side.opposite;
        var state = fogOpponentWindow(side), version = 30;
        var calls = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: _matchId,
          initialResponse: _response(state, viewer, version),
          persistPending: (_) async {},
          request: (path, body) async {
            calls++;
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(body['intent'] as Map),
            );
            return _response(state, viewer, ++version);
          },
        );
        addTearDown(controller.dispose);
        final before = fogCanonical(controller.view!.toJson());
        expect(
          await controller.submit(
            PlayCardAction(CardId.chain, target: fogSquare('d4', side)),
          ),
          isFalse,
        );
        expect(calls, 0);
        expect(fogCanonical(controller.view!.toJson()), before);
        expect(controller.busy, isFalse);
        expect(controller.hasPendingIntent, isFalse);
        expect(await controller.submit(const PassAction()), isTrue);
        expect(calls, 1);
        expect(controller.view!.rules.boardEffects, isEmpty);
        expect(controller.view!.rules.phase, BattlePhase.chess);
        expect(
          controller.legalActions.whereType<ChessMoveAction>(),
          isNotEmpty,
        );
      },
    );

    for (final card in [CardId.prophecy, CardId.fateExchange]) {
      test(
        'FOG ${side.name}/controller-pending-${card.wire}-reconnect-and-resolve',
        () async {
          final viewer = side.opposite;
          var state = fogOpponentWindow(side, enemyHand: [card, CardId.radar]);
          state = fogApply(
            state,
            PlayCardAction(
              card,
              sacrifice: card == CardId.fateExchange ? CardId.radar : null,
            ),
          );
          var version = 40, calls = 0;
          final inspected = [...state.hidden.knowledge[viewer]!.pendingCards];
          final selected = card == CardId.fateExchange ? inspected.last : null;
          final order =
              inspected
                  .where((value) => value != selected)
                  .toList()
                  .reversed
                  .toList();
          final controller = BattleV1Controller(
            uid: 'self',
            matchId: _matchId,
            initialResponse: _response(state, viewer, version),
            persistPending: (_) async {},
            request: (path, body) async {
              calls++;
              if (path == '/getBattleV1') {
                return _response(state, viewer, version);
              }
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              return _response(state, viewer, ++version);
            },
          );
          addTearDown(controller.dispose);
          await controller.reconnect();
          expect(controller.view!.rules.phase, BattlePhase.pending);
          expect(
            controller.view!.rules.boardEffects.single.type,
            BoardEffectType.fog,
          );
          expect(controller.view!.knowledge.pendingCards, inspected);
          expect(controller.legalActions, isNotEmpty);
          expect(
            controller.legalActions.every((action) => action is ResolveAction),
            isTrue,
          );
          expect(await controller.submit(ResolveAction([])), isFalse);
          expect(calls, 1, reason: 'invalid choice must not send or close Fog');
          expect(controller.busy, isFalse);
          expect(
            await controller.submit(ResolveAction(order, selected: selected)),
            isTrue,
          );
          expect(calls, 2);
          expect(controller.view!.rules.phase, BattlePhase.chess);
          expect(controller.view!.rules.boardEffects, isEmpty);
          expect(controller.view!.knowledge.pendingCards, isEmpty);
          expect(
            controller.legalActions.whereType<ChessMoveAction>(),
            isNotEmpty,
          );
          expect(controller.hasPendingIntent, isFalse);
          expect(controller.error, isNull);
        },
      );
    }
  }

  test('FOG live-local-opening-cast-expiry-does-not-strand-hotseat', () async {
    final order = [
      CardId.fog,
      ...CardId.values.where((card) => card != CardId.fog).take(9),
    ];
    final session = BattleV1LocalSession(
      hotseat: true,
      practice: true,
      practiceDeck: order,
    );
    addTearDown(session.dispose);
    for (final action in <BattleAction>[
      const ChessMoveAction('e2e4'),
      const ChessMoveAction('e7e5'),
      const PassAction(),
      const ChessMoveAction('g1f3'),
      const PassAction(),
      const ChessMoveAction('g8f6'),
    ]) {
      expect(await session.submit(action), isTrue, reason: action.key);
      expect(session.busy, isFalse);
      expect(session.terminal, isNull);
      expect(session.legalActions, isNotEmpty);
    }
    expect(session.view.rules.mana[PieceColor.white], 3);
    expect(
      await session.submit(PlayCardAction(CardId.fog, target: fogSquare('e4'))),
      isTrue,
    );
    expect(session.view.rules.phase, BattlePhase.chess);
    expect(session.view.rules.boardEffects.single.squares, [28, 29, 36, 37]);
    final version = session.version;
    expect(
      await session.submit(const PlayCardAction(CardId.fog, target: 28)),
      isFalse,
    );
    expect(session.version, version);
    expect(await session.submit(const ChessMoveAction('f1c4')), isTrue);
    expect(session.view.viewer, PieceColor.black);
    expect(
      BattleRulesCore.cardTargets(session.view, CardId.chain),
      isNot(contains(28)),
    );
    expect(await session.submit(const PassAction()), isTrue);
    expect(session.view.rules.boardEffects, isEmpty);
    expect(await session.submit(const ChessMoveAction('f8c5')), isTrue);
    expect(session.busy, isFalse);
    expect(session.terminal, isNull);
    expect(session.legalActions, isNotEmpty);
  });
}
