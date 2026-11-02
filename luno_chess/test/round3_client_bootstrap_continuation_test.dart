import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing preference transport; no runtime dependency is added.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

class _HeldProfileDisk extends InMemorySharedPreferencesStore {
  _HeldProfileDisk() : super.empty();
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

  for (final boundary in [
    'same-session',
    'account-switch',
    'same-uid-relogin',
    'retry',
    'state-epoch',
    'dispose',
  ]) {
    test('guest creation local continuation respects $boundary', () async {
      final previous = SharedPreferencesStorePlatform.instance;
      SharedPreferences.resetStatic();
      final disk = _HeldProfileDisk();
      SharedPreferencesStorePlatform.instance = disk;
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final changes = StreamController<User?>.broadcast(sync: true);
      var disposed = false;
      final requests = <(String, String?)>[];
      var lookups = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        authChanges: changes.stream,
        playerStore: store,
        appCheck: () async => 'local-check',
        client: MockClient((request) async {
          final path = request.url.path.split('/').last;
          requests.add((path, auth.currentUser?.uid));
          if (path == 'createGuestPlayer') {
            return http.Response(
              '{"ok":true,"uid":"first","usernameGenerated":true}',
              200,
            );
          }
          if (++lookups == 1) {
            return http.Response(
              '{"ok":false,"error":"profile-not-found"}',
              404,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'state': {
                'profile': {
                  'username':
                      auth.currentUser?.uid == 'first'
                          ? 'alias_first'
                          : 'alias_second',
                },
                'gold': 765,
              },
            }),
            200,
          );
        }),
      );
      addTearDown(() async {
        if (!disposed) service.dispose();
        await changes.close();
        await store.flush();
        store.dispose();
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = previous;
      });
      await service.start();
      await store.chooseUsername('local_draft');
      final gate = Completer<void>();
      disk
        ..gate = gate
        ..entered = Completer<void>();
      final operation = service.ensureRemoteProfileForTesting();
      await disk.entered!.future;
      expect(requests, [
        ('getPlayerState', 'first'),
        ('createGuestPlayer', 'first'),
      ]);
      Future<void>? restarted;
      if (boundary == 'account-switch') {
        auth.currentUser = TestUser('second');
        changes.add(auth.currentUser);
        await Future<void>.delayed(Duration.zero);
        expect(service.authTransitioning, true);
      } else if (boundary == 'same-uid-relogin') {
        auth.currentUser = null;
        changes.add(null);
        auth.currentUser = TestUser('first');
        changes.add(auth.currentUser);
        await Future<void>.delayed(Duration.zero);
      } else if (boundary == 'retry') {
        restarted = service.retry();
        await Future<void>.delayed(Duration.zero);
      } else if (boundary == 'state-epoch') {
        store.invalidateServerStates();
      } else if (boundary == 'dispose') {
        service.dispose();
        disposed = true;
      }
      Object? operationError;
      final completed = operation.catchError((Object error) {
        operationError = error;
      });
      gate.complete();
      await completed;
      if (restarted != null) await restarted;
      if (boundary == 'same-session') {
        expect(operationError, isNull);
        expect(requests, [
          ('getPlayerState', 'first'),
          ('createGuestPlayer', 'first'),
          ('getPlayerState', 'first'),
        ]);
        expect(store.data.username, 'alias_first');
      } else {
        expect(
          requests,
          [('getPlayerState', 'first'), ('createGuestPlayer', 'first')],
          reason:
              'The old creation flow must not begin another owner or generation request.',
        );
        expect(
          operationError,
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'session-changed',
          ),
        );
      }
    });
  }
}
