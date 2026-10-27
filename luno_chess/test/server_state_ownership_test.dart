import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final boundary in [
    'none',
    'other-account',
    'return-to-account',
    'signout',
    'retry',
    'dispose',
    'auth-event',
    'account-block',
  ]) {
    test('delivered state respects $boundary before application', () async {
      final store = GameStore.createForTesting();
      final auth = TestAuth();
      final changes = StreamController<User?>.broadcast(sync: true);
      var blocked = false;
      final client = MockClient(
        (_) async =>
            blocked
                ? http.Response('{"ok":false,"error":"account-deleted"}', 403)
                : http.Response(
                  jsonEncode({
                    'ok': true,
                    'state': {
                      'gold': 4321,
                      'profile': {'username': 'first_player'},
                      // Wire data cannot select local response ownership.
                      GameStore.serverStateOwnerKey: 'forged',
                      GameStore.serverStateEpochKey: -1,
                    },
                  }),
                  200,
                ),
      );
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        authChanges: changes.stream,
        playerStore: store,
        client: client,
        appCheck: () async => 'check',
      );
      var disposed = false;
      addTearDown(() async {
        if (!disposed) service.dispose();
        await store.flush();
        store.dispose();
        await changes.close();
      });
      await service.start();
      final response = await service.api('/getPlayerState', {});
      final state = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(response['state'])) as Map,
      );
      expect(state[GameStore.serverStateOwnerKey], 'first');
      if (boundary == 'other-account' || boundary == 'return-to-account') {
        await store.bindAccount('second');
        if (boundary == 'return-to-account') await store.bindAccount('first');
      } else if (boundary == 'signout') {
        await store.bindAccount(null);
      } else if (boundary == 'retry') {
        await service.retry();
      } else if (boundary == 'dispose') {
        service.dispose();
        disposed = true;
      } else if (boundary == 'auth-event') {
        auth.currentUser = null;
        changes.add(null);
        // No await: invalidation must precede asynchronous store rebinding.
      } else if (boundary == 'account-block') {
        blocked = true;
        await expectLater(
          service.api('/getPlayerState', {}),
          throwsA(isA<LunoApiException>()),
        );
      }
      final before = jsonEncode(store.data.toJson());
      var notifications = 0;
      store.addListener(() => notifications++);
      store.applyServerState(state);
      if (boundary == 'none') {
        expect(store.data.gold, 4321);
        expect(store.data.username, 'first_player');
        expect(notifications, 1);
        await store.flush();
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('luno_player_v1'),
          isNot(contains('_lunoLocal')),
        );
      } else {
        expect(jsonEncode(store.data.toJson()), before);
        expect(notifications, 0);
      }
    });
  }

  test(
    'online notification cannot return success after synchronous switch',
    () async {
      final auth = TestAuth();
      late LunoOnlineService service;
      final client = MockClient((_) async {
        service.lastError = 'temporary-network-error';
        return http.Response('{"ok":true,"state":{"gold":4321}}', 200);
      });
      service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: client,
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();
      service.addListener(() {
        if (service.lastError == null) auth.currentUser = TestUser('second');
      });
      await expectLater(
        service.api('/getPlayerState', {}),
        throwsA(
          isA<LunoApiException>().having(
            (error) => error.code,
            'code',
            'session-changed',
          ),
        ),
      );
    },
  );

  test('refreshState updates the explicitly bound store', () async {
    final store = GameStore.createForTesting();
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      playerStore: store,
      client: MockClient(
        (_) async => http.Response('{"ok":true,"state":{"gold":7654}}', 200),
      ),
      appCheck: () async => 'check',
    );
    addTearDown(() async {
      service.dispose();
      await store.flush();
      store.dispose();
    });
    await service.start();
    await service.refreshState();
    expect(store.data.gold, 7654);
  });
}
