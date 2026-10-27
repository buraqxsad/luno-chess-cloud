import 'board.dart';
import 'move_gen.dart';

/// Perft: belirli derinliğe kadar yasal hamle ağacındaki yaprak sayısı.
/// Satranç motorunun doğruluğunu kanıtlamanın standart yolu —
/// başlangıç dizilimi için bilinen değerlerle karşılaştırılır.
int perft(Board b, int depth) {
  if (depth < 0) throw RangeError.value(depth, 'depth');
  if (depth == 0) return 1;
  final moves = MoveGen.legal(b);
  if (depth == 1) return moves.length;
  int nodes = 0;
  for (final m in moves) {
    nodes += perft(b.apply(m), depth - 1);
  }
  return nodes;
}

/// Debug-only root breakdown. It does not apply game-ending draw counters.
Map<String, int> perftDivide(Board board, int depth) {
  if (depth < 1) throw RangeError.value(depth, 'depth');
  final moves = MoveGen.legal(board)..sort((a, b) => a.uci.compareTo(b.uci));
  return {
    for (final move in moves) move.uci: perft(board.apply(move), depth - 1),
  };
}
