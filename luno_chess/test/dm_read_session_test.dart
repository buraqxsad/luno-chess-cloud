import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final scenario in [
    'account-delay',
    'account-request',
    'target-delay',
    'retry-limit',
    'success',
  ]) {
    testWidgets('DM read timer respects $scenario', (tester) async {
      final auth = TestAuth();
      final firstRead = Completer<http.Response>();
      final reads = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) {
          if (!request.url.path.endsWith('/markDirectMessageRead')) {
            return Future.value(
              http.Response('{"ok":false,"error":"unavailable"}', 200),
            );
          }
          reads.add((jsonDecode(request.body) as Map)['targetUid'] as String);
          return reads.length == 1
              ? firstRead.future
              : Future.value(
                http.Response('{"ok":false,"error":"unavailable"}', 200),
              );
        }),
      );
      final rows = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      addTearDown(() async {
        online.dispose();
        await rows.close();
      });
      Widget app(String target) => MaterialApp(
        theme: LunoTheme.dark,
        home: DirectMessageScreen(
          targetUid: target,
          targetName: target,
          online: online,
        ),
      );
      await online.start();
      await tester.pumpWidget(app('first-target'));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(DirectMessageScreen));
      state.setState(() {
        state.messagesStream = rows.stream;
        state.error = null;
      });
      await tester.pump();
      final snapshot = [
        {'messageId': 'm1', 'ts': 123, 'from': 'first-target', 'text': 'Hello'},
      ];
      rows.add(snapshot);
      await tester.pump();
      if (scenario == 'account-delay') {
        auth.currentUser = TestUser('second');
        await tester.pump(const Duration(milliseconds: 300));
        expect(reads, isEmpty);
      } else if (scenario == 'target-delay') {
        await tester.pumpWidget(app('second-target'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(reads, isEmpty);
      } else {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(reads, ['first-target']);
        if (scenario == 'account-request') {
          auth.currentUser = TestUser('second');
        }
        firstRead.complete(
          http.Response(
            scenario == 'success'
                ? '{"ok":true,"marked":true}'
                : '{"ok":false,"error":"unavailable"}',
            200,
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2100));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(reads.length, scenario == 'retry-limit' ? 2 : 1);
        if (scenario == 'success') {
          rows.add(snapshot);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(reads, hasLength(1));
        }
      }
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    });
  }
}
