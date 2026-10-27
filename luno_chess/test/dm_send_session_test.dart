import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luno_chess/models/app_settings.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v214_ugc_safety_test.dart' show ugcReply;

void main() {
  for (final scenario in [
    'success',
    'malformed',
    'account',
    'before',
    'covered',
    'disposed',
    'target',
    'draft',
    'consent-account',
    'consent-success',
    'consent-cancel',
  ]) {
    testWidgets('DM send owns account and conversation: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      LunoSettings.instance.language = LunoSettings.languageTurkish;
      final auth = TestAuth();
      final sends = <Map<String, dynamic>>[];
      final pending = <Completer<http.Response>>[];
      var consents = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) {
          if (request.url.path.endsWith('/acceptLegalTerms')) {
            consents++;
            return Future.value(
              http.Response(jsonEncode(ugcReply('first')), 200),
            );
          }
          if (!request.url.path.endsWith('/sendDirectMessage')) {
            return Future.value(
              http.Response('{"ok":false,"error":"unavailable"}', 200),
            );
          }
          sends.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
          if (scenario.startsWith('consent') && sends.length == 1) {
            return Future.value(
              http.Response(
                '{"ok":false,"error":"legal-consent-required"}',
                403,
              ),
            );
          }
          final response = Completer<http.Response>();
          pending.add(response);
          return response.future;
        }),
      );
      addTearDown(online.dispose);
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
      await tester.pumpWidget(app('first-target'));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(DirectMessageScreen));
      state.setState(() {
        state.messagesStream = Stream.value(<Map<String, dynamic>>[]);
        state.error = null;
      });
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Merhaba');
      final submit =
          tester.widget<TextField>(find.byType(TextField)).onSubmitted!;
      if (scenario == 'before') {
        auth.currentUser = TestUser('second');
        submit('Merhaba');
        await tester.pumpAndSettle();
        expect(sends, isEmpty);
        expect(state.input.text, 'Merhaba');
      } else {
        submit('Merhaba');
        submit('Merhaba');
        await tester.pump(const Duration(milliseconds: 300));
        expect(sends, hasLength(1));
        expect(sends.first['targetUid'], 'first-target');
        if (scenario.startsWith('consent')) {
          expect(find.byType(AlertDialog), findsOneWidget);
          if (scenario == 'consent-account') {
            auth.currentUser = TestUser('second');
            online.notifyListeners();
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.byType(AlertDialog), findsNothing);
            expect(consents, 0);
            expect(sends, hasLength(1));
            expect(state.error, isNull);
          } else if (scenario == 'consent-cancel') {
            await tester.tap(find.text('ŞİMDİ DEĞİL'));
            await tester.pumpAndSettle();
            expect(consents, 0);
            expect(state.error, isNull);
            expect(state.input.text, 'Merhaba');
          } else {
            await tester.ensureVisible(
              find.byKey(const Key('ugc-consent-checkbox')),
            );
            await tester.tap(find.byKey(const Key('ugc-consent-checkbox')));
            await tester.pump(const Duration(milliseconds: 200));
            await tester.tap(find.text('KABUL ET'));
            await tester.pump(const Duration(milliseconds: 400));
            expect(consents, 1);
            expect(sends, hasLength(2));
            pending.first.complete(
              http.Response('{"ok":true,"messageId":"new-message"}', 200),
            );
            await tester.pumpAndSettle();
            expect(state.input.text, isEmpty);
          }
        } else {
          if (scenario == 'account') auth.currentUser = TestUser('second');
          if (scenario == 'disposed') {
            await tester.pumpWidget(
              const MaterialApp(home: Text('Replacement')),
            );
          }
          if (scenario == 'covered') {
            unawaited(
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Other screen')),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          if (scenario == 'draft') {
            await tester.enterText(find.byType(TextField), 'Yeni taslak');
          }
          if (scenario == 'target') {
            await tester.pumpWidget(app('second-target'));
            await tester.pumpAndSettle();
            expect(state.input.text, isEmpty);
            state.setState(() {
              state.messagesStream = Stream.value(<Map<String, dynamic>>[]);
              state.error = null;
            });
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField), 'Merhaba');
            tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
              'Merhaba',
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(sends, hasLength(2));
            expect(sends.last['targetUid'], 'second-target');
          }
          pending.first.complete(
            http.Response(
              scenario == 'malformed'
                  ? '{"ok":true}'
                  : scenario == 'covered' || scenario == 'disposed'
                  ? '{"ok":false,"error":"unavailable"}'
                  : '{"ok":true,"messageId":"first-message"}',
              200,
            ),
          );
          if (scenario == 'account' || scenario == 'target') {
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
          } else {
            await tester.pumpAndSettle();
          }
          if (scenario == 'success') expect(state.input.text, isEmpty);
          if (scenario == 'malformed') {
            expect(state.input.text, 'Merhaba');
            expect(state.error, 'Mesaj gönderilemedi.');
          }
          if (scenario == 'account') {
            expect(state.input.text, 'Merhaba');
            expect(state.error, isNull);
          }
          if (scenario == 'draft') expect(state.input.text, 'Yeni taslak');
          if (scenario == 'covered') {
            expect(find.text('Other screen'), findsOneWidget);
            expect(state.error, isNull);
          }
          if (scenario == 'target') {
            expect(state.input.text, 'Merhaba');
            expect(state.sending, isTrue);
            pending.last.complete(
              http.Response('{"ok":true,"messageId":"second-message"}', 200),
            );
            await tester.pumpAndSettle();
            expect(state.input.text, isEmpty);
            expect(state.sending, isFalse);
          }
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
