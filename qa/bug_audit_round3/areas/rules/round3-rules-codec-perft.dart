import 'dart:convert';
import 'dart:io';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';

const output = '/workspace/luno-review/bug-audit-round3/rules';
Object? sorted(Object? value) {
  if (value is List) return value.map(sorted).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: sorted(value[k])};
  }
  return value;
}
void equal(Object? actual, Object? expected, String message) {
  if (jsonEncode(sorted(actual)) != jsonEncode(sorted(expected))) {
    throw StateError(message);
  }
}
var transitions = 0, perftNodes = 0, terminalBeforeLeaf = 0;
int battlePerft(AuthoritativeBattleState state, int depth) {
  perftNodes++;
  if (depth == 0) return 1;
  if (state.rules.phase == BattlePhase.terminal) {
    terminalBeforeLeaf++;
    return 0;
  }
  if (state.rules.phase == BattlePhase.card) {
    state = DeckManager.apply(state, const PassAction());
    transitions++;
  }
  final actions = BattleRulesCore.legalActions(state.view(state.rules.board.turn));
  if (actions.any((a) => a is! ChessMoveAction)) throw StateError('nonmove perft');
  if (depth == 1) return actions.length;
  var count = 0;
  for (final a in actions) {
    count += battlePerft(DeckManager.apply(state, a), depth - 1);
    transitions++;
  }
  return count;
}
void main() {
  final entries = jsonDecode(File('$output/round3-rules-wire-states.json').readAsStringSync()) as List;
  var states = 0, actionCodecs = 0, transitionsCompared = 0;
  final cards = <String>{};
  for (final raw in entries.cast<Map>()) {
    final original = raw['state'] as Map;
    final state = AuthoritativeBattleState.fromJson(original);
    equal(state.toJson(), original, '${raw['label']}: state codec');
    final encoded = jsonEncode(state.toJson());
    final restored = AuthoritativeBattleState.fromJson(jsonDecode(encoded) as Map);
    final actions = BattleRulesCore.legalActions(state.view(state.rules.board.turn));
    equal(BattleRulesCore.legalActions(restored.view(restored.rules.board.turn)).map((a)=>a.toJson()).toList(), actions.map((a)=>a.toJson()).toList(), '${raw['label']}: restored complete legal set');
    for (final action in (raw['actions'] as List).cast<Map>()) {
      final parsed = BattleAction.fromJson(action);
      final reparsed = BattleAction.fromJson(jsonDecode(jsonEncode(parsed.toJson())) as Map);
      equal(reparsed.toJson(), parsed.toJson(), '${raw['label']}: action codec');
      actionCodecs++;
      final next = DeckManager.apply(state, parsed);
      final restoredNext = DeckManager.apply(restored, reparsed);
      equal(restoredNext.toJson(), next.toJson(), '${raw['label']}: restored transition');
      equal(state.toJson(), original, '${raw['label']}: retained input');
      equal(AuthoritativeBattleState.fromJson(jsonDecode(jsonEncode(next.toJson())) as Map).toJson(), next.toJson(), '${raw['label']}: resulting state codec');
      transitionsCompared++;
      if (parsed is PlayCardAction) cards.add(parsed.card.wire);
    }
    states++;
  }
  if (cards.length != 24) throw StateError('not all cards covered');
  final reference = jsonDecode(File('/workspace/luno-chess/battle_contract/v1/perft.json').readAsStringSync()) as Map;
  final perfts = <Object>[];
  for (final p in (reference['positions'] as List).cast<Map>()) {
    final fast = p['fast'] as List;
    final depths = [1, 2, if (['initial', 'position3', 'position4'].contains(p['id'])) 3];
    for (final depth in depths) {
      final actual = battlePerft(DeckManager.newBattle(board: Board.fromFen(p['fen'] as String)), depth);
      equal(actual, fast[depth-1], '${p['id']} depth $depth published perft');
      perfts.add({'position':p['id'], 'depth':depth, 'expected':fast[depth-1], 'actual':actual});
    }
  }
  final result = {'status':'PASS','codecStates':states,'actionCodecs':actionCodecs,'restoredTransitionsCompared':transitionsCompared,'cards':cards.toList()..sort(),'battlePerftCases':perfts,'battlePerftNodes':perftNodes,'battlePerftTransitions':transitions,'terminalBeforeLeaf':terminalBeforeLeaf,'oracle':'Existing tracked battle_contract/v1/perft.json, source https://chessprogramming.org/Perft_Results. Traverses actual Battle authority moves and passes card windows; no card played. Codec assertions are self-consistency invariants, not independent rules oracle.'};
  File('$output/codec-perft-result.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  stdout.writeln(jsonEncode(result));
}
