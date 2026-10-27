import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/social_safety_result.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  test('block confirmation binds exact target and requested outcome', () {
    for (final blocked in [true, false]) {
      validateSocialBlockResult(
        {'ok': true, 'targetUid': 'target', 'blocked': blocked},
        targetUid: 'target',
        blocked: blocked,
      );
      for (final result in <Map<String, dynamic>>[
        {},
        {'ok': true},
        {'ok': true, 'targetUid': 'other', 'blocked': blocked},
        {'ok': true, 'targetUid': 'target', 'blocked': !blocked},
        {'ok': false, 'targetUid': 'target', 'blocked': blocked},
      ]) {
        expect(
          () => validateSocialBlockResult(
            result,
            targetUid: 'target',
            blocked: blocked,
          ),
          throwsFormatException,
        );
      }
    }
  });
  test('reports need explicit server confirmation and bounded report ID', () {
    validateSocialReportResult({
      'ok': true,
      'reported': true,
      'reportId': 'rp_valid',
    });
    for (final result in <Map<String, dynamic>>[
      {},
      {'ok': true, 'reported': true},
      {'ok': false, 'reported': true, 'reportId': 'rp_valid'},
      {'ok': true, 'reported': false, 'reportId': 'rp_valid'},
      {'ok': true, 'reported': true, 'reportId': 'rp_bad/path'},
      {'ok': true, 'reported': true, 'reportId': 12},
    ]) {
      expect(() => validateSocialReportResult(result), throwsFormatException);
    }
  });
  test(
    'blocked list permits deleted display names but rejects forged identities',
    () {
      final rows = parseBlockedPlayers({
        'ok': true,
        'results': [
          {
            'uid': 'target',
            'username': '',
            'name': 'Silinmiş oyuncu',
            'private': 'not retained',
          },
        ],
      }, viewerUid: 'first');
      expect(rows.single.uid, 'target');
      expect(rows.single.name, 'Silinmiş oyuncu');
      expect(() => rows.clear(), throwsUnsupportedError);
      for (final users in <Object?>[
        null,
        {},
        [12],
        [
          {'uid': 'first', 'name': 'self', 'blocked': true},
        ],
        [
          {'uid': 'bad/path', 'name': 'bad', 'blocked': true},
        ],
        [
          {'uid': 'target', 'name': 'bad\u202e', 'blocked': true},
        ],
        [
          {'uid': 'target', 'name': ''},
        ],
        [
          {'uid': 'target', 'name': {}, 'blocked': true},
        ],
        List.generate(
          2,
          (_) => {'uid': 'target', 'name': 'duplicate', 'blocked': true},
        ),
        List.generate(
          101,
          (index) => {'uid': 'target$index', 'name': 'name', 'blocked': true},
        ),
      ]) {
        expect(
          () => parseBlockedPlayers({
            'ok': true,
            'results': users,
          }, viewerUid: 'first'),
          throwsFormatException,
        );
      }
    },
  );
  for (final reason in SocialReportReason.values) {
    test(
      'report ${reason.id} sends only server-approved context identifiers',
      () async {
        final sent = <Map<String, dynamic>>[];
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: TestAuth(),
          appCheck: () async => 'check',
          client: MockClient((request) async {
            sent.add(jsonDecode(request.body) as Map<String, dynamic>);
            expect(request.url.path.endsWith('/reportMessage'), isTrue);
            expect(request.headers['X-Luno-Request-Id'], isNotEmpty);
            return http.Response(
              '{"ok":true,"reported":true,"reportId":"rp_test"}',
              200,
            );
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        await online.reportDirectMessage('target', 'message_1', reason);
        expect(sent.single, {
          'targetUid': 'target',
          'messageId': 'message_1',
          'reason': reason.id,
        });
      },
    );
  }
  test(
    'block, unblock and list parse their actual endpoint contracts',
    () async {
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        appCheck: () async => 'check',
        client: MockClient((request) async {
          final path = request.url.path.split('/').last;
          return http.Response(
            jsonEncode(
              path == 'listBlockedUsers'
                  ? {
                    'ok': true,
                    'results': [
                      {'uid': 'target', 'username': 'player', 'blocked': true},
                    ],
                  }
                  : {
                    'ok': true,
                    'targetUid': 'target',
                    'blocked': path == 'blockUser',
                  },
            ),
            200,
          );
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await online.blockPlayer('target');
      await online.unblockPlayer('target');
      expect((await online.blockedPlayers()).single.uid, 'target');
    },
  );
  test('invalid/self targets and message IDs never dispatch', () async {
    var requests = 0;
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      appCheck: () async => 'check',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(online.dispose);
    await online.start();
    for (final target in ['', 'bad/path', 'first', 'x' * 129]) {
      await expectLater(online.blockPlayer(target), throwsFormatException);
      await expectLater(online.unblockPlayer(target), throwsFormatException);
      await expectLater(
        online.reportPlayer(target, SocialReportReason.spam),
        throwsFormatException,
      );
    }
    await expectLater(
      online.reportDirectMessage('target', 'bad/path', SocialReportReason.spam),
      throwsFormatException,
    );
    expect(requests, 0);
  });
  for (final scenario in ['response', 'bootstrap']) {
    test('account switch during $scenario rejects safety action', () async {
      final auth = TestAuth();
      final entered = Completer<void>();
      final wait = Completer<void>();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {
          if (scenario == 'bootstrap') {
            entered.complete();
            await wait.future;
          }
        },
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((_) async {
          requests++;
          if (scenario == 'response') {
            entered.complete();
            await wait.future;
          }
          return http.Response(
            '{"ok":true,"targetUid":"target","blocked":true}',
            200,
          );
        }),
      );
      addTearDown(online.dispose);
      if (scenario == 'response') await online.start();
      final operation = online.blockPlayer('target');
      await entered.future;
      auth.currentUser = TestUser('second');
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
      wait.complete();
      await assertion;
      expect(requests, scenario == 'bootstrap' ? 0 : 1);
    });
  }
}
