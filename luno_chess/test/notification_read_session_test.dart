import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final scenario in [
    'updated',
    'removed',
    'rejected',
    'malformed',
    'account',
  ]) {
    test('notification read requires owned confirmation: $scenario', () async {
      final auth = TestAuth();
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((_) {
          requests++;
          entered.complete();
          return response.future;
        }),
      );
      final streams = List.generate(
        4,
        (_) =>
            StreamController<List<Map<String, dynamic>>>.broadcast(sync: true),
      );
      addTearDown(() async {
        service.dispose();
        for (final stream in streams) {
          await stream.close();
        }
      });
      await service.start();
      service.bindActivityStreamsForTesting(
        streams.map((s) => s.stream).toList(),
      );
      streams[0].add([
        {'notificationId': 'n1', 'read': false},
      ]);
      final first = service.markNotificationRead('n1');
      final duplicate = service.markNotificationRead(' n1 ');
      expect(identical(first, duplicate), isTrue);
      await entered.future;
      expect(requests, 1);
      if (scenario == 'account') {
        auth.currentUser = TestUser('second');
        service.bindActivityStreamsForTesting(
          streams.map((s) => s.stream).toList(),
        );
        streams[0].add([
          {'notificationId': 'n1', 'read': false},
        ]);
      }
      final success = scenario == 'updated' || scenario == 'removed';
      final assertion =
          success
              ? expectLater(first, completes)
              : expectLater(
                first,
                throwsA(
                  scenario == 'account' || scenario == 'rejected'
                      ? isA<LunoApiException>()
                      : isA<FormatException>(),
                ),
              );
      response.complete(
        http.Response(
          jsonEncode(switch (scenario) {
            'rejected' => {'ok': false, 'updated': true},
            'malformed' => {'ok': true},
            'removed' => {'ok': true, 'updated': false},
            _ => {'ok': true, 'updated': true},
          }),
          200,
        ),
      );
      await assertion;
      expect(service.unreadNotificationCount, success ? 0 : 1);
    });
  }
  for (final scenario in ['normal', 'account-between', 'signout-between']) {
    test('bulk notification read keeps original owner: $scenario', () async {
      final auth = TestAuth();
      final ids = <String>[];
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          ids.add(
            (jsonDecode(request.body) as Map)['notificationId'] as String,
          );
          return http.Response('{"ok":true,"updated":true}', 200);
        }),
      );
      final streams = List.generate(
        4,
        (_) =>
            StreamController<List<Map<String, dynamic>>>.broadcast(sync: true),
      );
      addTearDown(() async {
        service.dispose();
        for (final stream in streams) {
          await stream.close();
        }
      });
      await service.start();
      service.bindActivityStreamsForTesting(
        streams.map((s) => s.stream).toList(),
      );
      streams[0].add([
        {'notificationId': 'n1', 'read': false},
        {'notificationId': 'n1', 'read': false},
        {'notificationId': 'n2', 'read': false},
        {'notificationId': 'already', 'read': true},
      ]);
      var changed = false;
      service.addListener(() {
        if (scenario == 'normal' ||
            changed ||
            service.unreadNotificationCount != 1) {
          return;
        }
        changed = true;
        auth.currentUser =
            scenario == 'account-between' ? TestUser('second') : null;
      });
      if (scenario == 'normal') {
        await service.markAllNotificationsRead();
        expect(ids, ['n1', 'n2']);
        expect(service.unreadNotificationCount, 0);
      } else {
        await expectLater(
          service.markAllNotificationsRead(),
          throwsA(
            isA<LunoApiException>().having(
              (e) => e.code,
              'code',
              'session-changed',
            ),
          ),
        );
        expect(ids, ['n1']);
        expect(changed, isTrue);
      }
    });
  }
  test('failed notification read can retry with a fresh request', () async {
    var requests = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      appCheck: () async => 'check',
      client: MockClient((_) async {
        requests++;
        return http.Response(
          requests == 1 ? '{"ok":false}' : '{"ok":true,"updated":true}',
          200,
        );
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await expectLater(
      service.markNotificationRead('n1'),
      throwsA(isA<LunoApiException>()),
    );
    await service.markNotificationRead('n1');
    expect(requests, 2);
  });
  test(
    'same notification id on a new account never joins the old request',
    () async {
      final auth = TestAuth();
      final pending = <Completer<http.Response>>[];
      final entered = StreamController<int>.broadcast();
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((_) {
          final response = Completer<http.Response>();
          pending.add(response);
          entered.add(pending.length);
          return response.future;
        }),
      );
      addTearDown(() async {
        service.dispose();
        await entered.close();
      });
      await service.start();
      final firstEntered = entered.stream.first;
      final first = service.markNotificationRead('n1');
      await firstEntered;
      auth.currentUser = TestUser('second');
      final secondEntered = entered.stream.first;
      final second = service.markNotificationRead('n1');
      await secondEntered;
      expect(identical(first, second), isFalse);
      final oldAssertion = expectLater(first, throwsA(isA<LunoApiException>()));
      pending[0].complete(http.Response('{"ok":true,"updated":true}', 200));
      pending[1].complete(http.Response('{"ok":true,"updated":true}', 200));
      await oldAssertion;
      await second;
      expect(pending, hasLength(2));
    },
  );
}
