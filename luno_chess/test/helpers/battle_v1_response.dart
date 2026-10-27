import 'dart:convert';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

const v1MatchId = 'bv1_0123456789abcdef0123456789abcdef';
Map<String, dynamic> v1Response({
  AuthoritativeBattleState? state,
  int version = 0,
  String uid = 'self',
  PieceColor side = PieceColor.white,
}) {
  final battle =
      state ?? DeckManager.newBattle(white: starterDeck, black: starterDeck);
  return {
    'ok': true,
    'matchId': v1MatchId,
    'status': 'active',
    'serverNow': 1000,
    'view': {
      'public': {
        'matchId': v1MatchId,
        'protocolVersion': 'LUNO_BATTLE_V1',
        'rulesetVersion': 1,
        'stateVersion': version,
        'participants': {'self': true, 'other': true},
        'players': {
          'w': {'uid': 'self', 'name': 'Self', 'bot': false},
          'b': {'uid': 'other', 'name': 'Other', 'bot': false},
        },
        'rulesJson': jsonEncode(battle.rules.toJson()),
        'clock': {
          'w': 300000,
          'b': 300000,
          'activeSide': 'w',
          'startedAt': 1000,
          'incrementMs': 2000,
        },
        'result': null,
        'settlementStatus': 'none',
        'rated': true,
        'createdAt': 1000,
        'lastEvent': null,
      },
      'private': {
        'stateVersion': version,
        'viewer': sideWire(side),
        'handJson': jsonEncode(
          battle.hidden.hands[side]!.map((c) => c.wire).toList(),
        ),
        'knowledgeJson': jsonEncode(battle.hidden.knowledge[side]!.toJson()),
      },
    },
  };
}
