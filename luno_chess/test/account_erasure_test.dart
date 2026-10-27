import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_store_isolation_test.dart' show accountKey;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'active erasure clears profile, archive, recovery and onboarding',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('A');
      store.data.bio = 'private biography';
      store.data.gold = 9999;
      await store.chooseUsername('private_user');
      await store.completeTutorial();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(accountKey('A'), jsonEncode(store.data.toJson()));
      await prefs.setString(
        '${accountKey('A')}_recovery',
        'damaged private data',
      );
      await store.eraseLocalAccount('A');
      expect(store.accountUid, isNull);
      expect(store.data.bio, PlayerData.initial().bio);
      expect(store.data.gold, PlayerData.initial().gold);
      expect(store.hasChosenUsername, isFalse);
      expect(store.hasCompletedTutorial, isFalse);
      expect(prefs.getString(accountKey('A')), isNull);
      expect(prefs.getString('${accountKey('A')}_recovery'), isNull);
      expect(prefs.getString('luno_unowned_account_backup_v1'), isNull);
      expect(prefs.getString('luno_unowned_account_backup_owner_v1'), isNull);
      expect(prefs.getString('luno_player_v1'), isNot(contains('private')));
      expect(prefs.getBool('luno_username_chosen_v1'), isNull);
      await store.bindAccount(null);
      expect(prefs.getString(accountKey('A')), isNull);
      await expectLater(
        store.bindAccount('A'),
        throwsA(isA<LocalAccountErasedException>()),
      );
    },
  );

  test(
    'inactive account erasure preserves the active account and its backup',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('B');
      store.data.bio = 'B biography';
      store.data.gold = 2345;
      await store.chooseUsername('player_b');
      await store.bindAccount('A');
      store.data.bio = 'A biography';
      await store.save();
      await store.bindAccount('B');
      final before = jsonEncode(store.data.toJson());
      final prefs = await SharedPreferences.getInstance();
      final beforeDisk = prefs.getString('luno_player_v1');
      final bArchive = prefs.getString(accountKey('B'));
      await store.eraseLocalAccount('A');
      expect(jsonEncode(store.data.toJson()), before);
      expect(prefs.getString('luno_player_v1'), beforeDisk);
      expect(prefs.getString(accountKey('B')), bArchive);
      expect(prefs.getString('luno_unowned_account_backup_v1'), isNotNull);
      expect(prefs.getString(accountKey('A')), isNull);
    },
  );

  test(
    'owner-tagged generic recovery is erased but unknown recovery is preserved',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_corrupt_backup_v2': jsonEncode({
          'accountUid': 'A',
          'bio': 'secret',
        }),
        'luno_unowned_account_backup_v1': 'unknown damaged data',
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('B');
      await store.eraseLocalAccount('A');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('luno_player_corrupt_backup_v2'), isNull);
      expect(
        prefs.getString('luno_unowned_account_backup_v1'),
        'unknown damaged data',
      );
    },
  );

  test('pending writes cannot recreate erased personal data', () async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.bindAccount('A');
    store.data.bio = 'pending private biography';
    final pending = store.save();
    final erased = store.eraseLocalAccount('A');
    final signout = store.bindAccount(null);
    await Future.wait([pending, erased, signout]);
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('luno_player_v1'),
      isNot(contains('pending private')),
    );
    expect(prefs.getString(accountKey('A')), isNull);
  });

  test(
    'restart hides an active snapshot left before erasure completed',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'accountUid': 'A',
          'bio': 'old secret',
          'gold': 9999,
          'usernameChosen': true,
          'tutorialCompleted': true,
        }),
        '${accountKey('A')}_erased': true,
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.accountUid, isNull);
      expect(store.data.bio, PlayerData.initial().bio);
      expect(store.hasChosenUsername, isFalse);
      expect(store.hasCompletedTutorial, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('luno_player_v1'), isNot(contains('old secret')));
      await expectLater(
        store.bindAccount('A'),
        throwsA(isA<LocalAccountErasedException>()),
      );
    },
  );

  test(
    'erasure is repeatable and invalid UID does not poison account queue',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('A');
      await expectLater(store.eraseLocalAccount(''), throwsArgumentError);
      await store.eraseLocalAccount('A');
      await store.eraseLocalAccount('A');
      await store.bindAccount('B');
      expect(store.accountUid, 'B');
    },
  );

  for (final code in [
    'account-deleted',
    'account-deletion-in-progress',
    'network-unavailable',
  ]) {
    test('API $code erases only confirmed deleted account', () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: store,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': code}),
            code == 'account-deleted' ? 403 : 409,
          ),
        ),
        appCheck: () async => 'check',
      );
      addTearDown(() async {
        service.dispose();
        await store.flush();
        store.dispose();
      });
      await service.start();
      store.data.bio = 'private biography';
      await store.save();
      await expectLater(
        service.api('/getPlayerState', {}),
        throwsA(isA<LunoApiException>()),
      );
      if (code == 'account-deleted') {
        expect(store.accountUid, isNull);
        expect(store.data.bio, PlayerData.initial().bio);
        expect(service.accountFailure?.code, code);
        await service.retry();
        expect(service.accountFailure?.code, code);
        expect(service.ready, isFalse);
      } else {
        expect(store.accountUid, 'first');
        expect(store.data.bio, 'private biography');
      }
    });
  }
}
