import 'public_player_profile.dart' show isPublicPlayerUidValid;
import 'ugc_text_safety.dart';

void validateDirectMessageParticipants(String viewerUid, String targetUid) {
  if (!isPublicPlayerUidValid(viewerUid) ||
      !isPublicPlayerUidValid(targetUid) ||
      viewerUid == targetUid) {
    throw const FormatException('Invalid direct-message participants');
  }
}

List<Map<String, dynamic>> parseDirectMessageRows(
  Object? value, {
  required String viewerUid,
  required String targetUid,
}) {
  validateDirectMessageParticipants(viewerUid, targetUid);
  if (value == null) return [];
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid direct-message snapshot');
  }
  final rows = <Map<String, dynamic>>[];
  for (final entry in value.entries) {
    final id = entry.key as String;
    final message = entry.value;
    if (!isPublicPlayerUidValid(id) || message is! Map) continue;
    final from = message['from'];
    final text = message['text'];
    if ((from != viewerUid && from != targetUid) || text is! String) continue;
    if (normalizeUgcText(text, maxLength: directMessageMaxLength) == null) {
      continue;
    }
    final trimmed = text.trim();
    if (trimmed.length > directMessageMaxLength) continue;
    final rawTime = message['ts'];
    final numeric =
        rawTime is num
            ? rawTime
            : rawTime is String
            ? num.tryParse(rawTime)
            : null;
    final timestamp =
        numeric != null &&
                numeric.isFinite &&
                numeric >= 0 &&
                numeric <= 9007199254740991
            ? numeric.toInt()
            : 0;
    rows.add({'messageId': id, 'from': from, 'text': trimmed, 'ts': timestamp});
  }
  rows.sort((a, b) {
    final time = (a['ts'] as int).compareTo(b['ts'] as int);
    return time != 0
        ? time
        : (a['messageId'] as String).compareTo(b['messageId'] as String);
  });
  return rows;
}
