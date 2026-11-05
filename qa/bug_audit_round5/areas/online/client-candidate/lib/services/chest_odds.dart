import 'dart:convert';

import 'chest_odds_contract.dart';

class ChestOddsItem {
  const ChestOddsItem({
    required this.type,
    required this.id,
    required this.rarity,
    required this.amountOdds,
  });
  final String type;
  final String id;
  final String rarity;
  final Map<int, double> amountOdds;
  double get chance =>
      amountOdds.values.fold<double>(0, (sum, value) => sum + value);
}

class ChestOdds {
  ChestOdds._({
    required this.chestId,
    required this.currency,
    required this.price,
    required this.goldMin,
    required this.goldMax,
    required this.fallbackChance,
    required this.items,
  });
  static final Map<String, dynamic> contract =
      jsonDecode(chestOddsContractJson) as Map<String, dynamic>;
  static const _draws = 0x100000000;
  final String chestId;
  final String currency;
  final int price;
  final int goldMin;
  final int goldMax;
  final double fallbackChance;
  final List<ChestOddsItem> items;
  bool get canPurchase => items.isNotEmpty;

  // The backend samples a uint32 divided by 2^32, including zero.
  static double _gate(num chance) => (chance * _draws).ceil() / _draws;
  static double _pick(int index, int count) =>
      (((index + 1) * _draws / count).ceil() -
          (index * _draws / count).ceil()) /
      _draws;

  double goldAmountChance(int amount) =>
      amount < goldMin || amount > goldMax
          ? 0
          : _pick(amount - goldMin, goldMax - goldMin + 1);

  factory ChestOdds.fromPlayerState(
    String chestId,
    Map<String, dynamic> state,
  ) {
    final chest = (contract['chests'] as Map)[chestId];
    final inventory = state['inventory'];
    if (chest is! Map || inventory is! Map) {
      throw const FormatException('Missing authoritative chest inventory');
    }
    final pools = contract['pools'] as Map;
    const fields = {
      'skin': ['ownedSkins', 'skinPieces'],
      'emoji': ['ownedEmojis', 'emojiPieces'],
      'frame_shard': ['ownedFrames', 'frameShards'],
      'bioframe_shard': ['ownedBioFrames', 'bioFrameShards'],
    };
    final remaining = <String, Map<String, int>>{};
    for (final entry in fields.entries) {
      final owned = inventory[entry.value[0]];
      // Legacy server inventories omit empty piece maps; rollChest treats them as zero.
      final pieces = inventory[entry.value[1]] ?? const <String, num>{};
      if (owned is! List ||
          pieces is! Map ||
          owned.any((id) => id is! String) ||
          pieces.values.any(
            (n) =>
                n is! num || !n.isFinite || n < 0 || n != n.truncateToDouble(),
          )) {
        throw const FormatException('Incomplete authoritative chest inventory');
      }
      remaining[entry.key] = {
        for (final item in (pools[entry.key] as Map).entries)
          if (!owned.contains(item.key) &&
              (pieces[item.key] as num? ?? 0) < item.value['target'])
            item.key as String:
                (item.value['target'] as num).toInt() -
                (pieces[item.key] as num? ?? 0).toInt(),
      };
    }
    final targets = <_OddsTarget>[];
    final groups = <List<_OddsTarget>>[];
    final gates = <double>[];
    final drops = chest['drops'] as Map;
    for (final entry in drops.entries) {
      if (entry.key == 'gold') continue;
      final parts = (entry.key as String).split('_');
      final type = parts[0], rarity = parts[1];
      final drop = entry.value as Map;
      if ((drop['chance'] as num) <= 0) continue;
      final group = <_OddsTarget>[
        for (final id in remaining[type]!.keys)
          if ((pools[type] as Map)[id]['rarity'] == rarity)
            _OddsTarget(
              type,
              id,
              rarity,
              remaining[type]![id]!,
              (drop['min'] as num).toInt(),
              (drop['max'] as num).toInt(),
            ),
      ];
      targets.addAll(group);
      groups.add(group);
      gates.add(group.isEmpty ? 0 : _gate(drop['chance'] as num));
    }
    final rarities = [
      'legendary',
      if (chestId == 'legendary' || chestId == 'royal') 'mythic',
    ];
    for (final type in ['frame_shard', 'bioframe_shard']) {
      // Fallback order groups by rarity; regular shard selection uses catalog order.
      final fallbackGroup = <_OddsTarget>[
        for (final rarity in rarities)
          for (final id in remaining[type]!.keys)
            if ((pools[type] as Map)[id]['rarity'] == rarity)
              _OddsTarget(type, id, rarity, remaining[type]![id]!, 1, 1),
      ];
      targets.addAll(fallbackGroup);
      final group = <_OddsTarget>[
        for (final id in remaining[type]!.keys)
          for (final target in fallbackGroup)
            if (target.id == id) target,
      ];
      groups.add(group);
      gates.add(
        group.isEmpty
            ? 0
            : _gate(
              (contract[type == 'frame_shard' ? 'frameChance' : 'bioChance']
                      as Map)[chestId]
                  as num,
            ),
      );
    }
    final fallback = gates.fold<double>(
      1,
      (value, chance) => value * (1 - chance),
    );
    final odds = <ChestOddsItem>[];
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final groupIndex = groups.indexWhere((group) => group.contains(target));
      final group = groups[groupIndex];
      final normal =
          gates[groupIndex] * _pick(group.indexOf(target), group.length);
      final rescue = fallback * _pick(index, targets.length);
      final amounts = <int, double>{};
      void add(int amount, double probability) {
        final delivered = amount > target.remaining ? target.remaining : amount;
        amounts.update(
          delivered,
          (value) => value + probability,
          ifAbsent: () => probability,
        );
      }

      if (target.type == 'frame_shard') {
        final two = _gate(contract['frameTwoPieceChance'] as num);
        add(1, normal * (1 - two) + rescue);
        add(2, normal * two);
      } else {
        for (var amount = target.min; amount <= target.max; amount++) {
          add(
            amount,
            (normal + rescue) *
                _pick(amount - target.min, target.max - target.min + 1),
          );
        }
      }
      odds.add(
        ChestOddsItem(
          type: target.type,
          id: target.id,
          rarity: target.rarity,
          amountOdds: Map.unmodifiable(amounts),
        ),
      );
    }
    final gold = drops['gold'] as Map;
    return ChestOdds._(
      chestId: chestId,
      currency: chest['currency'] as String,
      price: (chest['price'] as num).toInt(),
      goldMin: (gold['min'] as num).toInt(),
      goldMax: (gold['max'] as num).toInt(),
      fallbackChance: targets.isEmpty ? 0 : fallback,
      items: List.unmodifiable(odds),
    );
  }
}

class _OddsTarget {
  const _OddsTarget(
    this.type,
    this.id,
    this.rarity,
    this.remaining,
    this.min,
    this.max,
  );
  final String type, id, rarity;
  final int remaining, min, max;
}
