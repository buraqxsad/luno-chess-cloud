import 'dart:convert';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';

AuthoritativeBattleState fixtureInitial(Map f) {
  var s = DeckManager.newBattle(
    white: parseCards(f['whiteDeckOrder']),
    black: parseCards(f['blackDeckOrder']),
    board: f['fen'] == null ? null : Board.fromFen(f['fen'] as String),
  );
  final json = s.toJson(),
      rules = json['rules'] as Map,
      hidden = json['hidden'] as Map;
  if (f['ready'] == true) {
    rules['phase'] = 'card';
    rules['mana'] = {'w': 6, 'b': 6};
    rules['ownTurns'] = {'w': 2, 'b': 2};
    rules['repetitions'] = <String, int>{};
  }
  final setup = f['setup'] as Map?;
  for (final entry in (setup?['rules'] as Map? ?? {}).entries) {
    rules[entry.key as String] = entry.value;
  }
  for (final entry in (setup?['hidden'] as Map? ?? {}).entries) {
    hidden[entry.key as String] = entry.value;
  }
  s = AuthoritativeBattleState.fromJson(json);
  return s;
}

Object? fixtureAt(Object? value, String path) {
  for (final key in path.split('.')) {
    value =
        value is List
            ? value[int.parse(key)]
            : value is Map
            ? value[key]
            : null;
  }
  return value;
}

void fixtureEqual(Object? actual, Object? expected, String message) {
  if (jsonEncode(canonicalObject(actual)) !=
      jsonEncode(canonicalObject(expected))) {
    throw StateError('$message\nexpected=$expected\nactual=$actual');
  }
}

AuthoritativeBattleState runFixture(Map f) {
  var s = fixtureInitial(f);
  var index = 0;
  for (final value in f['steps'] as List) {
    final step = value as Map, label = '${f['fixtureId']}:${index++}';
    final keys =
        BattleRulesCore.legalActions(
            s.view(s.rules.board.turn),
          ).map((a) => a.key).toList()
          ..sort();
    for (final key in step['contains'] as List? ?? []) {
      if (!keys.contains(key)) {
        throw StateError('$label missing $key');
      }
    }
    for (final key in step['excludes'] as List? ?? []) {
      if (keys.contains(key)) {
        throw StateError('$label extra $key');
      }
    }
    if (step['exact'] != null) {
      fixtureEqual(
        keys,
        (step['exact'] as List).cast<String>()..sort(),
        '$label complete legal set',
      );
    }
    if (step['action'] != null) {
      final action = BattleAction.fromJson(step['action'] as Map),
          before = s.toJson();
      if (step['legal'] == false) {
        var rejected = false;
        try {
          DeckManager.apply(s, action);
        } on StateError {
          rejected = true;
        }
        if (!rejected) {
          throw StateError('$label accepted illegal action');
        }
        fixtureEqual(s.toJson(), before, '$label atomic');
      } else {
        s = DeckManager.apply(s, action);
      }
    }
    for (final entry in (step['expect'] as Map? ?? {}).entries) {
      fixtureEqual(
        fixtureAt(s.toJson(), entry.key as String),
        entry.value,
        '$label ${entry.key}',
      );
    }
  }
  return s;
}
