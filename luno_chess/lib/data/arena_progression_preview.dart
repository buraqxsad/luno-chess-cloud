import 'rank_catalog.dart';

/// Read-only previews of existing functions/lib/catalogs.js rewards.
/// Eligibility, season peak, claims and delivery stay on the server-backed pages.
class ArenaPathPreview {
  final String id;
  final int trophies;
  final int gold;
  final int gems;

  const ArenaPathPreview(this.id, this.trophies, this.gold, this.gems);
}

class ArenaAchievementPreview {
  final String id;
  final int arenaNumber;
  final int gold;
  final int gems;

  const ArenaAchievementPreview(
    this.id,
    this.arenaNumber,
    this.gold,
    this.gems,
  );
}

const kArenaPathPreviews = <ArenaPathPreview>[
  ArenaPathPreview('path_1', 0, 100, 0),
  ArenaPathPreview('path_2', 100, 150, 0),
  ArenaPathPreview('path_3', 300, 0, 5),
  ArenaPathPreview('path_4', 600, 250, 0),
  ArenaPathPreview('path_5', 1000, 350, 5),
  ArenaPathPreview('path_6', 1500, 500, 0),
  ArenaPathPreview('path_7', 2200, 600, 10),
  ArenaPathPreview('path_8', 3000, 750, 0),
  ArenaPathPreview('path_9', 4000, 1000, 15),
  ArenaPathPreview('path_10', 5000, 1500, 25),
];

const kArenaAchievementPreviews = <ArenaAchievementPreview>[
  ArenaAchievementPreview('arena_3', 3, 500, 0),
  ArenaAchievementPreview('arena_5', 5, 1500, 0),
  ArenaAchievementPreview('arena_7', 7, 4000, 15),
  ArenaAchievementPreview('arena_8', 8, 10000, 30),
  ArenaAchievementPreview('arena_9', 9, 25000, 75),
];

ArenaPathPreview arenaPathPreview(int arenaIndex) =>
    kArenaPathPreviews[arenaForIndex(arenaIndex).index];

ArenaAchievementPreview? arenaAchievementPreview(int arenaIndex) {
  for (final item in kArenaAchievementPreviews) {
    if (item.arenaNumber == arenaIndex + 1) return item;
  }
  return null;
}

ArenaAchievementPreview nextArenaAchievementPreview(int arenaIndex) =>
    kArenaAchievementPreviews.firstWhere(
      (item) => item.arenaNumber >= arenaForIndex(arenaIndex).index + 1,
      orElse: () => kArenaAchievementPreviews.last,
    );
