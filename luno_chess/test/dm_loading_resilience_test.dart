import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'online_request_session_test.dart' show TestAuth;

Widget dmApp(
  LunoOnlineService online,
  String language, {
  String target = 'friend',
}) => MaterialApp(
  theme: LunoTheme.dark,
  locale: Locale(language),
  supportedLocales: const [Locale('tr'), Locale('en')],
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: DirectMessageScreen(
    targetUid: target,
    targetName: target,
    online: online,
  ),
);

void main() {
  for (final language in ['tr', 'en']) {
    for (final receipt in ['pending', 'failure']) {
      testWidgets(
        'DM snapshot timeout recovers despite $receipt receipt $language',
        (tester) async {
          final rows = StreamController<List<Map<String, dynamic>>>.broadcast(
            sync: true,
          );
          final pending = Completer<http.Response>();
          var reads = 0;
          final online = LunoOnlineService.forTesting(
            auth: TestAuth(),
            bootstrap: () async {},
            appCheck: () async => 'check',
            directMessageStream: (_) => rows.stream,
            client: MockClient((request) {
              if (request.url.path.endsWith('/openDirectMessage')) {
                return Future.value(
                  http.Response(
                    '{"ok":true,"conversationId":"conversation"}',
                    200,
                  ),
                );
              }
              reads++;
              return receipt == 'pending'
                  ? pending.future
                  : Future.value(
                    http.Response('{"ok":false,"error":"unavailable"}', 200),
                  );
            }),
          );
          addTearDown(() async {
            online.dispose();
            await rows.close();
          });
          await online.start();
          await tester.pumpWidget(dmApp(online, language));
          await tester.pump(const Duration(milliseconds: 100));
          expect(reads, 0);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            find.text(
              language == 'en'
                  ? 'Start the conversation.'
                  : 'Konuşmayı başlat.',
            ),
            findsNothing,
          );
          await tester.pump(DirectMessageScreen.initialLoadTimeout);
          await tester.pump(const Duration(milliseconds: 300));
          final error =
              language == 'en'
                  ? 'Messages could not be loaded.'
                  : 'Mesajlar yüklenemedi.';
          expect(find.text(error), findsOneWidget);
          rows.add([
            {
              'from': 'friend',
              'text': 'Recovered message',
              'messageId': 'm1',
              'ts': 123,
            },
          ]);
          await tester.pump();
          expect(find.text('Recovered message'), findsOneWidget);
          expect(find.text(error), findsNothing);
          await tester.pump(const Duration(milliseconds: 300));
          expect(reads, 1);
          if (receipt == 'pending') {
            pending.complete(http.Response('{"ok":true}', 200));
          }
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(rows.hasListener, false);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('DM actual empty snapshot is distinct from loading $language', (
      tester,
    ) async {
      final rows = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        directMessageStream: (_) => rows.stream,
        client: MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('/openDirectMessage')
                ? '{"ok":true,"conversationId":"conversation"}'
                : '{"ok":true}',
            200,
          ),
        ),
      );
      addTearDown(() async {
        online.dispose();
        await rows.close();
      });
      await online.start();
      await tester.pumpWidget(dmApp(online, language));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      rows.add([]);
      await tester.pumpAndSettle();
      expect(
        find.text(
          language == 'en' ? 'Start the conversation.' : 'Konuşmayı başlat.',
        ),
        findsOneWidget,
      );
      await tester.pump(DirectMessageScreen.initialLoadTimeout * 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('DM bootstrap timeout permits retry $language', (tester) async {
      final pending = Completer<void>();
      var attempts = 0;
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () {
          attempts++;
          return pending.future;
        },
      );
      addTearDown(online.dispose);
      await tester.pumpWidget(dmApp(online, language));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(DirectMessageScreen.initialLoadTimeout);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text(
          language == 'en'
              ? 'The conversation could not be opened.'
              : 'Konuşma açılamadı.',
        ),
        findsOneWidget,
      );
      final retry = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(retry.onPressed, isNotNull);
      pending.completeError(StateError('Late failure'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(language == 'en' ? 'TRY AGAIN' : 'YENİDEN DENE'),
      );
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'DM target replacement cancels old stream and waits for new data',
    (tester) async {
      final oldRows = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final newRows = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        directMessageStream:
            (target) => target == 'friend' ? oldRows.stream : newRows.stream,
        client: MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('/openDirectMessage')
                ? '{"ok":true,"conversationId":"conversation"}'
                : '{"ok":true}',
            200,
          ),
        ),
      );
      addTearDown(() async {
        online.dispose();
        await oldRows.close();
        await newRows.close();
      });
      await online.start();
      await tester.pumpWidget(dmApp(online, 'tr'));
      await tester.pump(const Duration(milliseconds: 100));
      oldRows.add([
        {'from': 'friend', 'text': 'Old private message'},
      ]);
      await tester.pump();
      expect(find.text('Old private message'), findsOneWidget);
      await tester.pumpWidget(dmApp(online, 'tr', target: 'new_friend'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(oldRows.hasListener, false);
      expect(find.text('Old private message'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      oldRows.add([
        {'from': 'friend', 'text': 'Late old message'},
      ]);
      newRows.add([
        {'from': 'new_friend', 'text': 'New private message'},
      ]);
      await tester.pump();
      expect(find.text('Late old message'), findsNothing);
      expect(find.text('New private message'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(newRows.hasListener, false);
      expect(tester.takeException(), isNull);
    },
  );
}
