import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing platform test transport, no dependency added.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

class _HeldDisk extends InMemorySharedPreferencesStore {
  _HeldDisk() : super.empty();
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.luno_player_v1' && gate != null) {
      final pending = gate!;
      gate = null;
      entered!.complete();
      await pending.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _HeldDisk disk;
  late GameStore store;
  late TestAuth auth;
  late LunoOnlineService service;
  var disposed = false;
  var reject = false;
  Completer<void>? bootstrapGate;

  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    disk = _HeldDisk();
    SharedPreferencesStorePlatform.instance = disk;
    store = GameStore.createForTesting();
    auth = TestAuth();
    disposed = false;
    reject = false;
    bootstrapGate = null;
    service = LunoOnlineService.forTesting(
      auth: auth,
      playerStore: store,
      bootstrap: () async {
        await bootstrapGate?.future;
      },
      appCheck: () async => 'local-test-check',
      client: MockClient(
        (_) async =>
            reject
                ? http.Response('{"ok":false,"error":"account-deleted"}', 403)
                : http.Response(
                  jsonEncode({
                    'ok': true,
                    'state': {
                      'profile': {
                        'username': 'generated_alias',
                        'usernameGenerated': true,
                      },
                      'gold': 4321,
                    },
                  }),
                  200,
                ),
      ),
    );
    await service.start();
    store.hasChosenUsername = true;
    store.data.username = 'chosen_draft';
    await store.save();
  });

  tearDown(() async {
    if (!disposed) service.dispose();
    await store.flush();
    store.dispose();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  for (final boundary in [
    'same-session',
    'account-change',
    'dispose',
    'access-denied',
    'retry',
    'store-notification-account-change',
    'store-notification-dispose',
  ]) {
    test(
      'refresh completion after username persistence respects $boundary',
      () async {
        final previousSync = service.lastSyncAt;
        final beforeGold = store.data.gold;
        final blocked = Completer<void>();
        disk
          ..gate = blocked
          ..entered = Completer<void>();
        final operation = service.refreshState();
        // The HTTP response has passed the API owner gate; hold only the actual
        // SharedPreferences write performed by requireUsernamePublication.
        await disk.entered!.future;
        Future<void>? rejected;
        Future<void>? restarted;
        if (boundary.startsWith('store-notification-')) {
          store.addListener(() {
            if (store.data.gold != 4321 || disposed) return;
            if (boundary == 'store-notification-account-change') {
              auth.currentUser = TestUser('second');
            } else {
              service.dispose();
              disposed = true;
            }
          });
        }
        if (boundary == 'account-change') {
          auth.currentUser = TestUser('second');
        } else if (boundary == 'dispose') {
          service.dispose();
          disposed = true;
        } else if (boundary == 'access-denied') {
          reject = true;
          rejected = expectLater(
            service.api('/getPlayerState', {}),
            throwsA(isA<LunoApiException>()),
          );
          // account-deleted starts local erasure after marking access failure;
          // the same disk gate intentionally holds the erasure flush too.
          await Future<void>.delayed(Duration.zero);
          expect(service.accountFailure?.code, 'account-deleted');
        } else if (boundary == 'retry') {
          // retry rotates both request generation and local response epoch.
          bootstrapGate = Completer<void>();
          restarted = service.retry();
          await Future<void>.delayed(Duration.zero);
        }
        final expectedFailure = service.lastError;
        final assertion =
            boundary == 'same-session'
                ? expectLater(operation, completes)
                : expectLater(
                  operation,
                  throwsA(
                    isA<LunoApiException>().having(
                      (e) => e.code,
                      'code',
                      boundary == 'access-denied'
                          ? 'account-deleted'
                          : 'session-changed',
                    ),
                  ),
                );
        blocked.complete();
        try {
          await assertion;
        } finally {
          bootstrapGate?.complete();
        }
        if (rejected != null) await rejected;
        if (boundary == 'same-session') {
          expect(store.data.gold, 4321);
          expect(service.lastError, isNull);
        } else {
          expect(service.lastSyncAt, previousSync);
          if (boundary == 'access-denied') {
            expect(service.lastError, expectedFailure);
          }
          if (!boundary.startsWith('store-notification-')) {
            expect(store.data.gold, beforeGold);
          }
        }
        if (restarted != null) await restarted;
      },
    );
  }
}
