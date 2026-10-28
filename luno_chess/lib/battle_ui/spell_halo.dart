import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../widgets/luno_arcane_halo.dart';
import 'effect_timing.dart';
import 'spell_vfx.dart';
import 'spell_motifs.dart';

/// A quiet, open-centred ring behind the readable, card-specific spell outline.
/// It receives only the same public cue as the vector painter.
class BattleSpellHalo extends StatelessWidget {
  final BattleSpellCue cue;
  final PieceColor viewer;
  final double progress;
  final Color color;

  const BattleSpellHalo({
    super.key,
    required this.cue,
    required this.viewer,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!cue.isActive ||
        !progress.isFinite ||
        progress <= battleCastArrivalFraction ||
        progress >= 1 ||
        MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
          return const SizedBox.shrink();
        }
        final cell = size.shortestSide / 8;
        final target = battleSpellTarget(cue, viewer, size);
        final diameter = cell * (cue.squares.length > 1 ? 3.05 : 2.5);
        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: target.dx - diameter / 2,
                top: target.dy - diameter / 2,
                child: LunoArcaneHalo(
                  progress:
                      (progress - battleCastArrivalFraction) /
                      (1 - battleCastArrivalFraction),
                  size: diameter,
                  color: Color.lerp(color, Colors.white, .12)!,
                  opacity: switch (cardDefinitions[cue.card]!.category) {
                    CardCategory.board || CardCategory.modifier => .6,
                    CardCategory.knowledge => .42,
                    _ => .5,
                  },
                  atlasAsset: battleSpellMotif(cue.card).asset,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
