import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';

void main() {
  final store = GameStore.instance;
  late PlayerData original;
  setUp(() {
    original = store.data;
    store.data = PlayerData.initial();
  });
  tearDown(() => store.data = original);

  test(
    'all five families require server price and trophy arena at both levels',
    () {
      const expected = {
        'trap': [2, 4],
        'radar': [2, 4],
        'resist': [3, 5],
        'shield': [4, 6],
        'deploy': [6, 7],
      };
      for (final entry in expected.entries) {
        store.data.ownedCards.add(entry.key);
        for (var level = 1; level <= 2; level++) {
          final price = level == 1 ? 2500 : 5000;
          final arena = entry.value[level - 1];
          final threshold = arenaForIndex(arena).minTrophies;
          expect(upgradeGoldCost(level), price);
          expect(upgradeRequiredArena(entry.key, level), arena);
          store.data.cardLevel[entry.key] = level;
          store.data.gold = price;
          store.data.arenaIdx =
              8; // Stale cached rank must not unlock an upgrade.
          store.data.trophies = threshold - 1;
          expect(store.canUpgrade(entry.key), false, reason: entry.key);
          store.data.trophies = threshold;
          expect(store.canUpgrade(entry.key), true, reason: entry.key);
          expect(store.canUpgrade('${entry.key}$level'), true);
          store.data.gold = price - 1;
          expect(store.canUpgrade(entry.key), false, reason: entry.key);
        }
      }
    },
  );

  test('unowned, non-upgradeable and invalid levels remain unavailable', () {
    store.data.gold = 999999;
    store.data.trophies = 999999;
    expect(store.canUpgrade('trap'), false);
    expect(store.canUpgrade('barbarian'), false);
    store.data.ownedCards.add('trap');
    for (final level in [-1, 0, 3, 4]) {
      store.data.cardLevel['trap'] = level;
      expect(store.canUpgrade('trap'), false);
    }
  });
}
