import 'dart:convert';
import 'dart:io';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'battle_fixture_support.dart';

Future<void> main() async {
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    try {
      final request = jsonDecode(line) as Map;
      var s =
          request['state'] == null
              ? fixtureInitial(request['initial'] as Map)
              : AuthoritativeBattleState.fromJson(request['state'] as Map);
      String? error;
      if (request['action'] != null) {
        try {
          s = DeckManager.apply(
            s,
            BattleAction.fromJson(request['action'] as Map),
          );
        } on StateError {
          error = 'illegal-action';
        }
      }
      final view = s.view(s.rules.board.turn),
          legal =
              BattleRulesCore.legalActions(view).map((a) => a.key).toList()
                ..sort();
      stdout.writeln(
        jsonEncode({
          'id': request['id'],
          'state': s.toJson(),
          'legal': legal,
          'bot': BattleRulesCore.chooseBotAction(view)?.key,
          'check': {
            for (final c in PieceColor.values)
              sideWire(c): MoveGen.inCheck(s.rules.board, c),
          },
          'error': error,
        }),
      );
    } catch (e, stack) {
      stderr.writeln(stack);
      stdout.writeln(
        jsonEncode({'error': 'runner-error', 'message': e.toString()}),
      );
    }
  }
}
