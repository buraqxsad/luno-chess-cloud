import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/initial_stream_timeout.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'inbox_connection_resilience_test.dart' show app;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  for (final language in ['tr', 'en']) {
    for (final tab in [0, 1]) {
      for (final size in [
        const Size(320, 568),
        const Size(568, 320),
        const Size(800, 1280),
      ]) {
        testWidgets('inbox first snapshot recovery $language tab=$tab $size', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final online = LunoOnlineService.forTesting(
            auth: TestAuth(),
            bootstrap: () async {},
          );
          final source = StreamController<List<Map<String, dynamic>>>.broadcast(
            sync: true,
          );
          var cancelled = false;
          source.onCancel = () => cancelled = true;
          addTearDown(() async {
            online.dispose();
            await source.close();
          });
          await online.start();
          await tester.pumpWidget(app(online, language));
          await tester.pumpAndSettle();
          // Controlled streams exercise the same wrapper used by _connect.
          final dynamic state = tester.state(find.byType(InboxScreen));
          state.setState(() {
            state.error = null;
            state.tab = tab;
            state.notificationStream = withInitialStreamTimeout(
              source.stream,
              InboxScreen.connectionTimeout,
            );
            state.inboxStream = withInitialStreamTimeout(
              source.stream,
              InboxScreen.connectionTimeout,
            );
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(InboxScreen.connectionTimeout);
          await tester.pump(const Duration(milliseconds: 300));
          final message =
              tab == 0
                  ? (language == 'en'
                      ? 'Notifications could not be refreshed.'
                      : 'Bildirimler yenilenemedi.')
                  : (language == 'en'
                      ? 'The inbox could not be refreshed.'
                      : 'Mesaj kutusu yenilenemedi.');
          expect(find.text(message), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.text(language == 'en' ? 'TRY AGAIN' : 'TEKRAR DENE'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          source.add([
            tab == 0
                ? {
                  'notificationId': 'n1',
                  'type': 'general',
                  'message': 'Recovered notification',
                  'read': true,
                }
                : {
                  'targetUid': 'friend',
                  'username': 'recovered_player',
                  'name': 'recovered_player',
                  'last': 'Recovered message',
                  'unread': false,
                },
          ]);
          await tester.pumpAndSettle();
          expect(find.text(message), findsNothing);
          expect(
            find.text(
              tab == 0 ? 'Recovered notification' : 'Recovered message',
            ),
            findsOneWidget,
          );
          await tester.pump(InboxScreen.connectionTimeout * 3);
          expect(find.text(message), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(cancelled, true);
        });
      }
    }
  }
}
