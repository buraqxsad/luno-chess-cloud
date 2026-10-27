import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing preference test transport; no new runtime dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Disk extends InMemorySharedPreferencesStore {
  _Disk() : super.empty();

  String? failingKey;
  bool throwOnWrite = false;
  Completer<void>? entered, gate;
  final writes = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    if (key == 'flutter.luno_player_v1' && gate != null) {
      final wait = gate!;
      gate = null;
      entered?.complete();
      await wait.future;
    }
    if (key == failingKey) {
      if (throwOnWrite) throw StateError('Disk unavailable');
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  Future<Map<String, dynamic>> player() async {
    final values = await getAll();
    return Map<String, dynamic>.from(
      jsonDecode(values['flutter.luno_player_v1']! as String) as Map,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Disk disk;
  late GameStore store;

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    disk = _Disk();
    SharedPreferencesStorePlatform.instance = disk;
    store = GameStore.createForTesting();
    await store.bindAccount('A');
  });
  tearDown(() {
    store.dispose();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  for (final throws in [false, true]) {
    test(
      'flush retries a ${throws ? 'throwing' : 'rejected'} player write',
      () async {
        store.data.bio = 'latest biography';
        disk
          ..failingKey = 'flutter.luno_player_v1'
          ..throwOnWrite = throws;
        await store.save();
        expect((await disk.player())['bio'], isNot('latest biography'));
        disk.failingKey = null;
        await store.flush();
        expect((await disk.player())['bio'], 'latest biography');
        SharedPreferences.resetStatic();
        final restored = GameStore.createForTesting();
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.accountUid, 'A');
        expect(restored.data.bio, 'latest biography');
      },
    );
  }

  for (final key in [
    'luno_player_schema_v2',
    'luno_username_chosen_v1',
    'luno_tutorial_completed_v1',
    'luno_tutorial_step_v1',
  ]) {
    test('flush repairs rejected compatibility write $key', () async {
      disk.failingKey = 'flutter.$key';
      store.hasChosenUsername = true;
      store.hasCompletedTutorial = true;
      store.tutorialStep = 3;
      await store.save();
      final failedAttempts =
          disk.writes.where((write) => write == 'flutter.$key').length;
      disk.failingKey = null;
      await store.flush();
      expect(
        disk.writes.where((write) => write == 'flutter.$key').length,
        failedAttempts + 1,
      );
      final values = await disk.getAll();
      expect(values['flutter.luno_username_chosen_v1'], true);
      expect(values['flutter.luno_tutorial_completed_v1'], true);
      expect(values['flutter.luno_tutorial_step_v1'], 3);
    });
  }

  test(
    'persistent storage failure is bounded and recovery saves the newest state',
    () async {
      disk.failingKey = 'flutter.luno_player_v1';
      store.data.bio = 'old edit';
      await store.save();
      final attempts = disk.writes.length;
      await store.flush().timeout(const Duration(seconds: 1));
      expect(disk.writes.length - attempts, 1);
      store.data.bio = 'new edit';
      disk.failingKey = null;
      await store.save();
      await store.flush();
      expect((await disk.player())['bio'], 'new edit');
      final cleanWrites = disk.writes.length;
      await store.flush();
      expect(disk.writes.length, cleanWrites);
    },
  );

  test('a newer queued save wins over an older failed write', () async {
    disk
      ..failingKey = 'flutter.luno_player_v1'
      ..entered = Completer<void>()
      ..gate = Completer<void>();
    final gate = disk.gate!;
    store.data.bio = 'first';
    final first = store.save();
    await disk.entered!.future;
    store.data.bio = 'second';
    final second = store.save();
    gate.complete();
    await Future.wait([first, second]);
    disk.failingKey = null;
    await store.flush();
    expect((await disk.player())['bio'], 'second');
  });

  test('a failed player write cannot retry one account into another', () async {
    store.data.bio = 'A biography';
    disk.failingKey = 'flutter.luno_player_v1';
    await store.save();
    await store.bindAccount('B');
    expect(store.accountUid, 'B');
    expect(store.data.bio, isNot('A biography'));
    disk.failingKey = null;
    await store.flush();
    expect((await disk.player())['accountUid'], 'B');
    expect((await disk.player())['bio'], isNot('A biography'));
    await store.bindAccount('A');
    expect(store.data.bio, 'A biography');
  });

  test(
    'a rejected player write cannot advance legacy onboarding flags',
    () async {
      final before = await disk.getAll();
      disk.failingKey = 'flutter.luno_player_v1';
      store.hasChosenUsername = true;
      store.hasCompletedTutorial = true;
      store.tutorialStep = 4;
      await store.save();
      final after = await disk.getAll();
      for (final key in [
        'luno_username_chosen_v1',
        'luno_tutorial_completed_v1',
        'luno_tutorial_step_v1',
      ]) {
        expect(after['flutter.$key'], before['flutter.$key']);
      }
    },
  );

  test(
    'confirmed erasure notifies account departure even if sanitized write fails',
    () async {
      store.data.bio = 'private biography';
      await store.save();
      var departures = 0;
      store.addListener(() {
        if (store.accountUid == null) departures++;
      });
      final revision = store.accountBindingRevision;
      disk.failingKey = 'flutter.luno_player_v1';
      await expectLater(store.eraseLocalAccount('A'), throwsStateError);
      expect(store.accountUid, isNull);
      expect(store.accountBindingRevision, greaterThan(revision));
      expect(store.data.bio, isNot('private biography'));
      expect(departures, 1);
      disk.failingKey = null;
      await store.flush();
      expect((await disk.player())['accountUid'], isNull);
      expect((await disk.player())['bio'], isNot('private biography'));
      await expectLater(
        store.bindAccount('A'),
        throwsA(isA<LocalAccountErasedException>()),
      );
      await store.eraseLocalAccount('A');
    },
  );

  for (final throws in [false, true]) {
    test('failed legacy migration remains retryable, throws=$throws', () async {
      final legacy = await disk.player();
      legacy['bio'] = 'preserved legacy biography';
      legacy['schemaVersion'] = 1;
      await disk.setValue(
        'String',
        'flutter.luno_player_v1',
        jsonEncode(legacy),
      );
      await disk.setValue('int', 'flutter.luno_player_schema_v2', 1);
      disk
        ..failingKey = 'flutter.luno_player_v1'
        ..throwOnWrite = throws;
      SharedPreferences.resetStatic();
      final migrated = GameStore.createForTesting();
      addTearDown(migrated.dispose);
      await migrated.load();
      expect(migrated.data.bio, 'preserved legacy biography');
      expect((await disk.player())['schemaVersion'], 1);
      disk.failingKey = null;
      await migrated.flush();
      expect((await disk.player())['schemaVersion'], 2);
      expect((await disk.player())['bio'], 'preserved legacy biography');
    });
  }
}
