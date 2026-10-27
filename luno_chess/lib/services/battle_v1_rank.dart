import '../data/rank_catalog.dart';

/// Read-only projection of the authenticated Battle V1 rating namespace.
class BattleV1Rank {
  static const protocolVersion = 'LUNO_BATTLE_V1';
  final String uid;
  final int trophies;
  final int arenaIdx;

  const BattleV1Rank._(this.uid, this.trophies, this.arenaIdx);

  factory BattleV1Rank.fromJson(Object? value, {required String expectedUid}) {
    if (expectedUid.isEmpty ||
        value is! Map ||
        value['protocolVersion'] != protocolVersion ||
        value['uid'] != expectedUid) {
      throw const FormatException('Invalid Battle V1 rank owner or protocol');
    }
    final trophies = value['trophies'];
    final arena = value['arenaIdx'];
    if (trophies is! int ||
        trophies < 0 ||
        trophies > 1000000000 ||
        arena is! int ||
        arena < 0 ||
        arena >= kArenaCatalog.length ||
        arena != arenaIndexForTrophies(trophies)) {
      throw const FormatException('Invalid Battle V1 rank values');
    }
    return BattleV1Rank._(expectedUid, trophies, arena);
  }

  Map<String, dynamic> toJson() => {
    'protocolVersion': protocolVersion,
    'uid': uid,
    'trophies': trophies,
    'arenaIdx': arenaIdx,
  };
}
