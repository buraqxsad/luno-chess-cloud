import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  test(
    'HTTP retries keep both request identity and serialized payload',
    () async {
      final payload = <String, dynamic>{
        'intent': <String, dynamic>{'type': 'move', 'uci': 'e2e4'},
      };
      final bodies = <String>[];
      final ids = <String?>[];
      final client = MockClient((request) async {
        bodies.add(request.body);
        ids.add(request.headers['X-Luno-Request-Id']);
        if (bodies.length == 1) {
          (payload['intent'] as Map)['uci'] = 'd2d4';
          return http.Response('{"ok":false,"error":"unavailable"}', 503);
        }
        return http.Response('{"ok":true}', 200);
      });
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        client: client,
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();

      await service.api('/submitBattleV1Action', payload);

      expect(bodies, hasLength(2));
      expect(bodies[1], bodies[0]);
      expect((jsonDecode(bodies[0])['intent'] as Map)['uci'], 'e2e4');
      expect(ids.first, isNotNull);
      expect(ids[1], ids[0]);
    },
  );

  for (final body in ['[]', 'null', 'true', '{}', '{"ok":"true"}']) {
    test('HTTP 200 requires an object with explicit ok=true: $body', () async {
      var calls = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        client: MockClient((_) async {
          calls++;
          return http.Response(body, 200);
        }),
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();

      await expectLater(
        service.api('/mutation', {}),
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'invalid-server-response',
          ),
        ),
      );
      expect(calls, 1);
      expect(service.accountFailure, isNull);
    });
  }

  for (final change in ['account', 'signout', 'same-uid', 'dispose']) {
    test('private streams redact late data and errors after $change', () async {
      final auth = TestAuth();
      final authEvents = StreamController<User?>.broadcast(sync: true);
      final source = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        authChanges: authEvents.stream,
        friendRequestStream: source.stream,
        matchInviteStream: source.stream,
        directMessageStream: (_) => source.stream,
      );
      await service.start();
      final received = List.generate(3, (_) => <List<Map<String, dynamic>>>[]);
      final errors = <Object>[];
      final streams = [
        service.directMessagesStream('other'),
        service.friendRequestsStream(),
        service.matchInvitesStream(),
      ];
      final subscriptions = [
        for (var i = 0; i < streams.length; i++)
          streams[i].listen(received[i].add, onError: errors.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        if (change != 'dispose') service.dispose();
        await source.close();
        await authEvents.close();
      });
      source.add([
        {'private': 'first-account'},
      ]);
      expect(
        received.every(
          (rows) => rows.single.single['private'] == 'first-account',
        ),
        isTrue,
      );
      source.addError(StateError('current-account-error'));
      expect(errors, hasLength(3));
      errors.clear();

      if (change == 'dispose') {
        service.dispose();
      } else {
        auth.currentUser = change == 'account' ? TestUser('second') : null;
        authEvents.add(auth.currentUser);
        if (change == 'same-uid') {
          auth.currentUser = TestUser('first');
          authEvents.add(auth.currentUser);
        }
        await Future<void>.delayed(Duration.zero);
      }
      source.add([
        {'private': 'late-first-account'},
      ]);
      source.addError(StateError('old-account-error'));

      expect(received.every((rows) => rows.last.isEmpty), isTrue);
      expect(errors, isEmpty);
    });
  }

  test('signed-out stream overrides cannot bypass account checks', () async {
    final auth = TestAuth()..currentUser = null;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth,
      friendRequestStream: Stream.value([
        {'private': true},
      ]),
      matchInviteStream: Stream.value([
        {'private': true},
      ]),
      directMessageStream:
          (_) => Stream.value([
            {'private': true},
          ]),
    );
    addTearDown(service.dispose);
    expect(await service.friendRequestsStream().first, isEmpty);
    expect(await service.matchInvitesStream().first, isEmpty);
    expect(await service.directMessagesStream('other').first, isEmpty);
  });

  for (final stage in ['token', 'app-check']) {
    testWidgets(
      'stalled $stage acquisition has bounded retries without replacing auth',
      (tester) async {
        final stalled = Completer<String?>();
        final auth =
            TestAuth()
              ..currentUser = TestUser(
                'first',
                token: stage == 'token' ? stalled.future : null,
              );
        var requests = 0;
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          client: MockClient((_) async {
            requests++;
            return http.Response('{"ok":true}', 200);
          }),
          appCheck:
              () =>
                  stage == 'app-check' ? stalled.future : Future.value('check'),
        );
        addTearDown(service.dispose);
        await service.start();
        final assertion = expectLater(
          service.api('/submitBattleV1Action', {}),
          throwsA(isA<TimeoutException>()),
        );
        await tester.pump();
        for (var attempt = 0; attempt < 3; attempt++) {
          await tester.pump(const Duration(seconds: 12));
          await tester.pump();
          if (attempt < 2) {
            await tester.pump(Duration(milliseconds: 500 * (attempt + 1)));
            await tester.pump();
          }
        }
        await assertion;
        expect(requests, 0);
        expect(service.user?.uid, 'first');
        expect(service.accountFailure, isNull);
      },
    );
  }
}
