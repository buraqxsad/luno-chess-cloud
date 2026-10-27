import 'package:flutter/material.dart';

import '../data/board_finishes.dart';
import '../navigation/luno_account_modal.dart';
import '../services/chest_odds.dart';
import '../services/cosmetic_catalog.dart';

class ChestOddsDialog extends StatelessWidget {
  const ChestOddsDialog({super.key, required this.odds, required this.english});
  final ChestOdds odds;
  final bool english;
  String copy(String tr, String en) => english ? en : tr;
  String percent(double value) => '${(value * 100).toStringAsFixed(6)}%';

  String itemTitle(ChestOddsItem item) {
    final kind = switch (item.type) {
      'skin' => copy('Tahta yüzeyi', 'Board finish'),
      'emoji' => copy('İfade', 'Emote'),
      'frame_shard' => copy('Çerçeve', 'Frame'),
      _ => copy('Profil çerçevesi', 'Bio frame'),
    };
    final name = switch (item.type) {
      'skin' => boardFinish(item.id).title(english),
      'emoji' => cosmeticEmote(item.id)?.title(english) ?? item.id,
      _ => switch (item.id) {
        'galaxy' => copy('Galaksi', 'Galaxy'),
        'phoenix' => copy('Anka', 'Phoenix'),
        'rainbow' => copy('Gökkuşağı', 'Rainbow'),
        'aurora' => 'Aurora',
        _ => item.id,
      },
    };
    final rarity = CosmeticRarity.values
        .firstWhere((value) => value.name == item.rarity)
        .title(english);
    return '$kind: $name ($rarity)';
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        odds.currency == 'gems' ? copy('elmas', 'gems') : copy('altın', 'gold');
    final goldChances = [
      for (var n = odds.goldMin; n <= odds.goldMax; n++)
        odds.goldAmountChance(n),
    ];
    final goldLowest = goldChances.reduce((a, b) => a < b ? a : b);
    final goldHighest = goldChances.reduce((a, b) => a > b ? a : b);
    return AlertDialog(
      key: const ValueKey('chest-odds-dialog'),
      title: Text(copy('Sandık olasılıkları', 'Chest odds')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy(
                  'Güncel koleksiyonuna göre. Sahip olunan veya parçası tamamlanan hedefler çıkarılır. Başka cihazdaki koleksiyon değişiklikleri olasılıkları değiştirebilir.',
                  'Based on your latest collection. Owned or completed targets are excluded. Collection changes on another device can change the odds.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${copy('Altın', 'Gold')}: ${odds.goldMin}-${odds.goldMax} (100%).',
              ),
              Text(
                copy(
                  'Bu aralıktaki her tam sayı miktarının olasılığı (32-bit çekim): ${percent(goldLowest)}-${percent(goldHighest)}.',
                  'Probability of each integer amount in this range (32-bit draw): ${percent(goldLowest)}-${percent(goldHighest)}.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                copy(
                  'Birden fazla kozmetik çıkabilir; yüzdeler toplamı 100 olmak zorunda değildir. Normal çekim kozmetik vermezse kalan hedeflerden biri seçilir. Aşağıdaki olasılıklar bu garantili ek seçimi içerir. Parça miktarları koleksiyonuna eklenen ilerlemeyi gösterir; çekim fazladan parça içerse de ilerleme kalan hedef miktarıyla sınırlıdır. Yüzdeler 6 ondalığa yuvarlanmıştır.',
                  'Multiple cosmetics can drop; percentages need not total 100. If normal rolls give no cosmetic, one remaining target is selected. The odds below include that guaranteed fallback. Piece amounts show added collection progress; a roll can contain extra pieces, but progress is capped at the remaining target amount. Percentages are rounded to 6 decimals.',
                ),
              ),
              Text(
                '${copy('Garantili ek seçim devreye girme şansı', 'Fallback activation chance')}: ${percent(odds.fallbackChance)}',
              ),
              const SizedBox(height: 8),
              if (!odds.canPurchase)
                Text(
                  copy(
                    'Bu sandıkta kalan kozmetik hedefin yok.',
                    'No cosmetic target remains in this chest.',
                  ),
                ),
              for (final item in odds.items)
                Padding(
                  key: ValueKey('chest-odds-${item.type}-${item.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${itemTitle(item)}: ${percent(item.chance)}\n'
                    '${item.amountOdds.entries.map((entry) => '${entry.key} ${copy('parça', 'piece(s)')}: ${percent(entry.value)}').join('; ')}',
                  ),
                ),
              Text(
                copy(
                  'Rekabetçi kart çıkma olasılığı: 0%.',
                  'Competitive card drop chance: 0%.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('chest-odds-cancel'),
          onPressed: () => dismissLunoAccountModal(context, false),
          child: Text(copy('Vazgeç', 'Cancel')),
        ),
        FilledButton.icon(
          key: const ValueKey('chest-odds-confirm'),
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed:
              odds.canPurchase
                  ? () => dismissLunoAccountModal(context, true)
                  : null,
          label: Text(
            copy(
              '${odds.price} $currency karşılığında aç',
              'Open for ${odds.price} $currency',
            ),
          ),
        ),
      ],
    );
  }
}
