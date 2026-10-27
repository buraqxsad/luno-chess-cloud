import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/models/player_data.dart';

void main() {
  for (final invalid in [
    double.nan,
    double.infinity,
    double.negativeInfinity,
  ]) {
    test(
      'non-finite balances and counters preserve unrelated data: $invalid',
      () {
        final data = PlayerData.fromJson({
          ...PlayerData.initial().toJson(),
          'username': 'keep_player',
          'gold': 7777,
          'gems': invalid,
          'trophies': invalid,
          'arenaIdx': invalid,
          'lvl': invalid,
          'xp': invalid,
          'wins': invalid,
          'losses': invalid,
          'draws': invalid,
          'gamesPlayed': invalid,
          'streak': invalid,
          'bestStreak': invalid,
          'cardsPlayed': invalid,
          'chestsOpened': invalid,
          'dailyStreak': invalid,
          'lastDailyDay': invalid,
          'premiumUntil': invalid,
          'passXp': invalid,
        });

        expect(data.username, 'keep_player');
        expect(data.gold, 7777);
        expect(data.gems, 42);
        expect(data.lvl, 1);
        expect(data.trophies, 0);
        expect(data.dailyStreak, 0);
        expect(data.lastDailyDay, 0);
        expect(data.premiumUntil, 0);
        expect(data.passXp, 0);
        expect(data.wins + data.losses + data.draws, 0);
      },
    );

    test(
      'non-finite card levels and claims cannot discard a profile: $invalid',
      () {
        final data = PlayerData.fromJson({
          ...PlayerData.initial().toJson(),
          'gold': 7777,
          'ownedCards': [...kStarterOwned, 'trap'],
          'cardLevel': {'trap': invalid, 'radar': 2},
          'passFreeClaimed': [invalid, 1, 1.5, 0, 31],
          'passPremClaimed': [2, invalid, 2.5],
        });

        expect(data.gold, 7777);
        expect(data.ownedCards, contains('trap'));
        expect(data.cardLevel['radar'], 2);
        expect(data.cardLevel['trap'] ?? 1, 1);
        expect(data.passFreeClaimed, {1});
        expect(data.passPremClaimed, {2});
        expect(PlayerData.fromJson(data.toJson()).gold, 7777);
      },
    );
  }

  test(
    'normal economy and duplicate chest units survive a cache round trip',
    () {
      final source =
          PlayerData.initial()
            ..username = 'luno_player'
            ..gold = 9876
            ..gems = 543
            ..passXp = 1262
            ..passRewardVersion = 2
            ..passFreeClaimed = {1, 4}
            ..passPremClaimed = {2}
            ..ownedCards.add('trap')
            ..cardLevel['trap'] = 3
            ..ownedPieceSets.add('ottoman')
            ..pieceSet = 'ottoman'
            ..ownedSkins.add('jade')
            ..activeSkin = 'jade'
            ..skinPieces['ruby'] = 5
            ..ownedEmojis.add('heart')
            ..emojiLoadout = ['heart', 'smile']
            ..pendingChests = ['rare', 'rare', 'royal'];
      final copy = PlayerData.fromJson(source.toJson());

      expect(copy.toJson(), source.toJson());
    },
  );
}
