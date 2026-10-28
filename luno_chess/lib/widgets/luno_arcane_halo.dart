import 'package:flutter/material.dart';

/// A finite, pre-rendered Blender energy ring. The caller owns the clock;
/// this widget creates no ticker, gameplay state, audio or network requests.
class LunoArcaneHalo extends StatelessWidget {
  static const asset = 'assets/native_art/v237-arcane-halo-atlas.webp';
  static const columns = 4;
  static const frameCount = 16;

  final double progress;
  final double size;
  final Color color;
  final double opacity;
  final String atlasAsset;

  const LunoArcaneHalo({
    super.key,
    required this.progress,
    required this.size,
    this.color = const Color(0xffb5ecff),
    this.opacity = 1,
    this.atlasAsset = asset,
  });

  static int frameAt(double progress) =>
      progress.isFinite
          ? (progress.clamp(0.0, 1.0) * frameCount).floor().clamp(
            0,
            frameCount - 1,
          )
          : 0;

  @override
  Widget build(BuildContext context) {
    if (!size.isFinite || size <= 0) return const SizedBox.shrink();
    if (!progress.isFinite ||
        progress <= 0 ||
        progress >= 1 ||
        !opacity.isFinite ||
        opacity <= 0 ||
        color.a <= 0 ||
        MediaQuery.disableAnimationsOf(context)) {
      return SizedBox.square(dimension: size);
    }
    final frame = frameAt(progress);
    final fadeIn = (progress / .09).clamp(0.0, 1.0);
    final fadeOut = ((1 - progress) / .35).clamp(0.0, 1.0);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: size * columns,
              maxWidth: size * columns,
              minHeight: size * columns,
              maxHeight: size * columns,
              child: Transform.translate(
                offset: Offset(
                  -(frame % columns) * size,
                  -(frame ~/ columns) * size,
                ),
                child: Image.asset(
                  atlasAsset,
                  width: size * columns,
                  height: size * columns,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.low,
                  color: color.withValues(
                    alpha: color.a * opacity.clamp(0.0, 1.0) * fadeIn * fadeOut,
                  ),
                  colorBlendMode: BlendMode.modulate,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
