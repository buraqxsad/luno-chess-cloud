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

List<Map<String, dynamic>> messages(String id) => [
  {'messageId': id, 'from': 'target', 'text': 'Private message $id', 'ts': 1},
];

void setLifecycle(WidgetTester tester, AppLifecycleState target) {
  final binding = tester.binding;
  if (binding.lifecycleState == target) return;
  if (target == AppLifecycleState.resumed) {
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(target);
    return;
  }
  setLifecycle(tester, AppLifecycleState.resumed);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  if (target == AppLifecycleState.inactive) return;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  if (target == AppLifecycleState.hidden) return;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  if (target == AppLifecycleState.paused) return;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
}

Future<void> mountConversation(
  WidgetTester tester,
  LunoOnlineService online,
) async {
  await online.start();
  await tester.pumpWidget(
    MaterialApp(
      theme: LunoTheme.dark,
      home: DirectMessageScreen(
        targetUid: 'target',
        targetName: 'Target',
        online: online,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('DM receipts wait for foreground after $lifecycle', (
      tester,
    ) async {
      setLifecycle(tester, AppLifecycleState.resumed);
      final stream = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final receipts = <Object?>[];
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        directMessageStream: (_) => stream.stream,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/openDirectMessage')) {
            return http.Response(
              '{"ok":true,"conversationId":"first_target"}',
              200,
            );
          }
          receipts.add((jsonDecode(request.body) as Map)['lastMessageId']);
          return http.Response('{"ok":true,"marked":true}', 200);
        }),
      );
      addTearDown(() async {
        setLifecycle(tester, AppLifecycleState.resumed);
        online.dispose();
        await stream.close();
      });
      await mountConversation(tester, online);
      stream.add(messages('before_background'));
      await tester.pump();
      setLifecycle(tester, lifecycle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(receipts, isEmpty);
      stream.add(messages('during_background'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(receipts, isEmpty);

      setLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(receipts, ['during_background']);
      stream.add(messages('during_background'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(receipts, ['during_background']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final success in [false, true]) {
    testWidgets(
      'in-flight receipt success=$success does not retry in background',
      (tester) async {
        setLifecycle(tester, AppLifecycleState.resumed);
        final stream = StreamController<List<Map<String, dynamic>>>.broadcast(
          sync: true,
        );
        final pending = Completer<http.Response>();
        final receipts = <Object?>[];
        final online = LunoOnlineService.forTesting(
          auth: TestAuth(),
          bootstrap: () async {},
          appCheck: () async => 'check',
          directMessageStream: (_) => stream.stream,
          client: MockClient((request) {
            if (request.url.path.endsWith('/openDirectMessage')) {
              return Future.value(
                http.Response(
                  '{"ok":true,"conversationId":"first_target"}',
                  200,
                ),
              );
            }
            receipts.add((jsonDecode(request.body) as Map)['lastMessageId']);
            return receipts.length == 1
                ? pending.future
                : Future.value(http.Response('{"ok":true,"marked":true}', 200));
          }),
        );
        addTearDown(() async {
          setLifecycle(tester, AppLifecycleState.resumed);
          online.dispose();
          await stream.close();
        });
        await mountConversation(tester, online);
        stream.add(messages('first_message'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(receipts, ['first_message']);
        setLifecycle(tester, AppLifecycleState.paused);
        stream.add(messages('latest_message'));
        await tester.pump();
        pending.complete(
          http.Response(
            success
                ? '{"ok":true,"marked":true}'
                : '{"ok":false,"error":"unavailable"}',
            200,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(receipts, ['first_message']);
        setLifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(receipts, ['first_message', 'latest_message']);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['account', 'signout', 'rejected']) {
    testWidgets('DM removes cached messages and draft after $change', (
      tester,
    ) async {
      setLifecycle(tester, AppLifecycleState.resumed);
      final auth = TestAuth();
      final stream = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      var receipts = 0;
      var sends = 0;
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {},
        appCheck: () async => 'check',
        directMessageStream: (_) => stream.stream,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/openDirectMessage')) {
            return http.Response(
              '{"ok":true,"conversationId":"first_target"}',
              200,
            );
          }
          if (request.url.path.endsWith('/markDirectMessageRead')) receipts++;
          if (request.url.path.endsWith('/sendDirectMessage')) sends++;
          return http.Response('{"ok":false,"error":"account-deleted"}', 403);
        }),
      );
      addTearDown(() async {
        online.dispose();
        await stream.close();
      });
      await mountConversation(tester, online);
      stream.add(messages('secret'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Private draft');
      final submit =
          tester.widget<TextField>(find.byType(TextField)).onSubmitted!;
      final dynamic state = tester.state(find.byType(DirectMessageScreen));
      if (change == 'rejected') {
        await expectLater(
          online.api('/probe', {}),
          throwsA(isA<LunoApiException>()),
        );
        expect(online.accountFailure?.code, 'account-deleted');
      } else {
        auth.currentUser = change == 'account' ? TestUser('second') : null;
        online.notifyListeners();
      }
      await tester.pump();
      expect(state.messagesStream, isNull);
      expect(state.input.text, isEmpty);
      expect(find.text('Private message secret'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      submit('Private draft');
      stream.add(messages('late_old_account'));
      await tester.pump(const Duration(seconds: 3));
      expect(receipts, 0);
      expect(sends, 0);
      expect(find.text('Private message late_old_account'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
