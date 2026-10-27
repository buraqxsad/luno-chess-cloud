import '../data/username.dart';
import 'ugc_text_safety.dart';
import 'battle_v1_rank.dart';

bool isPublicPlayerUidValid(String uid) =>
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(uid);

Map<String, dynamic>? parsePublicPlayerProfile(String uid, Object? value) {
  if (!isPublicPlayerUidValid(uid)) {
    throw const FormatException('Invalid public player UID');
  }
  if (value == null) return null;
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid public profile');
  }
  final profile = Map<String, dynamic>.from(value);
  final username = usernameFromMap(profile, fallback: '');
  if (username.isEmpty) throw const FormatException('Missing public username');
  int number(Object? value) {
    if (value is num && !value.isFinite) return 0;
    final result = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return result < 0 ? 0 : result;
  }

  String text(String field, String fallback) =>
      profile[field] is String ? (profile[field] as String).trim() : fallback;
  final country = text('country', 'TR').toUpperCase();
  final wins = number(profile['wins']);
  final games = number(profile['gamesPlayed']);
  final premium = profile['isPremium'] == true;
  final battleRank =
      profile.containsKey('battleV1Rank')
          ? BattleV1Rank.fromJson(profile['battleV1Rank'], expectedUid: uid)
          : null;
  return {
    'uid': uid,
    'name': username,
    'username': username,
    'trophies': battleRank?.trophies ?? number(profile['trophies']),
    if (battleRank != null) 'battleV1Rank': battleRank.toJson(),
    'country': RegExp(r'^[A-Z]{2}$').hasMatch(country) ? country : 'TR',
    'avatarEmoji': text('avatarEmoji', 'av_pawn'),
    'bio': safePublicBio(profile['bio']),
    'wins': wins,
    'gamesPlayed': games < wins ? wins : games,
    'isPremium': premium,
    'premium': premium,
  };
}
