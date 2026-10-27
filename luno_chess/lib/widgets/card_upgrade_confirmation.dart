import 'package:flutter/material.dart' hide Text;

import '../data/card_pool.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/luno_text.dart';
import '../theme/luno_assets.dart';
import 'luno_surface.dart';
import 'resource_amount.dart';

Future<bool> confirmCardUpgrade(
  BuildContext context,
  String family,
  int level,
) async {
  final card = tryCardForOwned(family, level + 1);
  if (!context.mounted ||
      ModalRoute.of(context)?.isCurrent != true ||
      !isFamily(family) ||
      level < 1 ||
      level > 2 ||
      card == null) {
    return false;
  }
  var decided = false;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) {
          void finish(bool accepted) {
            if (decided ||
                !ctx.mounted ||
                ModalRoute.of(ctx)?.isCurrent != true) {
              return;
            }
            decided = true;
            Navigator.of(ctx).pop(accepted);
          }

          final strings = LunoLocalizations.of(ctx);
          return AlertDialog(
            backgroundColor: const Color(0xFF29423F),
            scrollable: true,
            title: Text(strings.isEnglish ? 'Upgrade card' : 'Kartı yükselt'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 96,
                  height: 112,
                  child: LunoArt(LunoAssets.card(card.key, card.level)),
                ),
                const SizedBox(height: 12),
                Text(
                  card.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(strings.cardLevel(level + 1, card.maxLevel)),
                const SizedBox(height: 16),
                ResourceAmount.coin(
                  upgradeGoldCost(level),
                  iconSize: 28,
                  fontSize: 22,
                ),
              ],
            ),
            actions: [
              LunoButton(
                label: strings.isEnglish ? 'UPGRADE' : 'YÜKSELT',
                icon: Icons.upgrade_rounded,
                onPressed: () => finish(true),
              ),
              const SizedBox(height: 8),
              LunoButton(
                label: 'VAZGEÇ',
                kind: LunoButtonKind.secondary,
                icon: Icons.close_rounded,
                onPressed: () => finish(false),
              ),
            ],
          );
        },
      ) ??
      false;
}
