import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

Future<List<Map<String, dynamic>>> load(
  LunoOnlineService service,
  String kind,
) => switch (kind) {
  'messages' => service.directMessages('other'),
  'requests' => service.friendRequests(),
  _ => service.friends(),
};

Object fixture(String path) {
  if (path.startsWith('dm/')) {
    return {
      'm': {'from': 'other', 'text': 'hello', 'ts': 1},
    };
  }
  if (path.startsWith('friendRequests/')) {
    return {
      'other': {'fromName': 'Other', 'sentAt': 1},
    };
  }
  if (path.startsWith('friends/')) return {'other': true};
  return {'username': 'Other', 'trophies': 30};
}

Matcher errorCode(String code) =>
    isA<LunoApiException>().having((error) => error.code, 'code', code);

void main() {
  for (final kind in ['messages', 'requests', 'friends']) {
    for (final change in ['none', 'account', 'signout', 'retry', 'dispose']) {
      test('$kind response respects $change session boundary', () async {
        final auth = TestAuth();
        final entered = Completer<void>();
        final response = Completer<Object?>();
        final paths = <String>[];
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          databaseRead: (path) async {
            paths.add(path);
            if (paths.length == 1) {
              entered.complete();
              return response.future;
            }
            return fixture(path);
          },
        );
        if (change != 'dispose') addTearDown(service.dispose);
        await service.start();
        final pending = load(service, kind);
        await entered.future;
        if (change == 'account') auth.currentUser = TestUser('second');
        if (change == 'signout') auth.currentUser = null;
        if (change == 'retry') await service.retry();
        if (change == 'dispose') service.dispose();
        final assertion =
            change == 'none'
                ? expectLater(pending, completion(hasLength(1)))
                : expectLater(pending, throwsA(errorCode('session-changed')));
        response.complete(fixture(paths.first));
        await assertion;
        expect(paths.first, contains('first'));
        expect(paths.length, kind == 'friends' && change == 'none' ? 2 : 1);
        expect(service.lastError, isNull);
      });
    }

    test('$kind signed-out read cannot fall back to cached user', () async {
      final auth = TestAuth();
      var reads = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        databaseRead: (_) async {
          reads++;
          return null;
        },
      );
      addTearDown(service.dispose);
      await service.start();
      auth.currentUser = null;
      await expectLater(
        load(service, kind),
        throwsA(errorCode('auth-required')),
      );
      expect(reads, 0);
    });

    test('$kind change before dispatch prevents the read', () async {
      final auth = TestAuth();
      var reads = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        databaseRead: (_) async {
          reads++;
          return null;
        },
      );
      addTearDown(service.dispose);
      await service.start();
      final pending = load(service, kind);
      auth.currentUser = TestUser('second');
      await expectLater(pending, throwsA(errorCode('session-changed')));
      expect(reads, 0);
    });
  }

  for (final failed in [false, true]) {
    test(
      'friend profile fan-out rejects old-session ${failed ? 'error' : 'data'}',
      () async {
        final auth = TestAuth();
        final entered = Completer<void>();
        final profile = Completer<Object?>();
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          databaseRead: (path) async {
            if (path.startsWith('friends/')) return {'other': true};
            entered.complete();
            return profile.future;
          },
        );
        addTearDown(service.dispose);
        await service.start();
        final pending = service.friends();
        await entered.future;
        auth.currentUser = TestUser('second');
        final assertion = expectLater(
          pending,
          throwsA(errorCode('session-changed')),
        );
        if (failed) {
          profile.completeError(StateError('old connection failed'));
        } else {
          profile.complete({'username': 'Other'});
        }
        await assertion;
        expect(service.lastError, isNull);
      },
    );
  }
}
