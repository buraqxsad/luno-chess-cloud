/// Taş renkleri ve türleri. Saf Dart — Flutter'a bağımlı değil (test edilebilir).
enum PieceColor { white, black }

extension PieceColorX on PieceColor {
  PieceColor get opposite =>
      this == PieceColor.white ? PieceColor.black : PieceColor.white;
  bool get isWhite => this == PieceColor.white;
}

enum PieceType { pawn, knight, bishop, rook, queen, king }

/// Tahtadaki tek bir taş. Şimdilik sadece renk + tür;
/// kart efektleri (donmuş/zehirli/kalkan vb.) ileride buraya eklenecek.
class Piece {
  final PieceColor color;
  final PieceType type;

  const Piece(this.color, this.type);

  Piece copyWith({PieceColor? color, PieceType? type}) =>
      Piece(color ?? this.color, type ?? this.type);

  @override
  bool operator ==(Object other) =>
      other is Piece && other.color == color && other.type == type;

  @override
  int get hashCode => Object.hash(color, type);
}
