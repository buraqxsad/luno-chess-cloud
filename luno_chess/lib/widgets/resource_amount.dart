import 'package:flutter/material.dart' hide Text;

import '../i18n/luno_text.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';

/// Original currency bitmaps have a wide transparent safety margin.
class LunoCurrencyArt extends StatelessWidget {
  final String art;
  final double size;
  const LunoCurrencyArt(this.art, {super.key, required this.size});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipRect(
      child: Transform.scale(
        scale:
            {LunoAssets.coin, LunoAssets.gem, LunoAssets.trophy}.contains(art)
                ? 2.15
                : 1,
        child: LunoArt(
          art,
          width: size,
          height: size,
          decodeScale:
              {LunoAssets.coin, LunoAssets.gem, LunoAssets.trophy}.contains(art)
                  ? 2.15
                  : 1,
        ),
      ),
    ),
  );
}

/// Compact resource value used across cards, rewards and match HUD.
/// Keeping the icon outside the text prevents emoji fallback and text drift.
class ResourceAmount extends StatelessWidget {
  final String? art;
  final IconData? icon;
  final int value;
  final Color color;
  final double iconSize;
  final double fontSize;

  const ResourceAmount({
    super.key,
    this.art,
    this.icon,
    required this.value,
    required this.color,
    this.iconSize = 16,
    this.fontSize = 11,
  });

  const ResourceAmount.coin(
    int value, {
    Key? key,
    Color color = LunoColors.gold,
    double iconSize = 16,
    double fontSize = 11,
  }) : this(
         key: key,
         art: LunoAssets.coin,
         value: value,
         color: color,
         iconSize: iconSize,
         fontSize: fontSize,
       );

  const ResourceAmount.gem(
    int value, {
    Key? key,
    Color color = const Color(0xFF5DE4FF),
    double iconSize = 16,
    double fontSize = 11,
  }) : this(
         key: key,
         art: LunoAssets.gem,
         value: value,
         color: color,
         iconSize: iconSize,
         fontSize: fontSize,
       );

  const ResourceAmount.mana(
    int value, {
    Key? key,
    Color color = LunoColors.gold,
    double iconSize = 15,
    double fontSize = 11,
  }) : this(
         key: key,
         icon: Icons.water_drop_rounded,
         value: value,
         color: color,
         iconSize: iconSize,
         fontSize: fontSize,
       );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (art != null)
          LunoCurrencyArt(art!, size: iconSize)
        else
          Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
