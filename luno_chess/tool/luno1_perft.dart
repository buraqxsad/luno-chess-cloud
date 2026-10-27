import 'dart:convert';
import 'dart:io';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/perft.dart';

void main(List<String> args) {
  final reference =
      jsonDecode(File('../battle_contract/v1/perft.json').readAsStringSync())
          as Map;
  final results = <Map<String, Object>>[];
  for (final position in reference['positions'] as List) {
    final board = Board.fromFen(position['fen'] as String);
    final fast = position['fast'] as List;
    final cases = <int, int>{
      for (var i = 0; i < fast.length; i++) i + 1: fast[i] as int,
    };
    if (args.contains('--slow')) {
      for (final entry in (position['slow'] as Map).entries) {
        cases[int.parse(entry.key as String)] = entry.value as int;
      }
    }
    for (final entry in cases.entries) {
      final actual = perft(board, entry.key);
      results.add({
        'position': position['id'] as String,
        'depth': entry.key,
        'expected': entry.value,
        'actual': actual,
        'pass': actual == entry.value,
      });
      if (actual != entry.value) {
        stderr.writeln(
          jsonEncode({
            'position': position['id'],
            'divide': perftDivide(board, entry.key),
          }),
        );
        exitCode = 1;
      }
    }
  }
  stdout.writeln(jsonEncode({'implementation': 'dart', 'results': results}));
}
