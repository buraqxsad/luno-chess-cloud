import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

http.Response reply(Map<String, dynamic> value, {int status = 200}) =>
    http.Response(jsonEncode(value), status);

http.Response missingProfile() =>
    reply({'ok': false, 'error': 'profile-not-found'}, status: 404);

http.Response serverProfile({
  String name = 'luno_guest',
  int gold = 765,
  bool generated = false,
}) => reply({
  'ok': true,
  'state': {
    'uid': 'first',
    'profile': {
      'username': name,
      'bio': 'server profile',
      'usernameGenerated': generated,
    },
    'gold': gold,
  },
});

Map<String, dynamic> snapshot(GameStore store) => Map<String, dynamic>.from(
  jsonDecode(
        jsonEncode({
          'data': store.data.toJson(),
          'chosen': store.hasChosenUsername,
          'draft': store.pendingUsernameDraft,
          'owner': store.accountUid,
          'revision': store.accountBindingRevision,
          'epoch': store.serverStateEpoch,
        }),
      )
      as Map,
);

Future<(GameStore, TestAuth, LunoOnlineService)> harness(
  Future<http.Response> Function(http.Request) respond, {
  bool pendingDraft = false,
}) async {
  final store = GameStore.createForTesting();
  await store.bindAccount('first');
  await store.chooseUsername('LunoFriend');
  if (pendingDraft) {
    await store.requireUsernamePublication(
      'first',
      store.accountBindingRevision,
      store.data.username,
    );
  }
  final auth = TestAuth();
  final client = MockClient((request) async {
    expect(request.method, 'POST');
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(request.headers['X-Firebase-AppCheck'], 'check');
    expect(request.headers['X-Luno-Request-Id'], isNotEmpty);
    // No bootstrap request can publish the chosen name or fabricate consent.
    expect(jsonDecode(request.body), <String, dynamic>{});
    return respond(request);
  });
  final service = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: auth,
    playerStore: store,
    client: client,
    appCheck: () async => 'check',
  );
  addTearDown(() async {
    service.dispose();
    client.close();
    await store.flush();
    store.dispose();
  });
  await service.start();
  return (store, auth, service);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final pending in [false, true]) {
    for (final created in [false, true]) {
      test(
        'generated alias with created=$created preserves ${pending ? 'pending' : 'chosen local'} name as unpublished draft',
        () async {
          final paths = <String>[];
          var reads = 0;
          final (store, _, service) = await harness((request) async {
            final path = request.url.path.split('/').last;
            paths.add(path);
            if (path == 'getPlayerState') {
              return ++reads == 1
                  ? missingProfile()
                  : serverProfile(generated: true);
            }
            expect(path, 'createGuestPlayer');
            return reply({
              'ok': true,
              'uid': 'first',
              'created': created,
              'usernameGenerated': true,
            });
          }, pendingDraft: pending);
          expect(store.hasChosenUsername, !pending);
          expect(store.pendingUsernameDraft, pending ? 'lunofriend' : '');
          await service.ensureRemoteProfileForTesting();
          expect(paths, [
            'getPlayerState',
            'createGuestPlayer',
            'getPlayerState',
          ]);
          expect(store.accountUid, 'first');
          expect(store.hasChosenUsername, false);
          expect(store.pendingUsernameDraft, 'lunofriend');
          expect(store.data.username, 'luno_guest');
          expect(store.data.gold, 765);
          expect(store.data.bio, 'server profile');
          await store.flush();
          final restored = GameStore.createForTesting();
          addTearDown(restored.dispose);
          await restored.load();
          expect(restored.accountUid, 'first');
          expect(restored.hasChosenUsername, false);
          expect(restored.pendingUsernameDraft, 'lunofriend');
          expect(restored.data.username, 'luno_guest');
        },
      );

      test(
        'published name with created=$created preserves ${pending ? 'pending draft' : 'chosen identity'} without reprompt',
        () async {
          final paths = <String>[];
          var reads = 0;
          final (store, _, service) = await harness((request) async {
            final path = request.url.path.split('/').last;
            paths.add(path);
            if (path == 'getPlayerState') {
              return ++reads == 1
                  ? missingProfile()
                  : serverProfile(name: 'lunofriend');
            }
            expect(path, 'createGuestPlayer');
            return reply({
              'ok': true,
              'uid': 'first',
              'created': created,
              'usernameGenerated': false,
            });
          }, pendingDraft: pending);
          await service.ensureRemoteProfileForTesting();
          expect(paths, [
            'getPlayerState',
            'createGuestPlayer',
            'getPlayerState',
          ]);
          expect(store.hasChosenUsername, !pending);
          expect(store.pendingUsernameDraft, pending ? 'lunofriend' : '');
          expect(store.data.username, 'lunofriend');
          await store.flush();
          final restored = GameStore.createForTesting();
          addTearDown(restored.dispose);
          await restored.load();
          expect(restored.hasChosenUsername, !pending);
          expect(restored.pendingUsernameDraft, pending ? 'lunofriend' : '');
          expect(restored.data.username, 'lunofriend');
        },
      );
    }
  }

  for (final pending in [false, true]) {
    test(
      'successful generated-profile refresh captures ${pending ? 'pending' : 'chosen'} name before applying alias',
      () async {
        final paths = <String>[];
        final (store, _, service) = await harness((request) async {
          paths.add(request.url.path.split('/').last);
          return serverProfile(generated: true);
        }, pendingDraft: pending);
        await service.ensureRemoteProfileForTesting();
        expect(paths, ['getPlayerState']);
        expect(store.hasChosenUsername, false);
        expect(store.pendingUsernameDraft, 'lunofriend');
        expect(store.data.username, 'luno_guest');
        await service.ensureRemoteProfileForTesting();
        expect(paths, ['getPlayerState', 'getPlayerState']);
        expect(store.pendingUsernameDraft, 'lunofriend');
        expect(store.hasChosenUsername, false);
        await store.flush();
      },
    );
  }

  test(
    'existing profile never calls guest creation or changes chosen consent state',
    () async {
      final paths = <String>[];
      final (store, _, service) = await harness((request) async {
        paths.add(request.url.path.split('/').last);
        return serverProfile(name: 'lunofriend');
      });
      await service.ensureRemoteProfileForTesting();
      expect(paths, ['getPlayerState']);
      expect(store.hasChosenUsername, true);
      expect(store.pendingUsernameDraft, isEmpty);
      expect(store.data.username, 'lunofriend');
    },
  );

  for (final uid in <Object?>['second', null]) {
    test(
      'created=true for mismatched uid $uid cannot clear the current chosen name',
      () async {
        var reads = 0;
        final (store, _, service) = await harness((request) async {
          if (request.url.path.endsWith('/getPlayerState')) {
            return ++reads == 1
                ? missingProfile()
                : serverProfile(name: 'lunofriend');
          }
          expect(request.url.path.endsWith('/createGuestPlayer'), true);
          return reply({
            'ok': true,
            'uid': uid,
            'created': true,
            'usernameGenerated': true,
          });
        });
        await service.ensureRemoteProfileForTesting();
        expect(store.hasChosenUsername, true);
        expect(store.pendingUsernameDraft, isEmpty);
        expect(store.data.username, 'lunofriend');
      },
    );
  }

  for (final marker in <Object?>[null, 'true', 1]) {
    test(
      'created=true without a strict generated marker $marker cannot reprompt',
      () async {
        var reads = 0;
        final (store, _, service) = await harness((request) async {
          if (request.url.path.endsWith('/getPlayerState')) {
            return ++reads == 1
                ? missingProfile()
                : serverProfile(name: 'lunofriend');
          }
          return reply({
            'ok': true,
            'uid': 'first',
            'created': true,
            if (marker != null) 'usernameGenerated': marker,
          });
        });
        await service.ensureRemoteProfileForTesting();
        expect(store.hasChosenUsername, true);
        expect(store.pendingUsernameDraft, isEmpty);
      },
    );
  }

  for (final stage in ['lookup', 'create', 'refresh']) {
    for (final boundary in ['account', 'store-only', 'same-uid-rebound']) {
      test(
        'stale $stage response cannot mutate state or draft after $boundary',
        () async {
          final entered = Completer<void>();
          final pending = Completer<http.Response>();
          final paths = <String>[];
          var reads = 0;
          final (store, auth, service) = await harness((request) async {
            final path = request.url.path.split('/').last;
            paths.add(path);
            final phase =
                path == 'createGuestPlayer'
                    ? 'create'
                    : ++reads == 1
                    ? 'lookup'
                    : 'refresh';
            if (phase == stage) {
              entered.complete();
              return pending.future;
            }
            if (phase == 'lookup') return missingProfile();
            if (phase == 'create') {
              return reply({
                'ok': true,
                'uid': 'first',
                'created': true,
                'usernameGenerated': true,
              });
            }
            return serverProfile(generated: true);
          });
          final operation = service.ensureRemoteProfileForTesting();
          await entered.future.timeout(const Duration(seconds: 3));
          if (boundary == 'account') auth.currentUser = TestUser('second');
          await store.bindAccount('second');
          if (boundary == 'same-uid-rebound') await store.bindAccount('first');
          final owner = store.accountUid!;
          await store.chooseUsername('NextOwner');
          await store.requireUsernamePublication(
            owner,
            store.accountBindingRevision,
            'NextOwnerDraft',
          );
          store.data.gold = 321;
          store.data.gems = 654;
          store.data.bio = 'next owner private bio';
          await store.save();
          await store.flush();
          final before = snapshot(store);
          final prefs = await SharedPreferences.getInstance();
          final diskBefore = prefs.getString('luno_player_v1');
          final assertion = expectLater(
            operation,
            throwsA(
              isA<LunoApiException>().having(
                (e) => e.code,
                'code',
                'session-changed',
              ),
            ),
          );
          pending.complete(switch (stage) {
            'lookup' => missingProfile(),
            'create' => reply({
              'ok': true,
              'uid': 'first',
              'created': true,
              'usernameGenerated': true,
            }),
            _ => serverProfile(
              name: 'stale_owner',
              gold: 999999,
              generated: true,
            ),
          });
          await assertion;
          await store.flush();
          expect(snapshot(store), before);
          expect(prefs.getString('luno_player_v1'), diskBefore);
          expect(
            paths.length,
            stage == 'lookup'
                ? 1
                : stage == 'create'
                ? 2
                : 3,
          );
          expect(store.pendingUsernameDraft, 'nextownerdraft');
          expect(store.hasChosenUsername, false);
        },
      );
    }
  }
}
