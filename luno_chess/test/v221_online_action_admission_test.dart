import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';

import 'helpers/battle_v1_response.dart';

AuthoritativeBattleState _cardWindow(CardId card) {
  final deck =
      [
        card,
        ...CardId.values.where((candidate) => candidate != card),
      ].take(10).toList();
  final battle = DeckManager.newBattle(white: deck, black: starterDeck);
  final draft =
      RuleDraft(battle.rules)
        ..phase = BattlePhase.card
        ..ownTurns = {PieceColor.white: 2, PieceColor.black: 2}
        ..mana = {PieceColor.white: 6, PieceColor.black: 6};
  return AuthoritativeBattleState(draft.freeze(), battle.hidden);
}

void main() {
  for (final (label, card) in [
    ('numeric square versus string', CardId.freeze),
    ('absent target versus empty string', CardId.prophecy),
  ]) {
    test(
      'online admission rejects $label before persistence or dispatch',
      () async {
        final battle = _cardWindow(card);
        final requests = <Map<String, dynamic>>[];
        final writes = <String?>[];
        var notifications = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: v1Response(state: battle),
          persistPending: (value) async => writes.add(value),
          request: (_, body) async {
            requests.add(Map<String, dynamic>.from(body));
            throw const BattleV1Rejection('INVALID_ACTION');
          },
        );
        addTearDown(controller.dispose);
        controller.addListener(() => notifications++);
        final canonical = controller.legalActions
            .whereType<PlayCardAction>()
            .firstWhere((action) => action.card == card);
        if (card == CardId.freeze) {
          expect(canonical.target, isA<int>());
        } else {
          expect(canonical.target, isNull);
        }
        final malformed = PlayCardAction(
          card,
          target: canonical.target is int ? '${canonical.target}' : '',
          sacrifice: canonical.sacrifice,
        );
        expect(malformed.key, canonical.key);
        expect(malformed.toJson(), isNot(equals(canonical.toJson())));
        expect(
          () => BattleRulesCore.transition(controller.view!, malformed),
          throwsStateError,
        );
        final before = jsonEncode(controller.view!.toJson());
        final initialSnapshot = controller.snapshot;

        expect(await controller.submit(malformed), isFalse);

        expect(
          requests,
          isEmpty,
          reason: 'Rejected actions must not reach HTTP.',
        );
        expect(
          writes,
          isEmpty,
          reason: 'Rejected actions must not become pending.',
        );
        expect(controller.snapshot, same(initialSnapshot));
        expect(jsonEncode(controller.view!.toJson()), before);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(notifications, 0);
      },
    );

    test('online admission still sends canonical $label action', () async {
      final battle = _cardWindow(card);
      final paths = <String>[];
      final bodies = <Map<String, dynamic>>[];
      final writes = <String?>[];
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(state: battle),
        persistPending: (value) async => writes.add(value),
        request: (path, body) async {
          paths.add(path);
          bodies.add(Map<String, dynamic>.from(body));
          expect(writes, hasLength(1));
          expect(jsonDecode(writes.single!), body);
          final action = BattleAction.fromJson(body['intent'] as Map);
          return v1Response(
            state: DeckManager.apply(battle, action),
            version: 1,
          );
        },
      );
      addTearDown(controller.dispose);
      final canonical = controller.legalActions
          .whereType<PlayCardAction>()
          .firstWhere((action) => action.card == card);

      expect(await controller.submit(canonical), isTrue);

      expect(paths, ['/submitBattleV1Action']);
      expect(bodies.single['intent'], canonical.toJson());
      expect(bodies.single['expectedStateVersion'], 0);
      expect(writes, hasLength(2));
      expect(writes.last, isNull);
      expect(controller.snapshot!.stateVersion, 1);
      expect(controller.hasPendingIntent, isFalse);
      expect(controller.error, isNull);
    });
  }

  test('server terminal result blocks otherwise legal core actions', () async {
    final response = v1Response(version: 1)..['status'] = 'finished';
    ((response['view'] as Map)['public'] as Map)['result'] = {
      'reason': 'resign',
      'winner': 'b',
    };
    var requests = 0, writes = 0;
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: response,
      persistPending: (_) async => writes++,
      request: (_, _) async {
        requests++;
        return response;
      },
    );
    addTearDown(controller.dispose);
    const move = ChessMoveAction('e2e4');
    expect(
      BattleRulesCore.legalActions(
        controller.view!,
      ).any((action) => action.key == move.key),
      isTrue,
    );

    expect(await controller.submit(move), isFalse);

    expect(requests, 0);
    expect(writes, 0);
    expect(controller.hasPendingIntent, isFalse);
    expect(controller.error, isNull);
  });
}
