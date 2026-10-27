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

List<Map<String, dynamic>> snapshot(int count) => List.generate(
  count,
  (i) => {'messageId': 'm$i', 'ts': i, 'from': 'friend', 'text': 'Message $i'},
);

void main() {
  for (final scenario in [
    'success',
    'failure',
    'opening',
    'account',
    'covered',
    'disposed',
    'target',
    'retry-cap',
  ]) {
    testWidgets('receipt queue serializes $scenario', (tester) async {
      final auth = TestAuth();
      final responses = <Completer<http.Response>>[];
      final targets = <String>[];
      final observedIds = <Object?>[];
      final streams = List.generate(
        2,
        (_) =>
            StreamController<List<Map<String, dynamic>>>.broadcast(sync: true),
      );
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {},
        appCheck: () async => 'check',
        directMessageStream:
            (target) => streams[target == 'friend' ? 0 : 1].stream,
        client: MockClient((request) {
          if (request.url.path.endsWith('/openDirectMessage')) {
            return Future.value(
              http.Response(
                scenario == 'opening'
                    ? '{"ok":true,"conversationId":"conversation"}'
                    : '{"ok":false,"error":"unavailable"}',
                200,
              ),
            );
          }
          targets.add((jsonDecode(request.body) as Map)['targetUid'] as String);
          observedIds.add((jsonDecode(request.body) as Map)['lastMessageId']);
          final response = Completer<http.Response>();
          responses.add(response);
          return response.future;
        }),
      );
      addTearDown(() async {
        online.dispose();
        for (final stream in streams) {
          await stream.close();
        }
      });
      final navigator = GlobalKey<NavigatorState>();
      Widget app(String target) => MaterialApp(
        navigatorKey: navigator,
        theme: LunoTheme.dark,
        home: DirectMessageScreen(
          targetUid: target,
          targetName: target,
          online: online,
        ),
      );
      await online.start();
      await tester.pumpWidget(app('friend'));
      await tester.pump(const Duration(milliseconds: 100));
      final dynamic state = tester.state(find.byType(DirectMessageScreen));
      if (scenario != 'opening') {
        state.setState(() {
          state.error = null;
          state.messagesStream = streams[0].stream;
        });
        await tester.pump();
      }
      streams[0].add(snapshot(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(targets, ['friend']);
      expect(observedIds, ['m0']);
      if (scenario != 'retry-cap') {
        for (final count in [2, 3, 4]) {
          streams[0].add(snapshot(count));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(targets, ['friend']);
        }
      }
      if (scenario == 'account') {
        auth.currentUser = TestUser('second');
      } else if (scenario == 'disposed') {
        await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
      } else if (scenario == 'covered') {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered')),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      } else if (scenario == 'target') {
        await tester.pumpWidget(app('new_friend'));
        await tester.pump(const Duration(milliseconds: 100));
        state.setState(() {
          state.error = null;
          state.messagesStream = streams[1].stream;
        });
        await tester.pump();
        streams[1].add(snapshot(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(targets, ['friend', 'new_friend']);
      }
      responses.first.complete(
        http.Response(
          scenario == 'failure' || scenario == 'retry-cap'
              ? '{"ok":false,"error":"unavailable"}'
              : '{"ok":true}',
          200,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (['account', 'disposed', 'covered'].contains(scenario)) {
        expect(targets, ['friend']);
        if (scenario == 'covered') {
          navigator.currentState!.pop();
          await tester.pump(const Duration(milliseconds: 300));
          state.setState(() {});
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(targets, ['friend', 'friend']);
          responses.last.complete(http.Response('{"ok":true}', 200));
        }
      } else if (scenario == 'target') {
        streams[1].add(snapshot(2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(targets, ['friend', 'new_friend']);
        responses[1].complete(http.Response('{"ok":true}', 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(targets, ['friend', 'new_friend', 'new_friend']);
        responses.last.complete(http.Response('{"ok":true}', 200));
      } else if (scenario == 'retry-cap') {
        await tester.pump(const Duration(seconds: 2));
        expect(targets, ['friend', 'friend']);
        responses.last.complete(
          http.Response('{"ok":false,"error":"unavailable"}', 200),
        );
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          streams[0].add(snapshot(1));
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
        }
        expect(targets, ['friend', 'friend']);
        streams[0].add(snapshot(2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(targets, ['friend', 'friend', 'friend']);
        responses.last.complete(http.Response('{"ok":true}', 200));
      } else {
        expect(targets, ['friend', 'friend']);
        expect(observedIds.last, 'm3');
        responses.last.complete(http.Response('{"ok":true}', 200));
        await tester.pump();
        streams[0].add(snapshot(4));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(targets, ['friend', 'friend']);
      }
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
