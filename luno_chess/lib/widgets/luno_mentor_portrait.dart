import 'package:flutter/material.dart';

import '../theme/luno_assets.dart';

/// A finite Blender puppet of the original illustration, not an idle ticker.
/// Rest and reduced motion use the original image and do not decode the atlas.
class LunoMentorPortrait extends StatelessWidget {
  static const atlas = 'assets/native_art/tutorial-luno-live-atlas.webp';
  static const frameCount = 16;
  static const columns = 4;
  static const decodedBytes = 640 * 640 * 4;

  const LunoMentorPortrait({
    super.key,
    required this.progress,
    required this.size,
  });

  final double progress;
  final double size;

  static int frameAt(double progress) =>
      progress.isFinite
          ? (progress.clamp(0.0, 1.0) * frameCount).floor().clamp(
            0,
            frameCount - 1,
          )
          : 0;

  Widget _still() => Image.asset(
    LunoAssets.lunoPortrait,
    cacheWidth: 192,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );

  @override
  Widget build(BuildContext context) {
    if (!size.isFinite || size <= 0) return const SizedBox.shrink();
    if (!progress.isFinite ||
        progress <= 0 ||
        progress >= 1 ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return SizedBox.square(dimension: size, child: _still());
    }
    final frame = frameAt(progress);
    final offset = Offset((frame % columns) * size, (frame ~/ columns) * size);
    // Keep the original visible until the one texture has decoded. Its position
    // cancels the atlas crop, so late decoding cannot leave an empty portrait.
    Widget fallback() => SizedBox.square(
      dimension: size * columns,
      child: Align(
        alignment: Alignment.topLeft,
        child: Transform.translate(
          offset: offset,
          child: SizedBox.square(dimension: size, child: _still()),
        ),
      ),
    );
    return SizedBox.square(
      key: ValueKey('luno-portrait-frame-$frame'),
      dimension: size,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size * columns,
          maxWidth: size * columns,
          minHeight: size * columns,
          maxHeight: size * columns,
          child: Transform.translate(
            offset: -offset,
            child: Image.asset(
              atlas,
              width: size * columns,
              height: size * columns,
              cacheWidth: 640,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
              frameBuilder:
                  (_, child, imageFrame, _) =>
                      imageFrame == null ? fallback() : child,
            ),
          ),
        ),
      ),
    );
  }
}
