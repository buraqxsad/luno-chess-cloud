import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass_purchase.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing preference test transport; no new runtime dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _playerKey = 'luno_player_v1';
const _corruptBackupKey = 'luno_player_corrupt_backup_v2';
const _legacyBackupKey = 'luno_unowned_account_backup_v1';
const _legacyOwnerKey = 'luno_unowned_account_backup_owner_v1';

String _accountKey(String uid) =>
    'luno_account_v1_${base64Url.encode(utf8.encode(uid))}';
String _diskKey(String key) => 'flutter.$key';
String _tombstoneKey(String uid) => '${_accountKey(uid)}_erased';

class _BoundaryDisk extends InMemorySharedPreferencesStore {
  _BoundaryDisk() : super.empty();

  String? failingWrite, failingRemoval;
  bool throwOnFailure = false;
  String? gatedWrite, gatedRemoval, gateAfterWrite;
  Completer<void>? entered, gate;
  final writes = <String>[];
  final removals = <String>[];

  Future<void> _waitAtGate() async {
    final currentGate = gate!;
    gate = null;
    entered!.complete();
    await currentGate.future;
  }

  bool _reject() {
    if (throwOnFailure) throw StateError('Disk unavailable');
    return false;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    if (key == gatedWrite &&
        gate != null &&
        (gateAfterWrite == null || writes.contains(gateAfterWrite))) {
      await _waitAtGate();
    }
    if (key == failingWrite) return _reject();
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    removals.add(key);
    if (key == gatedRemoval && gate != null) await _waitAtGate();
    if (key == failingRemoval) return _reject();
    return super.remove(key);
  }

  Future<Map<String, dynamic>> player() async {
    final values = await getAll();
    return Map<String, dynamic>.from(
      jsonDecode(values[_diskKey(_playerKey)]! as String) as Map,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _BoundaryDisk disk;
  late GameStore store;

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    disk = _BoundaryDisk();
    SharedPreferencesStorePlatform.instance = disk;
    store = GameStore.createForTesting();
    await store.bindAccount('A');
  });

  tearDown(() {
    store.dispose();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  Future<void> seedPrivateAccount() async {
    store.data.bio = 'A private biography';
    store.hasChosenUsername = true;
    store.hasCompletedTutorial = true;
    store.tutorialStep = 6;
    await store.save();
    final prefs = await SharedPreferences.getInstance();
    final privateSnapshot = jsonEncode({
      ...store.data.toJson(),
      'accountUid': 'A',
    });
    await prefs.setString(_accountKey('A'), privateSnapshot);
    await prefs.setString('${_accountKey('A')}_recovery', 'A private recovery');
    await prefs.setString('${_accountKey('A')}_google_link', 'A-link');
    await prefs.setString(
      '${_accountKey('A')}_pending_permanent_purchases',
      '{"item":"A-request"}',
    );
    await prefs.setString(
      '${_accountKey('A')}_pending_pass_premium_purchase',
      'A-pass-request',
    );
    for (final kind in ['common', 'rare', 'legendary', 'royal']) {
      for (final origin in ['pass', 'shop']) {
        await prefs.setString(
          '${_accountKey('A')}_pending_${origin}_chest_$kind',
          'A-$origin-$kind',
        );
      }
    }
    await prefs.setString(_corruptBackupKey, privateSnapshot);
    await prefs.setString(_legacyBackupKey, privateSnapshot);
    await prefs.setString(_legacyOwnerKey, 'A');
  }

  Future<void> expectPrivateAccountCleared() async {
    final values = await disk.getAll();
    expect(values[_diskKey(_tombstoneKey('A'))], true);
    expect(values[_diskKey(_accountKey('A'))], isNull);
    for (final key in values.keys) {
      if (key.startsWith(_diskKey(_accountKey('A')))) {
        expect(key, _diskKey(_tombstoneKey('A')));
      }
    }
    expect(values[_diskKey(_corruptBackupKey)], isNull);
    expect(values[_diskKey(_legacyBackupKey)], isNull);
    expect(values[_diskKey(_legacyOwnerKey)], isNull);
    expect((await disk.player())['bio'], isNot('A private biography'));
  }

  for (final throws in [false, true]) {
    test('failed tombstone drops owner, throws=$throws', () async {
      await seedPrivateAccount();
      final revision = store.accountBindingRevision;
      final epoch = store.serverStateEpoch;
      var departures = 0;
      store.addListener(() {
        if (store.accountUid == null) departures++;
      });
      disk
        ..failingWrite = _diskKey(_tombstoneKey('A'))
        ..throwOnFailure = throws;

      await expectLater(store.eraseLocalAccount('A'), throwsStateError);

      expect(store.accountUid, isNull);
      expect(store.accountBindingRevision, greaterThan(revision));
      expect(store.serverStateEpoch, greaterThan(epoch));
      expect(store.data.bio, PlayerData.initial().bio);
      expect(store.hasChosenUsername, isFalse);
      expect(store.hasCompletedTutorial, isFalse);
      expect(departures, 1);
      expect((await disk.getAll())[_diskKey(_tombstoneKey('A'))], isNull);

      // Use backend contents, not the failed set's optimistic cache.
      await (await SharedPreferences.getInstance()).reload();
      await expectLater(
        store.bindAccount('A'),
        throwsA(isA<LocalAccountErasedException>()),
      );
      expect(departures, 1);

      disk.failingWrite = null;
      await store.flush();
      await expectPrivateAccountCleared();
      SharedPreferences.resetStatic();
      final restarted = GameStore.createForTesting();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.accountUid, isNull);
      await expectLater(
        restarted.bindAccount('A'),
        throwsA(isA<LocalAccountErasedException>()),
      );
    });

    test('flush retries archive cleanup once, throws=$throws', () async {
      await seedPrivateAccount();
      disk
        ..failingRemoval = _diskKey(_accountKey('A'))
        ..throwOnFailure = throws;
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      expect((await disk.getAll())[_diskKey(_accountKey('A'))], isNotNull);
      final key = _diskKey(_accountKey('A'));
      final attempts = disk.removals.where((removed) => removed == key).length;

      await store.flush().timeout(const Duration(seconds: 1));
      expect(
        disk.removals.where((removed) => removed == key).length,
        attempts + 1,
      );
      disk.failingRemoval = null;
      await store.flush();
      await expectPrivateAccountCleared();
      final repaired = await disk.player();
      expect(repaired['username'], PlayerData.fromJson(repaired).username);
      final cleanWrites = disk.writes.length;
      final cleanRemovals = disk.removals.length;
      await store.flush();
      expect(disk.writes.length, cleanWrites);
      expect(disk.removals.length, cleanRemovals);
    });

    for (final key in [_corruptBackupKey, _legacyBackupKey]) {
      test('explicit retry retains hidden $key, throws=$throws', () async {
        await seedPrivateAccount();
        final prefs = await SharedPreferences.getInstance();
        // The JSON owner is sufficient; there is no separate ownership hint.
        await prefs.remove(_legacyOwnerKey);
        disk
          ..failingRemoval = _diskKey(key)
          ..throwOnFailure = throws;
        await expectLater(store.eraseLocalAccount('A'), throwsStateError);
        expect(prefs.getString(key), isNull);
        expect((await disk.getAll())[_diskKey(key)], isNotNull);

        disk.failingRemoval = null;
        await store.eraseLocalAccount('A');

        await expectPrivateAccountCleared();
      });
    }

    test('cleanup after A to B preserves B metadata, throws=$throws', () async {
      await seedPrivateAccount();
      disk
        ..failingRemoval = _diskKey(_accountKey('A'))
        ..throwOnFailure = throws;
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      await store.bindAccount('B');
      store.data.bio = 'B private biography';
      store.hasChosenUsername = true;
      store.hasCompletedTutorial = true;
      store.tutorialStep = 7;
      await store.save();
      final before = await disk.getAll();
      final removals = disk.removals.length;

      disk.failingRemoval = null;
      await store.flush();

      await expectPrivateAccountCleared();
      final after = await disk.getAll();
      expect(store.accountUid, 'B');
      expect(store.data.bio, 'B private biography');
      expect(after[_diskKey(_playerKey)], before[_diskKey(_playerKey)]);
      for (final key in [
        'luno_username_chosen_v1',
        'luno_tutorial_completed_v1',
        'luno_tutorial_step_v1',
      ]) {
        expect(after[_diskKey(key)], before[_diskKey(key)]);
        expect(disk.removals.skip(removals), isNot(contains(_diskKey(key))));
      }
      await store.bindAccount('C');
      await store.bindAccount('B');
      expect(store.data.bio, 'B private biography');
      expect(store.hasChosenUsername, isTrue);
      expect(store.hasCompletedTutorial, isTrue);
      expect(store.tutorialStep, 7);
    });

    test('inactive erasure failure preserves B, throws=$throws', () async {
      await seedPrivateAccount();
      await store.bindAccount('B');
      store.data.bio = 'B remains active';
      await store.save();
      final before = await disk.getAll();
      final revision = store.accountBindingRevision;
      disk
        ..failingWrite = _diskKey(_tombstoneKey('A'))
        ..throwOnFailure = throws;
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      expect(store.accountUid, 'B');
      expect(store.accountBindingRevision, revision);
      expect(store.data.bio, 'B remains active');

      disk.failingWrite = null;
      await store.flush();

      await expectPrivateAccountCleared();
      expect(
        (await disk.getAll())[_diskKey(_playerKey)],
        before[_diskKey(_playerKey)],
      );
    });

    test('tombstone retry is bounded, throws=$throws', () async {
      disk
        ..failingWrite = _diskKey(_tombstoneKey('A'))
        ..throwOnFailure = throws;
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      final key = _diskKey(_tombstoneKey('A'));
      for (var i = 0; i < 2; i++) {
        final attempts = disk.writes.where((write) => write == key).length;
        await store.flush().timeout(const Duration(seconds: 1));
        expect(disk.writes.where((write) => write == key).length, attempts + 1);
      }
      final idleWrites = disk.writes.length;
      await Future<void>.delayed(Duration.zero);
      expect(disk.writes.length, idleWrites);
      disk.failingWrite = null;
      await store.flush();
      final cleanWrites = disk.writes.length;
      await store.flush();
      expect(disk.writes.length, cleanWrites);
    });

    test(
      'failed A archive write cannot switch owner, throws=$throws',
      () async {
        await seedPrivateAccount();
        final revision = store.accountBindingRevision;
        disk
          ..failingWrite = _diskKey(_accountKey('A'))
          ..throwOnFailure = throws;
        await expectLater(store.bindAccount('B'), throwsStateError);
        expect(store.accountUid, 'A');
        expect(store.accountBindingRevision, revision);
        expect(store.data.bio, 'A private biography');
        expect((await disk.player())['accountUid'], 'A');

        disk.failingWrite = null;
        await store.bindAccount('B');
        expect(store.data.bio, isNot('A private biography'));
        await store.bindAccount('A');
        expect(store.data.bio, 'A private biography');
        expect(store.hasChosenUsername, isTrue);
        expect(store.hasCompletedTutorial, isTrue);
        expect(store.tutorialStep, 6);
      },
    );

    test('failed A tombstone cannot erase B later, throws=$throws', () async {
      await seedPrivateAccount();
      disk
        ..failingWrite = _diskKey(_tombstoneKey('A'))
        ..throwOnFailure = throws;
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      await store.bindAccount('B');
      store.data.bio = 'B after failed A tombstone';
      store.hasChosenUsername = true;
      store.hasCompletedTutorial = true;
      store.tutorialStep = 8;
      await store.save();
      final before = await disk.getAll();

      disk.failingWrite = null;
      await store.flush();

      await expectPrivateAccountCleared();
      final after = await disk.getAll();
      expect(store.accountUid, 'B');
      expect(after[_diskKey(_playerKey)], before[_diskKey(_playerKey)]);
      expect(after[_diskKey('luno_tutorial_step_v1')], 8);
      expect(after[_diskKey('luno_username_chosen_v1')], true);
      expect(after[_diskKey('luno_tutorial_completed_v1')], true);
      expect(after[_diskKey(_tombstoneKey('B'))], isNull);
    });

    test('erasure retains failed schema metadata, throws=$throws', () async {
      await seedPrivateAccount();
      disk
        ..failingWrite = _diskKey('luno_player_schema_v2')
        ..throwOnFailure = throws;
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      expect(store.accountUid, isNull);
      final attempts =
          disk.writes
              .where((key) => key == _diskKey('luno_player_schema_v2'))
              .length;

      disk.failingWrite = null;
      await store.flush();

      expect(
        disk.writes
            .where((key) => key == _diskKey('luno_player_schema_v2'))
            .length,
        greaterThan(attempts),
      );
      await expectPrivateAccountCleared();
    });
  }

  for (final failingKey in [_playerKey, _accountKey('A')]) {
    test('restart retries cleanup after failed $failingKey', () async {
      await seedPrivateAccount();
      if (failingKey == _playerKey) {
        disk.failingWrite = _diskKey(failingKey);
      } else {
        disk.failingRemoval = _diskKey(failingKey);
      }
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      expect((await disk.getAll())[_diskKey(_tombstoneKey('A'))], true);
      disk
        ..failingWrite = null
        ..failingRemoval = null;
      SharedPreferences.resetStatic();
      final restarted = GameStore.createForTesting();
      addTearDown(restarted.dispose);

      await restarted.load();
      expect(restarted.accountUid, isNull);
      expect(restarted.data.bio, PlayerData.initial().bio);
      await restarted.flush();

      await expectPrivateAccountCleared();
      final repaired = await disk.player();
      expect(repaired['username'], PlayerData.fromJson(repaired).username);
      final cleanWrites = disk.writes.length;
      SharedPreferences.resetStatic();
      final cleanRestart = GameStore.createForTesting();
      addTearDown(cleanRestart.dispose);
      await cleanRestart.load();
      await cleanRestart.flush();
      expect(disk.writes.length, cleanWrites);
    });
  }

  for (final invalid in ['not a bool', 7]) {
    test('malformed A tombstone preserves healthy owner: $invalid', () async {
      await seedPrivateAccount();
      await disk.setValue(
        invalid is int ? 'int' : 'String',
        _diskKey(_tombstoneKey('A')),
        invalid,
      );
      await disk.setValue('Bool', 'flutter.luno_account_v1_erased', true);
      await disk.setValue('Bool', 'flutter.luno_account_v1_!_erased', true);
      SharedPreferences.resetStatic();
      final restarted = GameStore.createForTesting();
      addTearDown(restarted.dispose);

      await restarted.load();

      expect(restarted.accountUid, 'A');
      expect(restarted.data.bio, 'A private biography');
      expect(restarted.hasChosenUsername, isTrue);
      expect(restarted.hasCompletedTutorial, isTrue);
      await restarted.bindAccount('B');
      await restarted.bindAccount('A');
      expect(restarted.data.bio, 'A private biography');
    });
  }

  test('persisted defaults are canonical on the first clean restart', () async {
    await store.save();
    expect(store.data.username, PlayerData.initial().username);
    final snapshot = await disk.player();
    expect(snapshot['username'], PlayerData.fromJson(snapshot).username);
    final cleanWrites = disk.writes.length;
    SharedPreferences.resetStatic();
    final restarted = GameStore.createForTesting();
    addTearDown(restarted.dispose);

    await restarted.load();
    await restarted.flush();

    expect(disk.writes.length, cleanWrites);
  });

  for (final malformed in <Object>['not a bool', 7, false]) {
    test('all journals tolerate non-erased marker $malformed', () async {
      final prefs = await SharedPreferences.getInstance();
      await disk.setValue(
        malformed is int
            ? 'int'
            : malformed is bool
            ? 'Bool'
            : 'String',
        _diskKey(_tombstoneKey('A')),
        malformed,
      );
      await prefs.reload();

      expect(await store.pendingPassChestRequestKinds('A'), isEmpty);
      expect(await store.pendingShopChestRequestKinds('A'), isEmpty);
      expect(
        await store.stagePassChestRequest('A', 'common', 'pass-request'),
        'pass-request',
      );
      expect(
        await store.stageShopChestRequest('A', 'rare', 'shop-request'),
        'shop-request',
      );
      expect(await store.pendingPassChestRequestKinds('A'), ['common']);
      expect(await store.pendingShopChestRequestKinds('A'), ['rare']);
      await store.clearPassChestRequest('A', 'common', 'pass-request');
      await store.clearShopChestRequest('A', 'rare', 'shop-request');
      expect(await store.pendingPassChestRequestKinds('A'), isEmpty);
      expect(await store.pendingShopChestRequestKinds('A'), isEmpty);

      expect(await store.pendingPermanentPurchaseItems('A'), isEmpty);
      expect(
        await store.stagePermanentPurchase('A', 'emoji:wave', 'item-request'),
        'item-request',
      );
      expect(await store.pendingPermanentPurchaseItems('A'), ['emoji:wave']);
      await store.clearPermanentPurchase('A', 'emoji:wave', 'item-request');
      expect(await store.pendingPermanentPurchaseItems('A'), isEmpty);

      const premium = PassPremiumPurchase(
        seasonId: 's1',
        requestId: 'premium-request',
      );
      expect(await store.pendingPassPremiumPurchase('A'), isNull);
      expect(
        (await store.stagePassPremiumPurchase('A', premium)).requestId,
        premium.requestId,
      );
      expect(
        (await store.pendingPassPremiumPurchase('A'))?.requestId,
        premium.requestId,
      );
      await store.clearPassPremiumPurchase('A', premium);
      expect(await store.pendingPassPremiumPurchase('A'), isNull);

      const attempt = '0123456789abcdef0123456789abcdef';
      expect(await store.readGoogleLinkAttempt('A'), isNull);
      await store.writeGoogleLinkAttempt('A', attempt);
      expect(await store.readGoogleLinkAttempt('A'), attempt);
      await store.writeGoogleLinkAttempt('A', null);
      expect(await store.readGoogleLinkAttempt('A'), isNull);
      expect(store.accountUid, 'A');
    });
  }

  test('a real tombstone blocks every journal without writes', () async {
    const premium = PassPremiumPurchase(
      seasonId: 's1',
      requestId: 'premium-request',
    );
    const attempt = '0123456789abcdef0123456789abcdef';
    await store.stagePassChestRequest('A', 'common', 'pass-request');
    await store.stageShopChestRequest('A', 'rare', 'shop-request');
    await store.stagePermanentPurchase('A', 'emoji:wave', 'item-request');
    await store.stagePassPremiumPurchase('A', premium);
    await store.writeGoogleLinkAttempt('A', attempt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tombstoneKey('A'), true);
    final writes = disk.writes.length;
    final removals = disk.removals.length;

    expect(await store.pendingPassChestRequestKinds('A'), isEmpty);
    expect(await store.pendingShopChestRequestKinds('A'), isEmpty);
    expect(await store.pendingPermanentPurchaseItems('A'), isEmpty);
    expect(await store.pendingPassPremiumPurchase('A'), isNull);
    expect(await store.readGoogleLinkAttempt('A'), isNull);
    await expectLater(
      store.stagePassChestRequest('A', 'common', 'new-pass-request'),
      throwsStateError,
    );
    await expectLater(
      store.stageShopChestRequest('A', 'rare', 'new-shop-request'),
      throwsStateError,
    );
    await expectLater(
      store.clearPassChestRequest('A', 'common', 'pass-request'),
      throwsStateError,
    );
    await expectLater(
      store.clearShopChestRequest('A', 'rare', 'shop-request'),
      throwsStateError,
    );
    await expectLater(
      store.stagePermanentPurchase('A', 'emoji:wave', 'new-item-request'),
      throwsStateError,
    );
    await expectLater(
      store.clearPermanentPurchase('A', 'emoji:wave', 'item-request'),
      throwsStateError,
    );
    await expectLater(
      store.stagePassPremiumPurchase('A', premium),
      throwsStateError,
    );
    await expectLater(
      store.clearPassPremiumPurchase('A', premium),
      throwsStateError,
    );
    await expectLater(
      store.writeGoogleLinkAttempt('A', attempt),
      throwsStateError,
    );
    await expectLater(
      store.writeGoogleLinkAttempt('A', null),
      throwsStateError,
    );
    expect(disk.writes.length, writes);
    expect(disk.removals.length, removals);
  });

  test('owner departure precedes a stalled tombstone write', () async {
    await seedPrivateAccount();
    final entered = Completer<void>();
    final gate = Completer<void>();
    disk
      ..gatedWrite = _diskKey(_tombstoneKey('A'))
      ..entered = entered
      ..gate = gate;
    final erased = store.eraseLocalAccount('A');
    try {
      await entered.future.timeout(const Duration(seconds: 1));
      expect(store.accountUid, isNull);
      expect(store.data.bio, PlayerData.initial().bio);
    } finally {
      gate.complete();
      await erased;
    }
    await expectPrivateAccountCleared();
  });

  test('flush cleanup serializes a subsequent account switch', () async {
    await seedPrivateAccount();
    disk.failingRemoval = _diskKey(_accountKey('A'));
    await expectLater(store.eraseLocalAccount('A'), throwsStateError);
    final entered = Completer<void>();
    final gate = Completer<void>();
    disk
      ..failingRemoval = null
      ..gatedRemoval = _diskKey(_accountKey('A'))
      ..entered = entered
      ..gate = gate;
    final flushed = store.flush();
    Future<void>? switched;
    try {
      await entered.future.timeout(const Duration(seconds: 1));
      switched = store.bindAccount('B');
      await Future<void>.delayed(Duration.zero);
      expect(store.accountUid, isNull);
    } finally {
      gate.complete();
      await flushed;
      if (switched != null) await switched;
    }
    expect(store.accountUid, 'B');
    await expectPrivateAccountCleared();
  });

  test('erasure persistence cannot overwrite a newer guest save', () async {
    await seedPrivateAccount();
    final entered = Completer<void>();
    final gate = Completer<void>();
    disk
      ..gatedWrite = _diskKey(_playerKey)
      ..gateAfterWrite = _diskKey(_tombstoneKey('A'))
      ..entered = entered
      ..gate = gate;
    final erased = store.eraseLocalAccount('A');
    Future<void>? guestSaved;
    try {
      await entered.future.timeout(const Duration(seconds: 1));
      expect(store.accountUid, isNull);
      store.data.bio = 'new guest biography';
      guestSaved = store.save();
      await Future<void>.delayed(Duration.zero);
    } finally {
      gate.complete();
      await erased;
      if (guestSaved != null) await guestSaved;
    }

    expect((await disk.player())['bio'], 'new guest biography');
    expect((await disk.player())['accountUid'], isNull);
    await expectPrivateAccountCleared();
  });

  test(
    'old in-flight save cannot survive a failed erasure tombstone',
    () async {
      await seedPrivateAccount();
      final entered = Completer<void>();
      final gate = Completer<void>();
      disk
        ..gatedWrite = _diskKey(_playerKey)
        ..entered = entered
        ..gate = gate;
      store.data.bio = 'A pending private biography';
      final pending = store.save();
      await entered.future.timeout(const Duration(seconds: 1));
      disk.failingWrite = _diskKey(_tombstoneKey('A'));
      final erased = store.eraseLocalAccount('A');
      final rejected = expectLater(erased, throwsStateError);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(store.accountUid, isNull);
      } finally {
        gate.complete();
        await pending;
        await rejected;
      }

      expect((await disk.player())['accountUid'], isNull);
      expect((await disk.player())['bio'], PlayerData.initial().bio);
      disk.failingWrite = null;
      await store.flush();
      await expectPrivateAccountCleared();
    },
  );
}
