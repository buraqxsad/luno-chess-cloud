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

http.Response _ack(bool marked) =>
    http.Response(jsonEncode({'ok': true, 'marked': marked}), 200);

class _Conversation {
  _Conversation(
    FutureOr<http.Response> Function(int attempt, Map<String, dynamic> body)
    acknowledge,
  ) {
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
        expect(request.url.path.endsWith('/markDirectMessageRead'), isTrue);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        receipts.add(body);
        return acknowledge(receipts.length, body);
      }),
    );
  }

  final auth = TestAuth();
  final messages = StreamController<List<Map<String, dynamic>>>.broadcast(
    sync: true,
  );
  final navigator = GlobalKey<NavigatorState>();
  final receipts = <Map<String, dynamic>>[];
  late final LunoOnlineService online;

  Widget app({String targetUid = 'target'}) => MaterialApp(
    navigatorKey: navigator,
    theme: LunoTheme.dark,
    home: DirectMessageScreen(
      targetUid: targetUid,
      targetName: targetUid,
      online: online,
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    setLifecycle(tester, AppLifecycleState.resumed);
    await online.start();
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> emit(
    WidgetTester tester, {
    String messageId = 'message_1',
    String targetUid = 'target',
  }) async {
    messages.add([
      {
        'messageId': messageId,
        'from': targetUid,
        'text': 'Observed message',
        'ts': 1,
      },
    ]);
    await tester.pump();
  }

  Future<void> advance(WidgetTester tester, Duration duration) async {
    await tester.pump(duration);
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }

  Future<void> dispose() async {
    online.dispose();
    await messages.close();
  }
}

void main() {
  for (final marked in [false, true]) {
    test('DM read service returns the server marked=$marked outcome', () async {
      Map<String, dynamic>? sent;
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return _ack(marked);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      expect(
        await online.markDirectMessageRead(
          'target',
          lastMessageId: 'message_1',
        ),
        marked,
      );
      expect(sent, {'targetUid': 'target', 'lastMessageId': 'message_1'});
    });
  }

  final malformed = <Map<String, dynamic>>[
    {'ok': true},
    {'ok': true, 'marked': null},
    {'ok': true, 'marked': 'true'},
    {'ok': true, 'marked': 1},
    {'ok': true, 'marked': {}},
  ];
  for (var index = 0; index < malformed.length; index++) {
    final response = malformed[index];
    test('DM read rejects malformed acknowledgement $index', () async {
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        client: MockClient(
          (_) async => http.Response(jsonEncode(response), 200),
        ),
      );
      addTearDown(online.dispose);
      await online.start();
      await expectLater(
        online.markDirectMessageRead('target', lastMessageId: 'message_1'),
        throwsFormatException,
      );
    });
  }

  for (final marked in [false, true]) {
    test('late marked=$marked cannot cross an account switch', () async {
      final auth = TestAuth();
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {},
        appCheck: () async => 'check',
        client: MockClient((_) {
          entered.complete();
          return response.future;
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      final operation = online.markDirectMessageRead(
        'target',
        lastMessageId: 'message_1',
      );
      await entered.future;
      auth.currentUser = TestUser('second');
      final assertion = expectLater(
        operation,
        throwsA(
          isA<LunoApiException>().having(
            (error) => error.code,
            'code',
            'session-changed',
          ),
        ),
      );
      response.complete(_ack(marked));
      await assertion;
    });
  }

  testWidgets('marked false retries before true acknowledges the snapshot', (
    tester,
  ) async {
    final conversation = _Conversation((attempt, _) => _ack(attempt > 1));
    addTearDown(conversation.dispose);
    await conversation.mount(tester);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(1));
    await conversation.advance(tester, const Duration(milliseconds: 1900));
    expect(conversation.receipts, hasLength(1));
    await conversation.advance(tester, const Duration(milliseconds: 200));
    expect(conversation.receipts, hasLength(2));
    expect(conversation.receipts.map((body) => body['lastMessageId']), [
      'message_1',
      'message_1',
    ]);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(seconds: 4));
    expect(conversation.receipts, hasLength(2));
    await conversation.unmount(tester);
  });

  testWidgets('two false results remain eligible without an automatic loop', (
    tester,
  ) async {
    final conversation = _Conversation((attempt, _) => _ack(attempt > 2));
    addTearDown(conversation.dispose);
    await conversation.mount(tester);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    await conversation.advance(tester, const Duration(milliseconds: 2100));
    expect(conversation.receipts, hasLength(2));
    await conversation.advance(tester, const Duration(seconds: 10));
    expect(conversation.receipts, hasLength(2));
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(3));
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(seconds: 3));
    expect(conversation.receipts, hasLength(3));
    await conversation.unmount(tester);
  });

  testWidgets('an in-flight false result yields to the newest message cursor', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    final conversation = _Conversation((attempt, _) async {
      if (attempt == 1) return first.future;
      return _ack(true);
    });
    addTearDown(conversation.dispose);
    await conversation.mount(tester);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(1));
    await conversation.emit(tester, messageId: 'message_2');
    first.complete(_ack(false));
    await tester.pump();
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts.map((body) => body['lastMessageId']), [
      'message_1',
      'message_2',
    ]);
    await conversation.emit(tester, messageId: 'message_2');
    await conversation.advance(tester, const Duration(seconds: 3));
    expect(conversation.receipts, hasLength(2));
    await conversation.unmount(tester);
  });

  for (final change in ['account', 'signout', 'target', 'dispose']) {
    testWidgets('false-result retry respects the $change boundary', (
      tester,
    ) async {
      final conversation = _Conversation((_, _) => _ack(false));
      addTearDown(conversation.dispose);
      await conversation.mount(tester);
      await conversation.emit(tester);
      await conversation.advance(tester, const Duration(milliseconds: 300));
      expect(conversation.receipts, hasLength(1));
      switch (change) {
        case 'account':
          conversation.auth.currentUser = TestUser('second');
          conversation.online.notifyListeners();
          break;
        case 'signout':
          conversation.auth.currentUser = null;
          conversation.online.notifyListeners();
          break;
        case 'target':
          await tester.pumpWidget(conversation.app(targetUid: 'other'));
          break;
        case 'dispose':
          await conversation.unmount(tester);
          break;
      }
      await conversation.advance(tester, const Duration(seconds: 3));
      expect(conversation.receipts, hasLength(1));
      await conversation.unmount(tester);
    });
  }

  testWidgets('false-result retry stays eligible after foreground resumes', (
    tester,
  ) async {
    final conversation = _Conversation((attempt, _) => _ack(attempt > 1));
    addTearDown(() async {
      setLifecycle(tester, AppLifecycleState.resumed);
      await conversation.dispose();
    });
    await conversation.mount(tester);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(1));
    setLifecycle(tester, AppLifecycleState.paused);
    await conversation.advance(tester, const Duration(seconds: 3));
    expect(conversation.receipts, hasLength(1));
    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(2));
    await conversation.unmount(tester);
  });

  testWidgets('false-result retry stays eligible after a covered route', (
    tester,
  ) async {
    final conversation = _Conversation((attempt, _) => _ack(attempt > 1));
    addTearDown(conversation.dispose);
    await conversation.mount(tester);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    unawaited(
      conversation.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered route')),
        ),
      ),
    );
    await conversation.advance(tester, const Duration(seconds: 3));
    expect(conversation.receipts, hasLength(1));
    conversation.navigator.currentState!.pop();
    await tester.pump();
    await conversation.advance(tester, const Duration(milliseconds: 500));
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(2));
    await conversation.unmount(tester);
  });

  testWidgets('late true cannot acknowledge the same ID for another target', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    final conversation = _Conversation((attempt, _) async {
      if (attempt == 1) return first.future;
      return _ack(true);
    });
    addTearDown(conversation.dispose);
    await conversation.mount(tester);
    await conversation.emit(tester);
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, hasLength(1));
    await tester.pumpWidget(conversation.app(targetUid: 'other'));
    await tester.pump();
    await conversation.advance(tester, const Duration(milliseconds: 50));
    first.complete(_ack(true));
    await tester.pump();
    await conversation.emit(tester, targetUid: 'other');
    await conversation.advance(tester, const Duration(milliseconds: 300));
    expect(conversation.receipts, [
      {'targetUid': 'target', 'lastMessageId': 'message_1'},
      {'targetUid': 'other', 'lastMessageId': 'message_1'},
    ]);
    await conversation.unmount(tester);
  });
}
