import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth;

void main() {
  test('receipt sends the observed message ID to the server', () async {
    Map<String, dynamic>? body;
    final online = LunoOnlineService.forTesting(
      auth: TestAuth(),
      bootstrap: () async {},
      appCheck: () async => 'check',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true,"marked":true}', 200);
      }),
    );
    addTearDown(online.dispose);
    await online.start();
    await online.markDirectMessageRead('other', lastMessageId: 'message_123');
    expect(body, {'targetUid': 'other', 'lastMessageId': 'message_123'});
  });

  test(
    'legacy receipt omits absent cursor instead of sending explicit null',
    () async {
      Map<String, dynamic>? body;
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true,"marked":false}', 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await online.markDirectMessageRead('other');
      expect(body, {'targetUid': 'other'});
    },
  );

  for (final invalid in ['', '../message', 'a' * 129, 'bad.id']) {
    test(
      'invalid receipt cursor $invalid is rejected before dispatch',
      () async {
        var requests = 0;
        final online = LunoOnlineService.forTesting(
          auth: TestAuth(),
          bootstrap: () async {},
          appCheck: () async => 'check',
          client: MockClient((_) async {
            requests++;
            return http.Response('{"ok":true}', 200);
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        await expectLater(
          online.markDirectMessageRead('other', lastMessageId: invalid),
          throwsFormatException,
        );
        expect(requests, 0);
      },
    );
  }
}
