import '../data/username.dart';

List<Map<String, dynamic>> parseLeaderboardResult(
  Map<String, dynamic> response,
  String mode,
) {
  const fields = {
    'trophies': 'trophies',
    'collection': 'collectionScore',
    'season': 'seasonScore',
  };
  final field = fields[mode];
  final raw = response['results'];
  if (field == null ||
      response['ok'] != true ||
      response['mode'] != mode ||
      raw is! List) {
    throw const FormatException('Unconfirmed leaderboard');
  }
  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final entry in raw) {
    if (entry is! Map) throw const FormatException('Invalid leaderboard row');
    final row = Map<String, dynamic>.from(entry);
    final uid = row['uid'];
    final score = row[field];
    if (uid is! String ||
        uid.trim().isEmpty ||
        score is! num ||
        !score.isFinite ||
        score < 0 ||
        score != score.truncateToDouble()) {
      throw const FormatException('Invalid leaderboard identity or score');
    }
    if (!seen.add(uid.trim())) continue;
    row['uid'] = uid.trim();
    row[field] = score.toInt();
    rows.add(row);
  }
  rows.sort((a, b) {
    final score = (b[field] as int).compareTo(a[field] as int);
    if (score != 0) return score;
    final name = usernameFromMap(a).compareTo(usernameFromMap(b));
    return name != 0
        ? name
        : (a['uid'] as String).compareTo(b['uid'] as String);
  });
  return rows;
}
