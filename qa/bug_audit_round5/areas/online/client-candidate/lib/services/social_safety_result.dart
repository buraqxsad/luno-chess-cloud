import 'public_player_profile.dart';
import 'ugc_text_safety.dart';

enum SocialReportReason {
  harassment('harassment', 'Harassment', 'Taciz'),
  threats('threats', 'Threats', 'Tehdit'),
  sexualContent('sexual_content', 'Sexual content', 'Cinsel içerik'),
  hate('hate', 'Hate speech', 'Nefret söylemi'),
  spam('spam', 'Spam', 'İstenmeyen mesaj'),
  scam('scam', 'Scam', 'Dolandırıcılık'),
  cheating('cheating', 'Cheating', 'Hile'),
  abuse('abuse', 'Abusive content', 'Kötüye kullanım'),
  other('other', 'Other', 'Diğer');

  const SocialReportReason(this.id, this.english, this.turkish);
  final String id;
  final String english;
  final String turkish;
  String label(bool english) => english ? this.english : turkish;
}

void validateSocialBlockResult(
  Map<String, dynamic> result, {
  required String targetUid,
  required bool blocked,
}) {
  if (result['ok'] != true ||
      result['targetUid'] != targetUid ||
      result['blocked'] != blocked) {
    throw const FormatException('Unconfirmed block action');
  }
}

void validateSocialReportResult(Map<String, dynamic> result) {
  final id = result['reportId'];
  if (result['ok'] != true ||
      result['reported'] != true ||
      id is! String ||
      !RegExp(r'^rp_[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
    throw const FormatException('Unconfirmed moderation report');
  }
}

class BlockedPlayer {
  const BlockedPlayer({required this.uid, required this.name});
  final String uid;
  final String name;
}

List<BlockedPlayer> parseBlockedPlayers(
  Map<String, dynamic> result, {
  required String viewerUid,
}) {
  final rows = result['results'];
  if (result['ok'] != true || rows is! List || rows.length > 100) {
    throw const FormatException('Invalid blocked player list');
  }
  final seen = <String>{};
  final players = <BlockedPlayer>[];
  for (final row in rows) {
    if (row is! Map || row.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid blocked player');
    }
    final uid = row['uid'];
    final username = row['username'];
    final name =
        username is String && username.trim().isNotEmpty
            ? username
            : row['name'];
    if (uid is! String ||
        !isPublicPlayerUidValid(uid) ||
        uid == viewerUid ||
        !seen.add(uid) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 64 ||
        normalizeUgcText(name, maxLength: 64) == null ||
        RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(name)) {
      throw const FormatException('Invalid blocked player identity');
    }
    players.add(BlockedPlayer(uid: uid, name: name.trim()));
  }
  return List.unmodifiable(players);
}
