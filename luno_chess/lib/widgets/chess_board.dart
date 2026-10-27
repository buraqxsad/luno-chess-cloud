import 'package:flutter/material.dart';
import '../engine/board.dart';
import '../engine/square.dart';
import '../theme/luno_theme.dart';
import 'piece_glyph.dart';

/// 8x8 satranç tahtasını çizer; kareye dokunmayı yukarı bildirir.
/// Seçili kareyi ve yasal hedefleri vurgular.
class ChessBoardView extends StatelessWidget {
  final Board board;
  final int? selected;
  final Set<int> targets;
  final bool flipped; // siyah altta
  final void Function(int idx) onTap;

  const ChessBoardView({
    super.key,
    required this.board,
    required this.onTap,
    this.selected,
    this.targets = const {},
    this.flipped = false,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, c) {
            final cell = c.maxWidth / 8;
            return Stack(
              children: [
                for (int rank = 0; rank < 8; rank++)
                  for (int file = 0; file < 8; file++) _cell(file, rank, cell),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cell(int file, int rank, double cell) {
    final idx = Square.of(file, rank);
    // Görüntü konumu: beyaz altta → rank 7 en üst satır.
    final displayRow = flipped ? rank : 7 - rank;
    final displayCol = flipped ? 7 - file : file;
    final isLight = (file + rank) % 2 == 1;
    final piece = board.pieceAt(idx);
    final isSelected = selected == idx;
    final isTarget = targets.contains(idx);

    return Positioned(
      left: displayCol * cell,
      top: displayRow * cell,
      width: cell,
      height: cell,
      child: GestureDetector(
        onTap: () => onTap(idx),
        child: Container(
          color:
              isSelected
                  ? LunoColors.gold.withValues(alpha: 0.55)
                  : (isLight ? LunoColors.boardLight : LunoColors.boardDark),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isTarget)
                Center(
                  child: Container(
                    width: piece == null ? cell * 0.30 : cell * 0.94,
                    height: piece == null ? cell * 0.30 : cell * 0.94,
                    decoration: BoxDecoration(
                      shape:
                          piece == null ? BoxShape.circle : BoxShape.rectangle,
                      color:
                          piece == null
                              ? Colors.black.withValues(alpha: 0.22)
                              : null,
                      border:
                          piece == null
                              ? null
                              : Border.all(color: LunoColors.danger, width: 3),
                      borderRadius:
                          piece == null ? null : BorderRadius.circular(4),
                    ),
                  ),
                ),
              if (piece != null) PieceGlyph(piece: piece, size: cell * 0.78),
            ],
          ),
        ),
      ),
    );
  }
}
