import 'package:flutter_test/flutter_test.dart';

import 'package:luno_chess/data/rank_catalog.dart';

void main() {
  test('arena boundaries are contiguous and unambiguous', () {
    expect(kArenaCatalog.length, 9);
    for (var index = 0; index < kArenaCatalog.length; index++) {
      final arena = kArenaCatalog[index];
      expect(arena.index, index);
      expect(
        arena.minTrophies,
        index == 0 ? 0 : kArenaCatalog[index - 1].maxTrophies! + 1,
      );
      if (arena.maxTrophies != null) {
        expect(arena.maxTrophies, greaterThanOrEqualTo(arena.minTrophies));
      }
    }
  });

  test('trophy boundaries resolve to exactly one arena', () {
    const checks = <(int, int)>[
      (0, 0),
      (99, 0),
      (100, 1),
      (299, 1),
      (300, 2),
      (599, 2),
      (600, 3),
      (999, 3),
      (1000, 4),
      (1499, 4),
      (1500, 5),
      (2199, 5),
      (2200, 6),
      (2999, 6),
      (3000, 7),
      (3999, 7),
      (4000, 8),
    ];
    for (final (trophies, expected) in checks) {
      expect(arenaIndexForTrophies(trophies), expected);
    }
    expect(arenaIndexForTrophies(-500), 0);
    expect(arenaIndexForTrophies(1000000), 8);
  });

  test('protected rank is preserved while stale rank data is repaired', () {
    expect(arenaIndexForPlayer(150, 0), 1);
    expect(arenaIndexForPlayer(50, 2), 0);
    expect(arenaIndexForPlayer(300, 1), 2);
    expect(arenaIndexForPlayer(600, 1), 3);
    expect(arenaForIndex(8).name, 'Luno Mythic');
  });

  test('progress and labels use the active arena span', () {
    expect(arenaProgress(0, 0), 0);
    expect(arenaProgress(99, 0), 0.99);
    expect(arenaProgress(100, 1), 0);
    expect(arenaProgress(299, 1), 0.995);
    expect(arenaProgress(4000, 8), 1);
    expect(arenaProgressLabel(100, 1), '0 / 200');
    expect(arenaProgressLabel(4000, 8), '0 kupa');
    expect(formatTrophies(2200), '2.200');
  });

  test('ranked trophy rewards are exposed per arena', () {
    expect(
      kArenaCatalog
          .map((arena) => (arena.winTrophies, arena.lossTrophies))
          .toList(),
      const <(int, int)>[
        (32, 8),
        (30, 10),
        (28, 12),
        (25, 15),
        (22, 18),
        (20, 20),
        (20, 20),
        (19, 21),
        (18, 22),
      ],
    );
  });
}
