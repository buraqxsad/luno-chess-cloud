import 'package:flutter/material.dart' hide Text;

import '../i18n/luno_text.dart';
import '../models/game_store.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../theme/luno_visual_assets.dart';
import 'luno_polish.dart';
import 'resource_amount.dart';

/// Altın + elmas göstergesi (store değişince kendini günceller).
class CurrencyBar extends StatelessWidget {
  const CurrencyBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameStore.instance,
      builder: (context, _) {
        final d = GameStore.instance.data;
        return LayoutBuilder(
          builder:
              (context, constraints) => Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(
                    LunoAssets.coin,
                    d.gold,
                    LunoColors.gold,
                    constraints.maxWidth,
                  ),
                  _pill(
                    LunoAssets.gem,
                    d.gems,
                    LunoColors.cyan,
                    constraints.maxWidth,
                  ),
                ],
              ),
        );
      },
    );
  }

  Widget _pill(String art, int value, Color color, double maxWidth) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: LunoColors.bgPanel,
        image: lunoFace(LunoVisualAssets.neutral, opacity: .7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LunoColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LunoCurrencyArt(art, size: 38),
          const SizedBox(width: 5),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
