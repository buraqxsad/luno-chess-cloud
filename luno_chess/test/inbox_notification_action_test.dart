import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final scenario in [
    'success',
    'partial',
    'account',
    'disposed',
    'covered',
    'before',
    'details',
  ]) {
    testWidgets('inbox notification action owns its UI: $scenario', (
      tester,
    ) async {
      final auth = TestAuth();
      final pending = Completer<http.Response>();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((_) {
          requests++;
          if (scenario == 'partial' && requests == 2) {
            return Future.value(
              http.Response('{"ok":false,"error":"unavailable"}', 200),
            );
          }
          return pending.future;
        }),
      );
      final streams = List.generate(
        4,
        (_) =>
            StreamController<List<Map<String, dynamic>>>.broadcast(sync: true),
      );
      addTearDown(() async {
        online.dispose();
        for (final stream in streams) {
          await stream.close();
        }
      });
      await online.start();
      online.bindActivityStreamsForTesting(
        streams.map((s) => s.stream).toList(),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: InboxScreen(online: online),
        ),
      );
      await tester.pumpAndSettle();
      // Inject snapshots after the widget's guarded Firebase connection attempt.
      // This test exercises UI actions, not RTDB initialization or transport.
      final dynamic state = tester.state(find.byType(InboxScreen));
      state.setState(() {
        state.notificationStream = streams[0].stream;
        state.inboxStream = streams[1].stream;
        state.error = null;
      });
      await tester.pump();
      streams[0].add([
        {
          'notificationId': 'n1',
          'read': false,
          'type': 'general',
          'message': 'Notification fixture',
        },
        if (scenario == 'partial')
          {
            'notificationId': 'n2',
            'read': false,
            'type': 'general',
            'message': 'Second notification',
          },
      ]);
      streams[1].add([]);
      await tester.pumpAndSettle();
      expect(
        find.byType(LunoStatusDot),
        findsNWidgets(scenario == 'partial' ? 2 : 1),
      );
      final action =
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Tümünü okundu işaretle',
                ),
              )
              .onPressed!;
      if (scenario == 'before') {
        auth.currentUser = TestUser('second');
        action();
        await tester.pumpAndSettle();
        expect(requests, 0);
      } else {
        if (scenario == 'details') {
          await tester.tap(find.text('Notification fixture'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(BottomSheet), findsOneWidget);
        } else {
          action();
          action();
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(requests, 1);
        if (scenario == 'account' || scenario == 'details') {
          auth.currentUser = TestUser('second');
          online.notifyListeners();
          await tester.pumpAndSettle();
          if (scenario == 'details') {
            expect(find.byType(BottomSheet), findsNothing);
          }
        } else if (scenario == 'disposed') {
          await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
        } else if (scenario == 'covered') {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other screen')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        pending.complete(
          http.Response(
            scenario == 'disposed' || scenario == 'covered'
                ? '{"ok":false,"error":"unavailable"}'
                : '{"ok":true,"updated":true}',
            200,
          ),
        );
        await tester.pumpAndSettle();
        if (scenario == 'partial') {
          expect(requests, 2);
          expect(online.unreadNotificationCount, 1);
          expect(find.byType(LunoStatusDot), findsOneWidget);
          expect(
            find.text('Bildirimler şu an işaretlenemedi.'),
            findsOneWidget,
          );
        } else if (scenario == 'success') {
          expect(online.unreadNotificationCount, 0);
          expect(find.byType(LunoStatusDot), findsNothing);
          // No fresh RTDB snapshot: local confirmation must keep the tile read.
          expect(find.text('Notification fixture'), findsOneWidget);
        } else if (scenario == 'covered') {
          expect(find.text('Other screen'), findsOneWidget);
        } else if (scenario == 'disposed') {
          expect(find.text('Replacement'), findsOneWidget);
        } else {
          expect(find.byType(LunoStatusDot), findsOneWidget);
        }
        if (scenario != 'partial') {
          expect(find.text('Bildirimler şu an işaretlenemedi.'), findsNothing);
        }
        expect(find.text('Bildirim okunamadı.'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
