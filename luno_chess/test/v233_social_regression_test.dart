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
import 'v218_social_dm_lifecycle_test.dart' show setLifecycle;

class _FailedReceiptConversation {
  _FailedReceiptConversation() {
    online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
      appCheck: () async => 'check',
      directMessageStream: (_) => messages.stream,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/openDirectMessage')) {
          return http.Response(
            '{"ok":true,"conversationId":"first_target"}',
            200,
          );
        }
        expect(request.url.path, endsWith('/markDirectMessageRead'));
        receipts.add(jsonDecode(request.body) as Map<String, dynamic>);
        return recovered
            ? http.Response('{"ok":true,"marked":true}', 200)
            : http.Response('{"ok":false,"error":"unavailable"}', 503);
      }),
    );
  }

  final auth = TestAuth();
  final messages = StreamController<List<Map<String, dynamic>>>.broadcast(
    sync: true,
  );
  final receipts = <Map<String, dynamic>>[];
  late final LunoOnlineService online;
  bool recovered = false;

  Future<void> advance(WidgetTester tester, Duration duration) async {
    await tester.pump(duration);
    await tester.pump();
  }

  Future<void> emit(WidgetTester tester) async {
    messages.add([
      {
        'messageId': 'visible_message',
        'from': 'target',
        'text': 'Visible message',
        'ts': 1,
      },
    ]);
    await tester.pump();
  }

  Future<void> exhaustRetries(WidgetTester tester) async {
    setLifecycle(tester, AppLifecycleState.resumed);
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
    await advance(tester, const Duration(milliseconds: 50));
    await emit(tester);
    await advance(tester, const Duration(milliseconds: 300));
    expect(receipts, hasLength(1));

    // Each UI attempt contains the service's three HTTP attempts.
    await advance(tester, const Duration(milliseconds: 500));
    await advance(tester, const Duration(seconds: 1));
    expect(receipts, hasLength(3));
    await advance(tester, const Duration(seconds: 2));
    await advance(tester, const Duration(milliseconds: 500));
    await advance(tester, const Duration(seconds: 1));
    expect(receipts, hasLength(6));

    for (var index = 0; index < 2; index++) {
      await emit(tester);
      await advance(tester, const Duration(seconds: 5));
    }
    expect(receipts, hasLength(6));
  }

  Future<void> dispose() async {
    online.dispose();
    await messages.close();
  }
}

void main() {
  testWidgets('foreground resume retries an exhausted DM read snapshot', (
    tester,
  ) async {
    final conversation = _FailedReceiptConversation();
    addTearDown(() async {
      setLifecycle(tester, AppLifecycleState.resumed);
      await conversation.dispose();
    });
    await conversation.exhaustRetries(tester);
    conversation.recovered = true;
    setLifecycle(tester, AppLifecycleState.paused);
    await conversation.advance(tester, const Duration(seconds: 3));
    expect(conversation.receipts, hasLength(6));

    // No new stream event: resume must revisit the already visible message.
    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(7));
    expect(conversation.receipts.last, {
      'targetUid': 'target',
      'lastMessageId': 'visible_message',
    });
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(seconds: 5));
    expect(conversation.receipts, hasLength(7));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground read recovery cannot cross an account switch', (
    tester,
  ) async {
    final conversation = _FailedReceiptConversation();
    addTearDown(() async {
      setLifecycle(tester, AppLifecycleState.resumed);
      await conversation.dispose();
    });
    await conversation.exhaustRetries(tester);
    setLifecycle(tester, AppLifecycleState.paused);
    conversation.recovered = true;
    conversation.auth.currentUser = TestUser('second');
    conversation.online.notifyListeners();
    await tester.pump();
    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    await conversation.advance(tester, const Duration(seconds: 3));
    expect(conversation.receipts, hasLength(6));
    expect(find.text('Visible message'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
