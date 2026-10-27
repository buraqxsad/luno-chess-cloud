import 'package:flutter/material.dart';
import '../engine/piece.dart';
import '../theme/luno_assets.dart';

class BattleArt extends StatelessWidget {
  final String name;
  final double? size;
  final BoxFit fit;
  const BattleArt(this.name, {super.key, this.size, this.fit = BoxFit.contain});
  static String path(String name) =>
      name == 'action-face'
          ? 'assets/native_art/battle-action-face-v212.webp'
          : name == 'card-frame'
          ? 'assets/native_art/v205-card-face.png'
          : 'assets/native_art/battle-v202b-$name.webp';
  static String piecePath(
    PieceColor side,
    PieceType type, {
    String set = 'luno',
  }) =>
      set == 'luno' ||
              !const {
                'ottoman',
                'roma',
                'brit',
                'viking',
                'tasdevri',
                'samuray',
                'ice',
                'dragon',
                'neon',
              }.contains(set)
          ? path('piece-${side.isWhite ? 'w' : 'b'}-${type.name}')
          : LunoAssets.pieceForSet(set, side, type);
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      path(name),
      width: size,
      height: size,
      fit: fit,
      cacheWidth:
          size == null
              ? null
              : (size! * MediaQuery.devicePixelRatioOf(context)).ceil(),
    ),
  );
}

class BattleSkin extends StatelessWidget {
  final String name;
  final Widget child;
  const BattleSkin({super.key, required this.name, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: IgnorePointer(child: BattleArt(name, fit: BoxFit.fill)),
      ),
      child,
    ],
  );
}
