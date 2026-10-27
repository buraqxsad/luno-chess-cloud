import 'piece.dart';
import 'square.dart';

/// Tek bir hamle. from/to kare indeksleri (0-63).
class Move {
  final int from;
  final int to;
  final PieceType? promotion; // piyon terfisi (null = yok)
  final bool isEnPassant;
  final bool isCastle;

  const Move(
    this.from,
    this.to, {
    this.promotion,
    this.isEnPassant = false,
    this.isCastle = false,
  });

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion &&
      other.isEnPassant == isEnPassant &&
      other.isCastle == isCastle;

  @override
  int get hashCode => Object.hash(from, to, promotion, isEnPassant, isCastle);

  /// UCI gösterimi (örn. "e2e4", "e7e8q").
  String get uci {
    const map = {
      PieceType.queen: 'q',
      PieceType.rook: 'r',
      PieceType.bishop: 'b',
      PieceType.knight: 'n',
    };
    final suffix = promotion == null ? '' : map[promotion]!;
    return '${Square.algebraic(from)}${Square.algebraic(to)}$suffix';
  }

  @override
  String toString() => uci;
}
