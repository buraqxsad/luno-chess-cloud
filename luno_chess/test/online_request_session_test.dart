import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';

class TestUser extends Fake implements User {
  TestUser(this.uid, {this.token});
  @override
  final String uid;
  final Future<String?>? token;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      token == null ? 'test-token' : await token;
}

class TestAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = TestUser('first');
}

void main() {
  for (final change in ['none', 'account', 'signout', 'bootstrap']) {
    test('HTTP response respects $change session boundary', () async {
      final auth = TestAuth();
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        entered.complete();
        return response.future;
      });
      addTearDown(client.close);
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: client,
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();
      final result = service.api('/getPlayerState', {});
      await entered.future;
      if (change == 'account') auth.currentUser = TestUser('second');
      if (change == 'signout') auth.currentUser = null;
      if (change == 'bootstrap') await service.retry();
      final assertion =
          change == 'none'
              ? expectLater(result, completion(containsPair('ok', true)))
              : expectLater(
                result,
                throwsA(
                  isA<LunoApiException>().having(
                    (e) => e.code,
                    'code',
                    'session-changed',
                  ),
                ),
              );
      response.complete(http.Response('{"ok":true,"state":{"gold":999}}', 200));
      await assertion;
      expect(requests, 1);
      expect(service.accountFailure, isNull);
      if (change == 'signout') {
        expect(service.user, isNull);
        expect(service.isOnline, isFalse);
      }
    });
  }
  test(
    'account switch during token acquisition prevents HTTP dispatch',
    () async {
      final token = Completer<String?>();
      final auth =
          TestAuth()..currentUser = TestUser('first', token: token.future);
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(client.close);
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: client,
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();
      final result = service.api('/getPlayerState', {});
      await Future<void>.delayed(Duration.zero);
      auth.currentUser = TestUser('second');
      final assertion = expectLater(
        result,
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'session-changed',
          ),
        ),
      );
      token.complete('old-token');
      await assertion;
      expect(requests, 0);
    },
  );
  test(
    'parallel account rejection prevents an older success from escaping',
    () async {
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      final auth = TestAuth();
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('/slow')) {
          entered.complete();
          return pending.future;
        }
        return http.Response('{"ok":false,"error":"account-deleted"}', 403);
      });
      addTearDown(client.close);
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: client,
        appCheck: () async => 'check',
      );
      addTearDown(service.dispose);
      await service.start();
      final old = service.api('/slow', {});
      await entered.future;
      await expectLater(
        service.api('/rejected', {}),
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'account-deleted',
          ),
        ),
      );
      final assertion = expectLater(
        old,
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'account-deleted',
          ),
        ),
      );
      pending.complete(http.Response('{"ok":true}', 200));
      await assertion;
      expect(requests, 2);
      expect(service.ready, isFalse);
      expect(service.accountFailure?.code, 'account-deleted');
    },
  );
}
