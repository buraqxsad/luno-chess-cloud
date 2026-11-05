List<Map<String, dynamic>> parsePlayerSearchResult(
  Map<String, dynamic> response, {
  required String? ownUid,
}) {
  final raw = response['results'];
  if (response['ok'] == false || raw is! List) {
    throw const FormatException('Invalid player search response');
  }
  const relationships = {'none', 'friends', 'incoming', 'outgoing'};
  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final entry in raw) {
    if (entry is! Map || entry.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid player search row');
    }
    final row = Map<String, dynamic>.from(entry);
    final uid = row['uid'];
    if (uid is! String ||
        uid.trim().isEmpty ||
        !relationships.contains(row['relationship'])) {
      throw const FormatException(
        'Invalid player search identity or relationship',
      );
    }
    final normalizedUid = uid.trim();
    if (normalizedUid == ownUid || !seen.add(normalizedUid)) continue;
    row['uid'] = normalizedUid;
    rows.add(row);
  }
  return rows;
}
