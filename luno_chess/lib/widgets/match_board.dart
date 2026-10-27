import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/piece.dart';
import '../engine/square.dart';
import '../match/match_state.dart';
import '../match/mpiece.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';

/// Tek bir canvas üzerinde çizilen savaş tahtası.
/// 64 ayrı widget yerine tek painter kullanmak, seçim ve AI hamlelerinde
/// gereksiz layout/paint maliyetini azaltır.
class MatchBoardView extends StatelessWidget {
  final MatchState match;
  final int? selected;
  final Set<int> moveTargets;
  final Set<int> cardTargets;
  final PieceColor viewer;
  final String pieceSet;
  final void Function(int idx) onTap;

  const MatchBoardView({
    super.key,
    required this.match,
    required this.onTap,
    this.selected,
    this.moveTargets = const {},
    this.cardTargets = const {},
    this.viewer = PieceColor.white,
    this.pieceSet = 'luno',
  });

  @override
  Widget build(BuildContext context) {
    const frameInset = 13.0;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth;
            final boardSize = size - frameInset * 2;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final local =
                    details.localPosition -
                    const Offset(frameInset, frameInset);
                if (local.dx < 0 ||
                    local.dy < 0 ||
                    local.dx >= boardSize ||
                    local.dy >= boardSize) {
                  return;
                }
                final cell = boardSize / 8;
                final rawFile =
                    math.min(7, math.max(0, (local.dx / cell).floor())).toInt();
                final displayRow =
                    math.min(7, math.max(0, (local.dy / cell).floor())).toInt();
                final file = viewer == PieceColor.white ? rawFile : 7 - rawFile;
                final rank =
                    viewer == PieceColor.white ? 7 - displayRow : displayRow;
                onTap(Square.of(file, rank));
              },
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Build 12'de çerçeve, tahtanın içeriğine göre 9 dilimli
                    // çizilir. Kareler ve taşlar bu açılış alanına oturur;
                    // böylece kalın görsel kenar ilk/son sırayı kapatmaz.
                    Positioned(
                      left: frameInset,
                      top: frameInset,
                      width: boardSize,
                      height: boardSize,
                      child: RepaintBoundary(
                        child: FutureBuilder<List<ui.Image>>(
                          future: _boardTextureImages,
                          builder: (context, snapshot) {
                            final textures = snapshot.data;
                            if (textures == null) {
                              // The first frame still has a visual fallback;
                              // once decoded, the 64 tile widgets are replaced
                              // by one canvas to keep board interaction light.
                              return GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 8,
                                    ),
                                itemCount: 64,
                                itemBuilder: (context, displayIndex) {
                                  final row = displayIndex ~/ 8;
                                  final column = displayIndex % 8;
                                  return LunoArt(
                                    (row + column).isEven
                                        ? LunoAssets.boardLight
                                        : LunoAssets.boardDark,
                                    fit: BoxFit.cover,
                                  );
                                },
                              );
                            }
                            return CustomPaint(
                              painter: _BoardTexturePainter(
                                light: textures[0],
                                dark: textures[1],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      left: frameInset,
                      top: frameInset,
                      width: boardSize,
                      height: boardSize,
                      child: CustomPaint(
                        painter: _MatchBoardPainter(
                          match: match,
                          visualRevision: match.visualRevision,
                          selected: selected,
                          moveTargets: moveTargets,
                          cardTargets: cardTargets,
                          viewer: viewer,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: Stack(
                          children: [
                            for (final entry in match.board.indexed)
                              if (entry.$2 != null)
                                _BoardPiece(
                                  key: ObjectKey(entry.$2),
                                  index: entry.$1,
                                  piece: entry.$2!,
                                  selected: selected == entry.$1,
                                  cell: boardSize / 8,
                                  inset: frameInset,
                                  viewer: viewer,
                                  pieceSet: pieceSet,
                                ),
                          ],
                        ),
                      ),
                    ),
                    if (match.lastCaptured != null &&
                        match.lastCaptureSquare != null)
                      _CaptureBurst(
                        key: ValueKey(
                          '${match.visualRevision}:${match.lastCaptureSquare}',
                        ),
                        index: match.lastCaptureSquare!,
                        piece: match.lastCaptured!,
                        cell: boardSize / 8,
                        inset: frameInset,
                        viewer: viewer,
                        pieceSet: pieceSet,
                        duration: LunoMotion.adaptive(
                          context,
                          LunoMotion.vfxBurst,
                        ),
                      ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: FutureBuilder<ui.Image>(
                            future: _boardFrameImage,
                            builder: (context, snapshot) {
                              final image = snapshot.data;
                              if (image == null) return const SizedBox.shrink();
                              return CustomPaint(
                                painter: _BoardFramePainter(image),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _BoardLabelsPainter()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final Future<List<ui.Image>> _boardTextureImages = _loadBoardTextureImages();
final Future<ui.Image> _boardFrameImage = _loadUiImage(LunoAssets.boardFrame);

Future<List<ui.Image>> _loadBoardTextureImages() async => [
  await _loadUiImage(LunoAssets.boardLight),
  await _loadUiImage(LunoAssets.boardDark),
];

Future<ui.Image> _loadUiImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

class _BoardTexturePainter extends CustomPainter {
  final ui.Image light;
  final ui.Image dark;

  const _BoardTexturePainter({required this.light, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final lightSource = Rect.fromLTWH(
      0,
      0,
      light.width.toDouble(),
      light.height.toDouble(),
    );
    final darkSource = Rect.fromLTWH(
      0,
      0,
      dark.width.toDouble(),
      dark.height.toDouble(),
    );
    for (var row = 0; row < 8; row++) {
      for (var column = 0; column < 8; column++) {
        final destination = Rect.fromLTWH(
          column * cell,
          row * cell,
          cell,
          cell,
        );
        canvas.drawImageRect(
          (row + column).isEven ? light : dark,
          (row + column).isEven ? lightSource : darkSource,
          destination,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardTexturePainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark;
}

class _BoardFramePainter extends CustomPainter {
  final ui.Image image;

  const _BoardFramePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final sourceEdgeX = image.width * 172 / 1250;
    final sourceEdgeY = image.height * 172 / 1250;
    final sourceWidth = image.width.toDouble();
    final sourceHeight = image.height.toDouble();
    // CSS border-image-width is 13px in Build 12. Canvas.drawImageNine
    // derives a much thicker destination edge, so place the eight slices
    // explicitly and leave the transparent center untouched.
    const destinationEdge = 13.0;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final right = size.width - destinationEdge;
    final bottom = size.height - destinationEdge;
    final sourceRight = sourceWidth - sourceEdgeX;
    final sourceBottom = sourceHeight - sourceEdgeY;

    void slice(Rect source, Rect destination) {
      canvas.drawImageRect(image, source, destination, paint);
    }

    slice(
      Rect.fromLTWH(0, 0, sourceEdgeX, sourceEdgeY),
      Rect.fromLTWH(0, 0, destinationEdge, destinationEdge),
    );
    slice(
      Rect.fromLTRB(sourceEdgeX, 0, sourceRight, sourceEdgeY),
      Rect.fromLTRB(destinationEdge, 0, right, destinationEdge),
    );
    slice(
      Rect.fromLTRB(sourceRight, 0, sourceWidth, sourceEdgeY),
      Rect.fromLTRB(right, 0, size.width, destinationEdge),
    );
    slice(
      Rect.fromLTRB(0, sourceEdgeY, sourceEdgeX, sourceBottom),
      Rect.fromLTRB(0, destinationEdge, destinationEdge, bottom),
    );
    slice(
      Rect.fromLTRB(sourceRight, sourceEdgeY, sourceWidth, sourceBottom),
      Rect.fromLTRB(right, destinationEdge, size.width, bottom),
    );
    slice(
      Rect.fromLTWH(0, sourceBottom, sourceEdgeX, sourceEdgeY),
      Rect.fromLTRB(0, bottom, destinationEdge, size.height),
    );
    slice(
      Rect.fromLTRB(sourceEdgeX, sourceBottom, sourceRight, sourceHeight),
      Rect.fromLTRB(destinationEdge, bottom, right, size.height),
    );
    slice(
      Rect.fromLTRB(sourceRight, sourceBottom, sourceWidth, sourceHeight),
      Rect.fromLTRB(right, bottom, size.width, size.height),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardFramePainter oldDelegate) =>
      oldDelegate.image != image;
}

class _MatchBoardPainter extends CustomPainter {
  final MatchState match;
  final int visualRevision;
  final int? selected;
  final Set<int> moveTargets;
  final Set<int> cardTargets;
  final PieceColor viewer;

  _MatchBoardPainter({
    required this.match,
    required this.visualRevision,
    required this.selected,
    required this.moveTargets,
    required this.cardTargets,
    required this.viewer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final fill = Paint()..style = PaintingStyle.fill;

    for (int rank = 0; rank < 8; rank++) {
      for (int file = 0; file < 8; file++) {
        final idx = Square.of(file, rank);
        final displayFile = viewer == PieceColor.white ? file : 7 - file;
        final displayRow = viewer == PieceColor.white ? 7 - rank : rank;
        final rect = Rect.fromLTWH(
          displayFile * cell,
          displayRow * cell,
          cell,
          cell,
        );
        // The final board bitmap supplies the wood and square texture. Only
        // transient state is painted here so selection never flattens the art.
        var bg = Colors.transparent;
        final mp = match.board[idx];
        final shield = match.shields[idx];
        final trap = match.traps[idx];

        if (match.lastFrom == idx || match.lastTo == idx) {
          bg = Color.alphaBlend(LunoColors.gold.withValues(alpha: 0.20), bg);
        }
        if (mp != null && (mp.frozen > 0 || mp.plagueUntil > match.moveCount)) {
          bg = Color.alphaBlend(
            const Color(0xFF6FC7FF).withValues(alpha: 0.40),
            bg,
          );
        }
        if (shield != null) {
          final tint =
              shield.by == PieceColor.white
                  ? LunoColors.gold
                  : LunoColors.danger;
          bg = Color.alphaBlend(tint.withValues(alpha: 0.28), bg);
        }
        if (selected == idx) {
          bg = Color.alphaBlend(LunoColors.gold.withValues(alpha: 0.55), bg);
        }
        if (cardTargets.contains(idx)) {
          bg = Color.alphaBlend(
            const Color(0xFF38E0D0).withValues(alpha: 0.45),
            bg,
          );
        }

        if (bg.a > 0) canvas.drawRect(rect, fill..color = bg);

        if (shield != null) {
          _drawBadge(
            canvas,
            rect.topLeft + Offset(cell * 0.12, cell * 0.12),
            'K',
            LunoColors.goldDeep,
            cell,
          );
        }
        final showTrap = trap != null && trap.isRevealedFor(viewer);
        if (showTrap) {
          _drawBadge(
            canvas,
            rect.bottomRight - Offset(cell * 0.14, cell * 0.14),
            'T',
            LunoColors.danger,
            cell,
          );
        }
        if (moveTargets.contains(idx)) {
          final occupied = mp != null;
          final marker =
              Paint()
                ..style = occupied ? PaintingStyle.stroke : PaintingStyle.fill
                ..strokeWidth = cell * 0.045
                ..color =
                    occupied
                        ? LunoColors.danger.withValues(alpha: 0.95)
                        : Colors.black.withValues(alpha: 0.24);
          final center = rect.center;
          if (occupied) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                rect.deflate(cell * 0.035),
                Radius.circular(cell * 0.08),
              ),
              marker,
            );
          } else {
            canvas.drawCircle(center, cell * 0.15, marker);
          }
        }
        // Pieces are layered as decoded Flutter images above the painter.
        // Keeping glyph text out of this canvas preserves the same art on
        // every device and avoids font fallback differences.
      }
    }

    final outline =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.055
          ..color = const Color(0xFF6F4B2B).withValues(alpha: 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.12)),
      outline,
    );
  }

  void _drawBadge(
    Canvas canvas,
    Offset anchor,
    String label,
    Color color,
    double cell,
  ) {
    final radius = cell * 0.12;
    final circle = Paint()..color = color;
    canvas.drawCircle(anchor, radius, circle);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: LunoColors.bgDeep,
          fontSize: cell * 0.12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, anchor - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MatchBoardPainter oldDelegate) {
    return oldDelegate.visualRevision != visualRevision ||
        oldDelegate.selected != selected ||
        oldDelegate.viewer != viewer ||
        !setEquals(oldDelegate.moveTargets, moveTargets) ||
        !setEquals(oldDelegate.cardTargets, cardTargets);
  }
}

class _BoardLabelsPainter extends CustomPainter {
  const _BoardLabelsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 13.0;
    final cell = (size.width - inset * 2) / 8;
    const style = TextStyle(
      fontFamily: 'Cinzel',
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: LunoColors.gold,
      shadows: [Shadow(color: Color(0xAA050812), blurRadius: 3)],
    );
    const files = <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    for (var i = 0; i < files.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: files[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          inset + i * cell + (cell - painter.width) / 2,
          size.height - painter.height - 2,
        ),
      );
    }
    for (var i = 0; i < 8; i++) {
      final painter = TextPainter(
        text: TextSpan(text: '${8 - i}', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(2, inset + i * cell + (cell - painter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoardLabelsPainter oldDelegate) => false;
}

class _BoardPiece extends StatelessWidget {
  final int index;
  final MPiece piece;
  final bool selected;
  final double cell;
  final double inset;
  final PieceColor viewer;
  final String pieceSet;

  const _BoardPiece({
    super.key,
    required this.index,
    required this.piece,
    required this.selected,
    required this.cell,
    required this.inset,
    required this.viewer,
    required this.pieceSet,
  });

  @override
  Widget build(BuildContext context) {
    final file = index % 8;
    final rank = index ~/ 8;
    final displayFile = viewer == PieceColor.white ? file : 7 - file;
    final displayRow = viewer == PieceColor.white ? 7 - rank : rank;
    return AnimatedPositioned(
      left: inset + displayFile * cell,
      top: inset + displayRow * cell,
      width: cell,
      height: cell,
      duration: LunoMotion.adaptive(context, LunoMotion.pieceMove),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: selected ? 1.035 : 1,
        duration: LunoMotion.adaptive(context, LunoMotion.pieceSelect),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          child: Padding(
            padding: EdgeInsets.all(cell * .075),
            child: LunoArt(
              LunoAssets.pieceForSet(pieceSet, piece.color, piece.type),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureBurst extends StatefulWidget {
  final int index;
  final MPiece piece;
  final double cell;
  final double inset;
  final PieceColor viewer;
  final String pieceSet;
  final Duration duration;

  const _CaptureBurst({
    super.key,
    required this.index,
    required this.piece,
    required this.cell,
    required this.inset,
    required this.viewer,
    required this.pieceSet,
    required this.duration,
  });

  @override
  State<_CaptureBurst> createState() => _CaptureBurstState();
}

class _CaptureBurstState extends State<_CaptureBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: widget.duration,
    vsync: this,
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.index % 8;
    final rank = widget.index ~/ 8;
    final displayFile = widget.viewer == PieceColor.white ? file : 7 - file;
    final displayRow = widget.viewer == PieceColor.white ? 7 - rank : rank;
    return Positioned(
      left: widget.inset + displayFile * widget.cell,
      top: widget.inset + displayRow * widget.cell,
      width: widget.cell,
      height: widget.cell,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _curve.value;
              final opacity = 1 - progress;
              final scale = 1 - progress * .28;
              return CustomPaint(
                painter: _CaptureVfxPainter(
                  progress: progress,
                  color:
                      widget.piece.color == PieceColor.white
                          ? LunoColors.ivory
                          : LunoColors.gold,
                ),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Padding(
                      padding: EdgeInsets.all(widget.cell * .075),
                      child: LunoArt(
                        LunoAssets.pieceForSet(
                          widget.pieceSet,
                          widget.piece.color,
                          widget.piece.type,
                        ),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CaptureVfxPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CaptureVfxPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final radius = size.shortestSide * (.14 + progress * .45);

    final halo = Paint()..color = color.withValues(alpha: .12 * fade);
    canvas.drawCircle(center, radius * .78, halo);

    final ring =
        Paint()
          ..color = color.withValues(alpha: .82 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * .025 * fade;
    canvas.drawCircle(center, radius, ring);

    final shardPaint = Paint()..color = color.withValues(alpha: .9 * fade);
    final shardRadius = size.shortestSide * (.12 + progress * .34);
    for (var i = 0; i < 8; i++) {
      final angle = (math.pi * 2 * i / 8) + math.pi / 8;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * shardRadius;
      final shardSize = size.shortestSide * (.018 + .012 * fade);
      canvas.drawCircle(point, shardSize, shardPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaptureVfxPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
