import 'package:flutter/material.dart';
import '../battle_v1/deck_metrics.dart';
import '../battle_v1/model.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../theme/luno_theme.dart';

class BattleDeckMana extends StatelessWidget {
  final Iterable<CardId> cards;
  const BattleDeckMana({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final stats = BattleDeckMetrics.fromCards(cards);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.learning(
            'Ortalama mana: ${stats.average.toStringAsFixed(1)}',
            'Average mana: ${stats.average.toStringAsFixed(1)}',
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var index = 0; index < 4; index++)
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index == 3 ? '4+' : index + 1} mana · ${stats.curve[index]}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value:
                          stats.count == 0
                              ? 0
                              : stats.curve[index] / stats.count,
                      minHeight: 4,
                      color: LunoColors.gold,
                      backgroundColor: LunoColors.bgDeep,
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (stats.heavy) ...[
          const SizedBox(height: 8),
          Text(
            l.learning(
              'Ağır deste: İlk turlarda oynanabilir kart bulmak zorlaşabilir.',
              'Heavy deck: Playable cards can be harder to find in early turns.',
            ),
            style: const TextStyle(fontSize: 12, color: LunoColors.gold),
          ),
        ],
      ],
    );
  }
}
