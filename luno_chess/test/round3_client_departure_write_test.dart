import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing preference test transport; no runtime dependency is added.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

String _archiveKey(String uid) =>
    'flutter.luno_account_v1_${base64Url.encode(utf8.encode(uid))}';

class _HeldArchive extends InMemorySharedPreferencesStore {
  _HeldArchive() : super.empty();
  Completer<void>? gate;
  Completer<void>? entered;
  String heldKey = _archiveKey('first');
  int archiveWrites = 0;
  int? rejectedArchiveWrite;
  bool throwOnReject = false;
  Future<void> Function(int)? beforeArchiveWrite;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == heldKey) {
      final write = ++archiveWrites;
      if (gate != null) {
        final pending = gate!;
        gate = null;
        entered!.complete();
        await pending.future;
      }
      await beforeArchiveWrite?.call(write);
      if (write == rejectedArchiveWrite) {
        if (throwOnReject) throw StateError('Local archive unavailable');
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _HeldArchive disk;
  late GameStore store;

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    disk = _HeldArchive();
    SharedPreferencesStorePlatform.instance = disk;
    store = GameStore.createForTesting();
    await store.bindAccount('first');
    await store.chooseUsername('original_name');
  });

  tearDown(() async {
    await store.flush();
    store.dispose();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  for (final held in [false, true]) {
    test(
      'departure preserves username saved ${held ? 'during archive write' : 'before switch'}',
      () async {
        Future<void>? switching;
        final gate = Completer<void>();
        if (held) {
          disk
            ..gate = gate
            ..entered = Completer<void>();
          switching = store.bindAccount('second');
          await disk.entered!.future;
          expect(store.accountUid, 'first');
        }
        await store.chooseUsername('latest_name');
        final active = await disk.getAll();
        expect(
          jsonDecode(active['flutter.luno_player_v1']! as String)['username'],
          'latest_name',
        );
        if (held) {
          gate.complete();
          await switching;
        } else {
          await store.bindAccount('second');
        }
        expect(store.accountUid, 'second');
        expect(store.data.username, isNot('latest_name'));
        await store.bindAccount('first');
        expect(store.data.username, 'latest_name');
      },
    );
  }
  for (final throwing in [false, true]) {
    test(
      'a ${throwing ? 'throwing' : 'rejected'} latest archive retains the live owner and edits',
      () async {
        final revision = store.accountBindingRevision;
        final gate = Completer<void>();
        disk
          ..gate = gate
          ..entered = Completer<void>()
          ..rejectedArchiveWrite = 2
          ..throwOnReject = throwing;
        final operation = store.bindAccount('second');
        await disk.entered!.future;
        await store.chooseUsername('latest_name');
        final assertion = expectLater(operation, throwsStateError);
        gate.complete();
        await assertion;
        expect(store.accountUid, 'first');
        expect(store.accountBindingRevision, revision);
        expect(store.data.username, 'latest_name');
        disk.rejectedArchiveWrite = null;
        await store.bindAccount('second');
        await store.bindAccount('first');
        expect(store.data.username, 'latest_name');
      },
    );
  }

  test(
    'a finite burst of edits during archive corrections is preserved',
    () async {
      disk.beforeArchiveWrite = (write) async {
        if (write <= 2) await store.chooseUsername('edit_$write');
      };
      await store.bindAccount('second');
      expect(disk.archiveWrites, 3);
      disk.beforeArchiveWrite = null;
      await store.bindAccount('first');
      expect(store.data.username, 'edit_2');
    },
  );

  test(
    'sustained edits bound the switch and retain the current owner',
    () async {
      final revision = store.accountBindingRevision;
      disk.beforeArchiveWrite = (write) => store.chooseUsername('edit_$write');
      await expectLater(
        store.bindAccount('second').timeout(const Duration(seconds: 2)),
        throwsStateError,
      );
      expect(disk.archiveWrites, 4);
      expect(store.accountUid, 'first');
      expect(store.accountBindingRevision, revision);
      expect(store.data.username, 'edit_4');
      disk.beforeArchiveWrite = null;
      await store.bindAccount('second');
      await store.bindAccount('first');
      expect(store.data.username, 'edit_4');
    },
  );

  test(
    'new unowned recovery backup keeps edits while restoring an account',
    () async {
      await store.flush();
      store.dispose();
      SharedPreferences.resetStatic();
      disk = _HeldArchive();
      SharedPreferencesStorePlatform.instance = disk;
      store = GameStore.createForTesting();
      await store.load();
      await store.chooseUsername('original_name');
      final gate = Completer<void>();
      disk
        ..heldKey = 'flutter.luno_unowned_account_backup_v1'
        ..gate = gate
        ..entered = Completer<void>();
      final operation = store.bindAccount('existing', restoreExisting: true);
      await disk.entered!.future;
      await store.chooseUsername('latest_name');
      gate.complete();
      await operation;
      expect(store.accountUid, 'existing');
      expect(store.data.username, isNot('latest_name'));
      final values = await disk.getAll();
      final backup = jsonDecode(
        values['flutter.luno_unowned_account_backup_v1']! as String,
      );
      expect(backup['username'], 'latest_name');
      expect(backup.containsKey('accountUid'), false);
    },
  );
}
