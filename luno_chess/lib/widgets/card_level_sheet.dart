import 'package:flutter/material.dart' hide Text;

import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../i18n/luno_text.dart';
import '../services/luno_feedback.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import 'resource_amount.dart';

Future<String?> showCardLevelSheet(
  BuildContext context,
  CardDef held,
  int mana,
) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    return Future.value();
  }
  var selected = false;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF263F43),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder:
        (ctx) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SEVİYE SEÇ', style: LunoType.sectionTitle),
                const SizedBox(height: 14),
                for (var level = 1; level <= held.level; level++)
                  if (familyKeyAtLevel(held.family, level)
                      case final String key)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: const Color(0xFF315457),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap:
                              mana < kCards[key]!.mana
                                  ? null
                                  : () {
                                    if (selected ||
                                        !ctx.mounted ||
                                        ModalRoute.of(ctx)?.isCurrent != true) {
                                      return;
                                    }
                                    selected = true;
                                    LunoFeedback.tap();
                                    Navigator.of(ctx).pop(key);
                                  },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 58,
                                  height: 72,
                                  child: LunoArt(LunoAssets.card(key, level)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Sv$level · ${kCards[key]!.name}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        kCards[key]!.desc,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.4,
                                          color: Color(0xFFE0E8E3),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ResourceAmount.mana(
                                        kCards[key]!.mana,
                                        iconSize: 20,
                                        fontSize: 14,
                                        color:
                                            mana >= kCards[key]!.mana
                                                ? LunoColors.gold
                                                : LunoColors.danger,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
  );
}
