import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing preference transport; no runtime dependency is added.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

String _archive(String uid) =>
    'luno_account_v1_${base64Url.encode(utf8.encode(uid))}';
const _legacyBackup = 'luno_unowned_account_backup_v1';
const _legacyOwner = 'luno_unowned_account_backup_owner_v1';
const _legacyPending = 'luno_unowned_account_backup_pending_v1';

class _RecoveryDisk extends InMemorySharedPreferencesStore {
  _RecoveryDisk() : super.empty();

  String? rejectedKey;
  bool throwing = false;
  bool commitBeforeThrow = false;
  String? rejectedRemoval;
  bool rejectedReads = false;
  Future<void> Function(String, Object)? beforeWrite;
  final writes = <String>[];
  final removals = <String>[];

  @override
  Future<Map<String, Object>> getAll() async {
    if (rejectedReads) throw StateError('Preferences unavailable');
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add(key);
    await beforeWrite?.call(key, value);
    if (key == 'flutter.$rejectedKey') {
      if (commitBeforeThrow) await super.setValue(type, key, value);
      if (throwing) throw StateError('Recovery disk unavailable');
      return false;
    }
    return super.setValue(type, key, value);
  }

  Future<Object?> durable(String key) async => (await getAll())['flutter.$key'];

  @override
  Future<bool> remove(String key) async {
    removals.add(key);
    if (key == 'flutter.$rejectedRemoval') {
      if (commitBeforeThrow) await super.remove(key);
      if (throwing) throw StateError('Recovery removal unavailable');
      return false;
    }
    return super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _RecoveryDisk disk;
  late GameStore store;

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    disk = _RecoveryDisk();
    SharedPreferencesStorePlatform.instance = disk;
    store = GameStore.createForTesting();
  });
  tearDown(() async {
    await store.flush();
    store.dispose();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  Future<void> restartStore() async {
    store.dispose();
    SharedPreferences.resetStatic();
    store = GameStore.createForTesting();
    await store.load();
  }

  for (final failure in ['none', 'false', 'throw']) {
    for (final raw in [
      '{broken-private-profile',
      '{"accountUid":"other","bio":"private-archive"}',
    ]) {
      test(
        'damaged archive recovery survives $failure write and retry: $raw',
        () async {
          await store.bindAccount('first');
          final prefs = await SharedPreferences.getInstance();
          final key = '${_archive('second')}_recovery';
          await prefs.setString(_archive('second'), raw);
          final revision = store.accountBindingRevision;
          if (failure != 'none') {
            disk
              ..rejectedKey = key
              ..throwing = failure == 'throw';
            await expectLater(store.bindAccount('second'), throwsStateError);
            expect(store.accountUid, 'first');
            expect(store.accountBindingRevision, revision);
            expect(await disk.durable(key), isNull);
            expect(
              prefs.getString(key),
              raw,
              reason:
                  'The plugin optimistically updates its cache even though disk rejected the write.',
            );
            disk.rejectedKey = null;
          }
          await store.bindAccount('second');
          expect(store.data.bio, PlayerData.initial().bio);
          await store.bindAccount('first');
          expect(await disk.durable(_archive('second')), isNot(raw));
          expect(
            await disk.durable(key),
            raw,
            reason:
                'Leaving second replaces its invalid archive, so recovery must already be durable.',
          );
        },
      );
    }
  }

  for (final failure in ['none', 'false', 'throw']) {
    for (final key in [_legacyPending, _legacyBackup, _legacyOwner]) {
      test(
        'first association recovery survives $failure $key write and retry',
        () async {
          await store.load();
          await store.chooseUsername('legacy_owner');
          store.data.bio = 'unowned progress requiring recovery';
          await store.save();
          final revision = store.accountBindingRevision;
          if (failure != 'none') {
            disk
              ..rejectedKey = key
              ..throwing = failure == 'throw';
            await expectLater(store.bindAccount('first'), throwsStateError);
            expect(store.accountUid, isNull);
            expect(store.accountBindingRevision, revision);
            expect(await disk.durable(key), isNull);
            disk.rejectedKey = null;
          }
          await store.bindAccount('first');
          await store.bindAccount('second');
          expect(store.data.bio, isNot('unowned progress requiring recovery'));
          final raw = await disk.durable(_legacyBackup);
          expect(
            raw,
            isA<String>(),
            reason:
                'The unowned profile must have a durable recovery copy before association.',
          );
          if (raw is String) {
            expect(
              (jsonDecode(raw) as Map)['bio'],
              'unowned progress requiring recovery',
            );
          }
          expect(
            await disk.durable(_legacyOwner),
            'first',
            reason:
                'Recovery ownership must be durable before association can succeed.',
          );
        },
      );
    }
  }

  test(
    'persistent recovery failure keeps rejecting a switch on retry',
    () async {
      await store.bindAccount('first');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_archive('second'), '{broken-private-profile');
      disk.rejectedKey = '${_archive('second')}_recovery';
      final revision = store.accountBindingRevision;
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(store.bindAccount('second'), throwsStateError);
        expect(store.accountUid, 'first');
        expect(store.accountBindingRevision, revision);
      }
      disk.rejectedKey = null;
    },
  );

  for (final key in [_legacyPending, _legacyBackup, _legacyOwner]) {
    for (final failure in ['false', 'throw', 'committed-throw']) {
      final committed = failure == 'committed-throw';
      test(
        'first association recovery retries after restart; $failure key=$key',
        () async {
          await store.load();
          store.data.bio = 'durable unowned biography';
          await store.save();
          disk
            ..rejectedKey = key
            ..throwing = failure != 'false'
            ..commitBeforeThrow = committed;
          await expectLater(store.bindAccount('first'), throwsStateError);
          expect(await disk.durable(key), committed ? isNotNull : isNull);
          disk.rejectedKey = null;
          await restartStore();
          expect(store.accountUid, isNull);
          expect(store.data.bio, 'durable unowned biography');
          await store.bindAccount('first');
          final backup =
              jsonDecode(await disk.durable(_legacyBackup) as String) as Map;
          expect(backup['bio'], 'durable unowned biography');
          expect(await disk.durable(_legacyOwner), 'first');
          expect(await disk.durable(_legacyPending), isNull);
          await store.eraseLocalAccount('first');
          expect(await disk.durable(_legacyBackup), isNull);
          expect(await disk.durable(_legacyOwner), isNull);
          expect(await disk.durable(_legacyPending), isNull);
        },
      );
    }
  }

  for (final failure in ['false', 'throw', 'committed-throw']) {
    final committed = failure == 'committed-throw';
    test(
      'invalid archive remains recoverable across restart; $failure',
      () async {
        await store.bindAccount('first');
        final prefs = await SharedPreferences.getInstance();
        const raw = '{broken-private-profile';
        final key = '${_archive('second')}_recovery';
        await prefs.setString(_archive('second'), raw);
        disk
          ..rejectedKey = key
          ..throwing = failure != 'false'
          ..commitBeforeThrow = committed;
        await expectLater(store.bindAccount('second'), throwsStateError);
        expect(await disk.durable(key), committed ? raw : isNull);
        disk.rejectedKey = null;
        await restartStore();
        await store.bindAccount('second');
        await store.bindAccount('first');
        expect(await disk.durable(key), raw);
      },
    );
  }

  for (final boundary in ['same-process', 'restart']) {
    for (final throwing in [false, true]) {
      test(
        'unowned archive correction retries preserve latest edits; $boundary throws=$throwing',
        () async {
          await store.load();
          await store.chooseUsername('original_name');
          var backups = 0;
          disk.beforeWrite = (key, _) async {
            if (key != 'flutter.$_legacyBackup') return;
            if (++backups == 1) {
              await store.chooseUsername('latest_name');
            } else if (backups == 2) {
              disk
                ..rejectedKey = _legacyBackup
                ..throwing = throwing;
            }
          };
          await expectLater(
            store.bindAccount('existing', restoreExisting: true),
            throwsStateError,
          );
          expect(store.data.username, 'latest_name');
          disk
            ..beforeWrite = null
            ..rejectedKey = null;
          if (boundary == 'restart') await restartStore();
          await store.bindAccount('existing', restoreExisting: true);
          expect(store.data.username, isNot('latest_name'));
          final backup =
              jsonDecode(await disk.durable(_legacyBackup) as String) as Map;
          expect(backup['username'], 'latest_name');
        },
      );
    }
  }

  for (final boundary in ['same-process', 'restart']) {
    for (final failure in ['false', 'throw', 'committed-throw']) {
      test(
        'completed recovery retries pending-marker removal; $boundary $failure',
        () async {
          await store.load();
          store.data.bio = 'completed recovery biography';
          await store.save();
          disk
            ..rejectedRemoval = _legacyPending
            ..throwing = failure != 'false'
            ..commitBeforeThrow = failure == 'committed-throw';
          await store.bindAccount('first');
          expect(store.accountUid, 'first');
          expect(
            await disk.durable(_legacyPending),
            failure == 'committed-throw' ? isNull : 'first',
          );
          // Flush must retry a rejected removal even though prefs removed its cache entry.
          final attempts = disk.removals.length;
          await store.flush();
          expect(disk.removals.length, attempts + 1);
          final retryAttempts = disk.removals.length;
          await store.flush();
          expect(disk.removals.length, retryAttempts + 1);
          disk.rejectedRemoval = null;
          if (boundary == 'restart') await restartStore();
          await store.flush();
          expect(await disk.durable(_legacyPending), isNull);
          final backup =
              jsonDecode(await disk.durable(_legacyBackup) as String) as Map;
          expect(backup['bio'], 'completed recovery biography');
          await store.eraseLocalAccount('first');
          expect(await disk.durable(_legacyBackup), isNull);
          expect(await disk.durable(_legacyOwner), isNull);
        },
      );
    }
  }

  test('completed pre-existing unowned recovery copy stays intact', () async {
    const original = '{"bio":"older completed recovery"}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_legacyBackup, original);
    await store.load();
    store.data.bio = 'current unowned snapshot';
    await store.save();
    await store.bindAccount('existing', restoreExisting: true);
    expect(await disk.durable(_legacyBackup), original);
    expect(await disk.durable(_legacyPending), isNull);
    expect(await disk.durable(_legacyOwner), isNull);
  });

  test(
    'completed pre-existing damaged archive recovery copy stays intact',
    () async {
      await store.bindAccount('first');
      final prefs = await SharedPreferences.getInstance();
      const original = '{earlier-private-profile';
      final key = '${_archive('second')}_recovery';
      await prefs.setString(key, original);
      await prefs.setString(_archive('second'), '{another-broken-profile');
      await store.bindAccount('second');
      await store.bindAccount('first');
      expect(await disk.durable(key), original);
    },
  );

  for (final boundary in ['same-process', 'restart']) {
    for (final key in [_legacyPending, _legacyBackup, _legacyOwner]) {
      test(
        'interrupted first association can retry another UID; $boundary key=$key',
        () async {
          await store.load();
          store.data.bio = 'unowned biography adopted by second';
          await store.save();
          disk.rejectedKey = key;
          await expectLater(store.bindAccount('first'), throwsStateError);
          disk.rejectedKey = null;
          if (boundary == 'restart') await restartStore();
          await store.bindAccount('second');
          expect(store.accountUid, 'second');
          expect(store.data.bio, 'unowned biography adopted by second');
          expect(await disk.durable(_legacyOwner), 'second');
          expect(await disk.durable(_legacyPending), isNull);
          final backup = await disk.durable(_legacyBackup);
          await store.eraseLocalAccount('first');
          expect(store.accountUid, 'second');
          expect(await disk.durable(_legacyBackup), backup);
          expect(await disk.durable(_legacyOwner), 'second');
          await store.bindAccount('third');
          await store.bindAccount('second');
          expect(store.data.bio, 'unowned biography adopted by second');
          await store.eraseLocalAccount('second');
          expect(await disk.durable(_legacyBackup), isNull);
          expect(await disk.durable(_legacyOwner), isNull);
          expect(await disk.durable(_legacyPending), isNull);
        },
      );
    }
  }

  for (final boundary in ['same-process', 'restart']) {
    test(
      'interrupted guest association cannot replace restored account archive; $boundary',
      () async {
        await store.load();
        store.data.bio = 'unowned guest biography';
        await store.save();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _archive('second'),
          jsonEncode({
            ...PlayerData.initial().toJson(),
            'accountUid': 'second',
            'bio': 'second completed profile',
          }),
        );
        disk.rejectedKey = _legacyBackup;
        await expectLater(store.bindAccount('first'), throwsStateError);
        disk.rejectedKey = null;
        if (boundary == 'restart') await restartStore();
        await store.bindAccount('second', restoreExisting: true);
        expect(store.data.bio, 'second completed profile');
        final backup =
            jsonDecode(await disk.durable(_legacyBackup) as String) as Map;
        expect(backup['bio'], 'unowned guest biography');
        expect(await disk.durable(_legacyOwner), isNull);
        await store.eraseLocalAccount('first');
        expect(store.accountUid, 'second');
        expect(store.data.bio, 'second completed profile');
        await store.bindAccount('third');
        await store.bindAccount('second');
        expect(store.data.bio, 'second completed profile');
      },
    );
  }

  test(
    'lifecycle cleanup retries unavailable preference acquisition without throwing',
    () async {
      await store.bindAccount('first');
      SharedPreferences.resetStatic();
      disk.rejectedReads = true;
      await store.flush();
      await store.flush();
      disk.rejectedReads = false;
      await store.flush();
      expect(store.accountUid, 'first');
      expect(await disk.durable(_legacyPending), isNull);
    },
  );
}
