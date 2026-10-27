import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _accountKey(String uid) =>
    'luno_account_v1_${base64Url.encode(utf8.encode(uid))}';

// Valid JSON syntax; the native Dart decoder represents 1e999 as infinity.
const _accountBArchive = r'''
{
  "schemaVersion": 2,
  "accountUid": "B",
  "username": "account_b",
  "usernameChosen": true,
  "tutorialCompleted": false,
  "tutorialStep": 1e999,
  "bio": "B-only biography",
  "gold": 8765,
  "gems": 321,
  "ownedCards": [
    "barbarian", "card_block", "poison_q", "angry_n", "glue", "freeze", "trap"
  ],
  "cardLevel": {"trap": 2},
  "deck": ["trap", "barbarian", "card_block", "poison_q", "angry_n", "glue"],
  "passFreeClaimed": [1],
  "pendingChests": ["rare", "rare"]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'malformed account restore cannot transplant B economy into A archive',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(() async {
        await store.flush();
        store.dispose();
      });
      await store.bindAccount('A');
      store.data.username = 'account_a';
      store.hasChosenUsername = true;
      store.data.gold = 4321;
      store.data.gems = 87;
      store.data.bio = 'A-only biography';
      await store.save();
      final confirmedA = store.data.toJson();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountKey('B'), _accountBArchive);

      Object? restoreError;
      try {
        await store.bindAccount('B');
      } catch (error) {
        restoreError = error;
      }
      final ownerAfterAttempt = store.accountUid;
      final dataAfterAttempt = store.data.toJson();

      // A rejected restore must not make the next ordinary switch archive
      // B's already-parsed data under the still-current owner A.
      await store.bindAccount('C');
      final archivedA = jsonDecode(prefs.getString(_accountKey('A'))!) as Map;
      await store.bindAccount('A');

      expect(
        archivedA['gold'],
        confirmedA['gold'],
        reason: 'A archive must never contain B gold after a failed restore',
      );
      expect(store.data.toJson(), confirmedA);
      if (restoreError != null) {
        expect(ownerAfterAttempt, 'A');
        expect(dataAfterAttempt, confirmedA);
      } else {
        expect(ownerAfterAttempt, 'B');
        expect(dataAfterAttempt['gold'], 8765);
        expect(dataAfterAttempt['ownedCards'], contains('trap'));
      }
    },
  );

  test(
    'overflow tutorial step on cold load preserves healthy owned economy',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': _accountBArchive,
        'luno_player_schema_v2': 2,
      });
      final store = GameStore.createForTesting();
      addTearDown(() async {
        await store.flush();
        store.dispose();
      });

      await store.load();

      expect(store.loaded, isTrue);
      expect(store.accountUid, 'B');
      expect(store.data.username, 'account_b');
      expect(store.data.bio, 'B-only biography');
      expect(store.data.gold, 8765);
      expect(store.data.gems, 321);
      expect(store.data.ownedCards, contains('trap'));
      expect(store.data.cardLevel['trap'], 2);
      expect(store.data.deck.first, 'trap');
      expect(store.data.passFreeClaimed, {1});
      expect(store.data.pendingChests, ['rare', 'rare']);
      expect(store.hasChosenUsername, isTrue);
      expect(store.tutorialStep, 0);

      await store.save();
      final restarted = GameStore.createForTesting();
      addTearDown(() async {
        await restarted.flush();
        restarted.dispose();
      });
      await restarted.load();
      expect(restarted.accountUid, 'B');
      expect(restarted.data.toJson(), store.data.toJson());
      expect(restarted.tutorialStep, 0);
    },
  );

  test(
    'cold load and account restore share finite tutorial step parsing',
    () async {
      const cases = <(String, int)>[
        ('-1e999', 0),
        ('1e100', GameStore.tutorialStepCount - 1),
        ('3.9', 3),
        ('-2', 0),
      ];
      for (final (encodedStep, expectedStep) in cases) {
        final raw = _accountBArchive.replaceFirst('1e999', encodedStep);
        SharedPreferences.setMockInitialValues({
          'luno_player_v1': raw,
          'luno_player_schema_v2': 2,
        });
        final cold = GameStore.createForTesting();
        final switched = GameStore.createForTesting();
        addTearDown(() async {
          await cold.flush();
          await switched.flush();
          cold.dispose();
          switched.dispose();
        });

        await cold.load();
        expect(cold.accountUid, 'B', reason: encodedStep);
        expect(cold.data.gold, 8765, reason: encodedStep);
        expect(cold.tutorialStep, expectedStep, reason: encodedStep);
        await cold.flush();

        await switched.bindAccount('A');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_accountKey('B'), raw);
        await switched.bindAccount('B');
        expect(switched.accountUid, 'B', reason: encodedStep);
        expect(switched.tutorialStep, expectedStep, reason: encodedStep);
        expect(switched.data.toJson(), cold.data.toJson(), reason: encodedStep);
      }
    },
  );
}
