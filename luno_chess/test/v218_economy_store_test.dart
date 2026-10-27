import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/data/pass.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = GameStore.createForTesting();
    await store.load();
  });
  tearDown(() async {
    await store.flush();
    store.dispose();
  });

  for (final invalid in [
    double.nan,
    double.infinity,
    double.negativeInfinity,
  ]) {
    test(
      'malformed numeric state keeps confirmed values and applies healthy fields: $invalid',
      () {
        store.data.gems = 123;
        store.data.passXp = 3 * kPassXpPerLevel + 17;
        store.data.cardLevel['trap'] = 2;
        store.data.lastDailyDay = 12345;
        store.applyServerState({
          'gold': 7777,
          'gems': invalid,
          'trophies': invalid,
          'arenaIdx': invalid,
          'lvl': invalid,
          'xp': invalid,
          'stats': {'wins': invalid, 'chestsOpened': invalid},
          'cardLevel': {'trap': invalid, 'radar': 3},
          'passState': {'level': invalid, 'xp': invalid},
          'economy': {
            'daily': {'lastClaimDay': invalid, 'streak': invalid},
          },
        });

        expect(store.data.gold, 7777);
        expect(store.data.gems, 123);
        expect(store.data.passXp, 767);
        expect(store.data.cardLevel['trap'], 2);
        expect(store.data.cardLevel['radar'], 3);
        expect(store.data.lastDailyDay, 12345);
        expect(store.data.lvl, 1);
        expect(store.data.arenaIdx, 0);
      },
    );
  }

  test(
    'server level and arena are bounded at their structural minima and maxima',
    () {
      store.applyServerState({'lvl': 0, 'arenaIdx': 1000000});
      expect(store.data.lvl, 1);
      expect(store.data.arenaIdx, 8);
    },
  );

  test(
    'Pass array claims clear stale cache and disable only confirmed tiers',
    () {
      store.data.passFreeClaimed = {30};
      store.data.passPremClaimed = {29};
      store.applyServerState({
        'passState': {
          'level': 4,
          'xp': 17,
          'premium': true,
          'claimed': {
            'free': [null, 1000, 2000, null, false],
            'premium': [null, null, true],
          },
        },
      });
      expect(store.data.passFreeClaimed, {1, 2});
      expect(store.data.passPremClaimed, {2});
      expect(store.canClaimPassFree(1), isFalse);
      expect(store.canClaimPassFree(4), isTrue);
      expect(store.canClaimPassPrem(2), isFalse);
      expect(store.claimablePassRewardCount, 5);
      store.applyServerState({
        'passState': {
          'claimed': {'free': [], 'premium': []},
        },
      });
      expect(store.data.passFreeClaimed, isEmpty);
      expect(store.data.passPremClaimed, isEmpty);
    },
  );

  test('inventory-only ownership changes prune unowned quick emotes', () {
    store.data.ownedEmojis.add('heart');
    store.data.emojiLoadout = ['heart', 'smile'];
    store.applyServerState({
      'inventory': {
        'ownedEmojis': ['smile'],
      },
    });
    expect(store.data.emojiLoadout, ['smile']);
  });

  test(
    'ownership changes repair a deck even when no deck field is returned',
    () {
      store.data.ownedCards.add('trap');
      store.data.deck = ['trap', ...kStarterOwned.take(5)];
      store.applyServerState({
        'unlockedCards': {for (final key in kStarterOwned) key: true},
      });
      expect(store.data.ownedCards, kStarterOwned.toSet());
      expect(store.data.deck.length, 6);
      expect(store.data.deck, isNot(contains('trap')));
      expect(store.data.deck.every(store.data.ownedCards.contains), isTrue);
    },
  );

  test(
    'invalid six-card server deck preserves a confirmed usable selection',
    () {
      store.data.ownedCards.add('trap');
      final confirmed = ['trap', ...kStarterOwned.take(5)];
      store.data.deck = List.of(confirmed);
      store.applyServerState({'deck': List.filled(6, 'unknown')});
      expect(store.data.deck, confirmed);
      store.applyServerState({'deck': confirmed.reversed.toList()});
      expect(store.data.deck, confirmed.reversed.toList());
    },
  );

  test('duplicate earned chest units are not collapsed by reconciliation', () {
    store.applyServerState({
      'inventory': {
        'pendingChests': ['rare', 'rare'],
      },
    });
    expect(store.data.pendingChests, ['rare', 'rare']);
  });

  final today = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
  for (final daysAgo in [0, 1, 2]) {
    test('daily preview and delivery agree at a $daysAgo-day gap', () {
      store.data.lastDailyDay = today - daysAgo;
      store.data.dailyStreak = 6;
      if (daysAgo == 0) {
        expect(store.canClaimDaily(), isFalse);
        expect(store.claimDaily(), isNull);
        return;
      }
      final expected = daysAgo == 1 ? 1500 : 200;
      final gold = store.data.gold;
      expect(store.dailyPreview(), expected);
      expect(store.claimDaily(), expected);
      expect(store.data.gold, gold + expected);
      expect(store.data.dailyStreak, daysAgo == 1 ? 7 : 1);
      expect(store.claimDaily(), isNull);
    });
  }

  test('a missing daily claim day cannot retain a stale streak payout', () {
    store.data.dailyStreak = 6;
    store.data.lastDailyDay = 0;
    expect(store.dailyPreview(), 200);
    expect(store.claimDaily(), 200);
    expect(store.data.dailyStreak, 1);
  });
}
