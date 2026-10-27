/// The single client-side contract for ranked arenas.
///
/// `maxTrophies` is inclusive. The server stores the same boundaries as
/// exclusive upper limits, so a boundary can never belong to two arenas.
class ArenaDefinition {
  final int index;
  final String asset;
  final String name;
  final String displayName;
  final int minTrophies;
  final int? maxTrophies;
  final int winTrophies;
  final int lossTrophies;

  const ArenaDefinition({
    required this.index,
    required this.asset,
    required this.name,
    required this.displayName,
    required this.minTrophies,
    required this.maxTrophies,
    required this.winTrophies,
    required this.lossTrophies,
  });

  int get trophySpan =>
      maxTrophies == null ? 0 : maxTrophies! - minTrophies + 1;

  String get rangeLabel {
    final min = formatTrophies(minTrophies);
    final max = maxTrophies;
    return max == null ? '$min+ kupa' : '$min - ${formatTrophies(max)} kupa';
  }
}

/// Keep this order and the server `ARENAS` table in lockstep.
const kArenaCatalog = <ArenaDefinition>[
  ArenaDefinition(
    index: 0,
    asset: 'arena-01-acemi-v24.webp',
    name: 'Acemi Kampı',
    displayName: 'ACEMİ KAMPI',
    minTrophies: 0,
    maxTrophies: 99,
    winTrophies: 32,
    lossTrophies: 8,
  ),
  ArenaDefinition(
    index: 1,
    asset: 'arena-02-piyon-v24.webp',
    name: 'Piyon Vadisi',
    displayName: 'PİYON VADİSİ',
    minTrophies: 100,
    maxTrophies: 299,
    winTrophies: 30,
    lossTrophies: 10,
  ),
  ArenaDefinition(
    index: 2,
    asset: 'arena-03-hukumdar-v24.webp',
    name: 'Hükümdar',
    displayName: 'HÜKÜMDAR',
    minTrophies: 300,
    maxTrophies: 599,
    winTrophies: 28,
    lossTrophies: 12,
  ),
  ArenaDefinition(
    index: 3,
    asset: 'arena-04-golge-v24.webp',
    name: 'Gölge Hükümdarı',
    displayName: 'GÖLGE HÜKÜMDARI',
    minTrophies: 600,
    maxTrophies: 999,
    winTrophies: 25,
    lossTrophies: 15,
  ),
  ArenaDefinition(
    index: 4,
    asset: 'arena-05-imparator-v24.webp',
    name: 'İmparator',
    displayName: 'İMPARATOR',
    minTrophies: 1000,
    maxTrophies: 1499,
    winTrophies: 22,
    lossTrophies: 18,
  ),
  ArenaDefinition(
    index: 5,
    asset: 'arena-06-usta-v24.webp',
    name: 'Luno Ustası',
    displayName: 'LUNO USTASI',
    minTrophies: 1500,
    maxTrophies: 2199,
    winTrophies: 20,
    lossTrophies: 20,
  ),
  ArenaDefinition(
    index: 6,
    asset: 'arena-07-kraliyet-v24.webp',
    name: 'Luno Kraliyeti',
    displayName: 'LUNO KRALİYETİ',
    minTrophies: 2200,
    maxTrophies: 2999,
    winTrophies: 20,
    lossTrophies: 20,
  ),
  ArenaDefinition(
    index: 7,
    asset: 'arena-08-legend-v24.webp',
    name: 'Luno Legend',
    displayName: 'LUNO LEGEND',
    minTrophies: 3000,
    maxTrophies: 3999,
    winTrophies: 19,
    lossTrophies: 21,
  ),
  ArenaDefinition(
    index: 8,
    asset: 'arena-09-mythic-v24.webp',
    name: 'Luno Mythic',
    displayName: 'LUNO MYTHIC',
    minTrophies: 4000,
    maxTrophies: null,
    winTrophies: 18,
    lossTrophies: 22,
  ),
];

int _nonNegative(int value) => value < 0 ? 0 : value;

int _clampArenaIndex(int value) {
  if (value < 0) return 0;
  if (value >= kArenaCatalog.length) return kArenaCatalog.length - 1;
  return value;
}

String formatTrophies(int value) {
  final normalized = _nonNegative(value);
  final text = normalized.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

int arenaIndexForTrophies(int trophies) {
  final normalized = _nonNegative(trophies);
  var result = 0;
  for (final arena in kArenaCatalog) {
    if (normalized < arena.minTrophies) break;
    result = arena.index;
  }
  return result;
}

/// The server keeps a reached arena as a floor-protected rank. Preserve that
/// state in the client while still repairing stale values from trophy count.
int arenaIndexForPlayer(int trophies, [int? storedArenaIndex]) {
  final normalizedTrophies = _nonNegative(trophies);
  final fromTrophies = arenaIndexForTrophies(normalizedTrophies);
  final stored = _clampArenaIndex(storedArenaIndex ?? fromTrophies);
  final storedIsConsistent =
      stored > fromTrophies &&
      normalizedTrophies >= kArenaCatalog[stored].minTrophies;
  return storedIsConsistent ? stored : fromTrophies;
}

ArenaDefinition arenaForIndex(int index) =>
    kArenaCatalog[_clampArenaIndex(index)];

double arenaProgress(int trophies, [int? arenaIndex]) {
  final arena = arenaForIndex(arenaIndexForPlayer(trophies, arenaIndex));
  final max = arena.maxTrophies;
  if (max == null) return 1;
  final within = _nonNegative(trophies) - arena.minTrophies;
  final value = within / arena.trophySpan;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

String arenaProgressLabel(int trophies, [int? arenaIndex]) {
  final arena = arenaForIndex(arenaIndexForPlayer(trophies, arenaIndex));
  final within = _nonNegative(trophies) - arena.minTrophies;
  final current = within < 0 ? 0 : within;
  final max = arena.maxTrophies;
  return max == null
      ? '${formatTrophies(current)} kupa'
      : '${formatTrophies(current)} / ${formatTrophies(arena.trophySpan)}';
}
