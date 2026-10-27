import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/models/player_data.dart';

void main() {
  test(
    'bozuk yerel snapshot açılışı düşürmeden güvenli varsayılanlara döner',
    () {
      final data = PlayerData.fromJson({
        'username': 42,
        'gold': 'not-a-number',
        'ownedCards': [null, 'radar', 7],
        'cardLevel': {'radar': 'broken', 4: 3},
        'deck': [null, 'radar'],
        'passFreeClaimed': ['1', 2, null],
        'premium': 'yes',
      });

      expect(data.username, 'LunoPlayer');
      expect(data.gold, 1250);
      expect(data.ownedCards.length, 6);
      expect(data.cardLevel['radar'], 1);
      expect(data.deck.length, 6);
      expect(data.passFreeClaimed, {2});
      expect(data.premium, isFalse);
    },
  );

  test('kart aile varyantları tek sahiplik yuvasına indirgenir', () {
    final data = PlayerData.fromJson({
      'ownedCards': [
        'barbarian',
        'card_block',
        'poison_q',
        'angry_n',
        'glue',
        'freeze',
        'trap1',
        'trap2',
      ],
      'cardLevel': {'trap': 2},
      'deck': [
        'trap2',
        'barbarian',
        'card_block',
        'poison_q',
        'angry_n',
        'glue',
      ],
    });

    expect(data.ownedCards, contains('trap'));
    expect(data.ownedCards, isNot(contains('trap1')));
    expect(data.deck, contains('trap'));
    expect(ownedPhysicalCardCount(data.ownedCards, data.cardLevel), 8);
  });

  test(
    'emoji loadout yalnızca sahip olunan katalog ifadelerini ve dört yuvayı saklar',
    () {
      final snapshot =
          PlayerData.initial().toJson()
            ..['ownedEmojis'] = ['smile', 'heart', 'fire', 'star', 'crown']
            ..['emojiLoadout'] = [
              'heart',
              'heart',
              'locked',
              'fire',
              'star',
              'crown',
            ];

      final data = PlayerData.fromJson(snapshot);

      expect(data.emojiLoadout, ['heart', 'fire', 'star', 'crown']);
    },
  );
}
