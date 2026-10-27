import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

String accountKey(String uid) =>
    'luno_account_v1_${base64Url.encode(utf8.encode(uid))}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'first association preserves legacy progress and a separate recovery copy',
    () async {
      final old =
          PlayerData.initial()
            ..gold = 9123
            ..bio = 'legacy';
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode(old.toJson()),
        'luno_username_chosen_v1': true,
        'luno_tutorial_completed_v1': true,
      });
      final store = GameStore.createForTesting();
      await store.bindAccount('A');
      expect(store.accountUid, 'A');
      expect(store.data.gold, 9123);
      expect(store.hasChosenUsername, isTrue);
      expect(store.hasCompletedTutorial, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final backup = jsonDecode(
        prefs.getString('luno_unowned_account_backup_v1')!,
      );
      expect(backup['gold'], 9123);
      expect(backup.containsKey('accountUid'), isFalse);
      expect(jsonDecode(prefs.getString('luno_player_v1')!)['accountUid'], 'A');
    },
  );

  test(
    'switching accounts isolates data and restores each account flags',
    () async {
      final store = GameStore.createForTesting();
      await store.bindAccount('A');
      store.data.gold = 9000;
      store.data.bio = 'A private bio';
      await store.chooseUsername('alpha');
      await store.completeTutorial();
      await store.bindAccount('B');
      expect(store.accountUid, 'B');
      expect(store.data.gold, PlayerData.initial().gold);
      expect(store.data.bio, isNot('A private bio'));
      expect(store.hasChosenUsername, isFalse);
      expect(store.hasCompletedTutorial, isFalse);
      store.data.gold = 200;
      await store.chooseUsername('beta');
      await store.setTutorialStep(4);
      await store.bindAccount('A');
      expect(store.data.gold, 9000);
      expect(store.data.bio, 'A private bio');
      expect(store.data.username, 'alpha');
      expect(store.hasCompletedTutorial, isTrue);
      await store.bindAccount('B');
      expect(store.data.gold, 200);
      expect(store.data.username, 'beta');
      expect(store.hasCompletedTutorial, isFalse);
      expect(store.tutorialStep, 4);
    },
  );

  test(
    'sign-out hides progress without deleting the prior account archive',
    () async {
      final store = GameStore.createForTesting();
      await store.bindAccount('A');
      store.data.gold = 5555;
      await store.bindAccount(null);
      expect(store.accountUid, isNull);
      expect(store.data.gold, PlayerData.initial().gold);
      await store.bindAccount('B');
      expect(store.data.gold, PlayerData.initial().gold);
      await store.bindAccount('A');
      expect(store.data.gold, 5555);
    },
  );

  test(
    'restart restores the active owner and ignores stale auxiliary flags',
    () async {
      final store = GameStore.createForTesting();
      await store.bindAccount('A');
      await store.chooseUsername('alpha');
      await store.completeTutorial();
      await store.save();
      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('luno_username_chosen_v1', false);
      await prefs.setBool('luno_tutorial_completed_v1', false);
      final fresh = GameStore.createForTesting();
      await fresh.load();
      expect(fresh.accountUid, 'A');
      expect(fresh.hasChosenUsername, isTrue);
      expect(fresh.hasCompletedTutorial, isTrue);
      await fresh.bindAccount('B');
      expect(fresh.hasChosenUsername, isFalse);
    },
  );

  test('same-account retry leaves current data intact', () async {
    final store = GameStore.createForTesting();
    await store.bindAccount('A');
    store.data.gold = 333;
    await store.bindAccount('A');
    expect(store.data.gold, 333);
  });

  test(
    'owned tutorial changes survive restart without a separate save call',
    () async {
      final store = GameStore.createForTesting();
      await store.bindAccount('A');
      await store.setTutorialStep(5);
      await store.flush();
      final restored = GameStore.createForTesting();
      await restored.load();
      expect(restored.tutorialStep, 5);
      await restored.completeTutorial();
      await restored.flush();
      final completed = GameStore.createForTesting();
      await completed.load();
      expect(completed.hasCompletedTutorial, isTrue);
      expect(completed.tutorialStep, 0);
    },
  );

  test(
    'queued switches preserve the latest pending save and final owner',
    () async {
      final store = GameStore.createForTesting();
      await store.bindAccount('A');
      store.data.gold = 4567;
      final save = store.save();
      final b = store.bindAccount('B');
      final a = store.bindAccount('A');
      await Future.wait([save, b, a, store.flush()]);
      expect(store.accountUid, 'A');
      expect(store.data.gold, 4567);
      final disk = jsonDecode(
        (await SharedPreferences.getInstance()).getString('luno_player_v1')!,
      );
      expect(disk['accountUid'], 'A');
      expect(disk['gold'], 4567);
    },
  );

  for (final invalid in [
    '{broken',
    jsonEncode({'accountUid': 'OTHER', 'gold': 999999}),
  ]) {
    test(
      'invalid or wrong-owner archive is never imported: $invalid',
      () async {
        final store = GameStore.createForTesting();
        await store.bindAccount('A');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(accountKey('B'), invalid);
        await store.bindAccount('B');
        expect(store.data.gold, PlayerData.initial().gold);
        expect(prefs.getString('${accountKey('B')}_recovery'), invalid);
      },
    );
  }

  test('invalid UID does not poison later account operations', () async {
    final store = GameStore.createForTesting();
    await expectLater(store.bindAccount('  '), throwsArgumentError);
    await store.bindAccount('A');
    expect(store.accountUid, 'A');
  });

  test(
    'native auth bootstrap switches store before exposing readiness',
    () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final observations = <String?>[];
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {
          observations.add(store.accountUid);
        },
        auth: auth,
        authChanges: events.stream,
        playerStore: store,
      );
      await service.start();
      expect(observations, ['first']);
      store.data.gold = 9876;
      auth.currentUser = TestUser('second');
      events.add(auth.currentUser);
      for (var i = 0; i < 20 && service.authTransitioning; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(service.ready, isTrue);
      expect(observations, ['first', 'second']);
      expect(store.accountUid, 'second');
      expect(store.data.gold, PlayerData.initial().gold);
      auth.currentUser = null;
      events.add(null);
      await store.flush();
      expect(store.accountUid, isNull);
      await store.bindAccount('first');
      expect(store.data.gold, 9876);
      service.dispose();
      await events.close();
    },
  );
}
