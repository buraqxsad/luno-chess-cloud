import 'package:flutter/material.dart' hide Text;
import '../i18n/luno_text.dart';
import '../engine/piece.dart';
import '../theme/luno_theme.dart';

/// Bir taşı Unicode satranç sembolüyle çizer.
/// (İleride özel skin görselleriyle değiştirilebilir — arayüz aynı kalır.)
class PieceGlyph extends StatelessWidget {
  final Piece piece;
  final double size;

  const PieceGlyph({super.key, required this.piece, required this.size});

  // Dolu (siyah seri) semboller; rengi biz veriyoruz.
  static const Map<PieceType, String> _glyph = {
    PieceType.king: '♚',
    PieceType.queen: '♛',
    PieceType.rook: '♜',
    PieceType.bishop: '♝',
    PieceType.knight: '♞',
    PieceType.pawn: '♟',
  };

  @override
  Widget build(BuildContext context) {
    final isWhite = piece.color == PieceColor.white;
    return Text(
      _glyph[piece.type]!,
      style: TextStyle(
        fontSize: size,
        height: 1.0,
        color: isWhite ? LunoColors.pieceWhite : LunoColors.pieceBlack,
        shadows: [
          Shadow(
            color:
                isWhite
                    ? Colors.black.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.20),
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
