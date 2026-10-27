import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';

Future<BattleV1LocalSession> cardTurn() async {
  final session = BattleV1LocalSession(
    hotseat: true,
    practiceDeck: starterDeck,
    random: Random(221),
  );
  addTearDown(session.dispose);
  expect(await session.submit(const ChessMoveAction('e2e4')), isTrue);
  expect(await session.submit(const ChessMoveAction('e7e5')), isTrue);
  expect(session.view.rules.phase, BattlePhase.card);
  return session;
}

void main() {
  test(
    'local admission rejects string square without throwing or mutation',
    () async {
      final session = await cardTurn();
      final valid = session.legalActions.whereType<PlayCardAction>().firstWhere(
        (action) => action.card == CardId.shelter && action.target is int,
      );
      final malformed = PlayCardAction(
        valid.card,
        target: valid.target.toString(),
      );
      expect(malformed.key, valid.key);
      final before = jsonEncode(session.view.toJson());
      final version = session.version;

      expect(await session.submit(malformed), isFalse);
      expect(jsonEncode(session.view.toJson()), before);
      expect(session.version, version);
      expect(await session.submit(valid), isTrue);
      expect(session.view.rules.phase, BattlePhase.chess);
    },
  );

  test(
    'local admission rejects empty target instead of aliasing null',
    () async {
      final session = await cardTurn();
      final valid = session.legalActions.whereType<PlayCardAction>().firstWhere(
        (action) => action.card == CardId.prophecy,
      );
      const malformed = PlayCardAction(CardId.prophecy, target: '');
      expect(malformed.key, valid.key);
      final before = jsonEncode(session.view.toJson());
      final version = session.version;

      expect(await session.submit(malformed), isFalse);
      expect(jsonEncode(session.view.toJson()), before);
      expect(session.version, version);
      expect(await session.submit(valid), isTrue);
      expect(session.view.rules.phase, BattlePhase.pending);
    },
  );
}
