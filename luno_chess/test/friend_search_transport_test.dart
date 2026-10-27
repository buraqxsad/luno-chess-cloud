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
    'newer',
    'edit',
    'tab',
    'account',
    'malformed',
    'duplicate',
    'invalid',
  ]) {
    testWidgets('search transport handles $scenario', (tester) async {
      final auth = TestAuth();
      final pending = <Completer<http.Response>>[];
      final queries = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        friendRequestStream: Stream.value(<Map<String, dynamic>>[]),
        matchInviteStream:
            Stream.value(<Map<String, dynamic>>[]).asBroadcastStream(),
        databaseRead: (_) async => {},
        client: MockClient((request) {
          queries.add((jsonDecode(request.body) as Map)['query'] as String);
          final completer = Completer<http.Response>();
          pending.add(completer);
          return completer.future;
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: FriendsScreen(online: online)),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(FriendsScreen));
      Future<void> submit(String query) async {
        await tester.enterText(find.byType(TextField), query);
        tester.widget<TextField>(find.byType(TextField)).onSubmitted!(query);
        await tester.pump(const Duration(milliseconds: 50));
      }

      http.Response result(String uid) => http.Response(
        jsonEncode({
          'ok': true,
          'results': [
            {'uid': uid, 'username': uid, 'relationship': 'none'},
          ],
        }),
        200,
      );
      await submit(scenario == 'invalid' ? 'bad query!' : 'FIRST_PLAYER');
      if (scenario == 'invalid') {
        expect(queries, isEmpty);
        expect(state.loading, false);
      } else {
        expect(queries, ['first_player']);
        if (scenario == 'newer') {
          await submit('second_player');
          expect(pending, hasLength(2));
          pending[1].complete(result('new_player'));
          await tester.pump(const Duration(milliseconds: 50));
        } else if (scenario == 'edit') {
          await tester.enterText(find.byType(TextField), 'changed');
        } else if (scenario == 'tab') {
          await tester.tap(find.text('İSTEKLER'));
          await tester.pump(const Duration(milliseconds: 50));
        } else if (scenario == 'account') {
          auth.currentUser = TestUser('second');
        } else if (scenario == 'duplicate') {
          tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
            'FIRST_PLAYER',
          );
          await tester.pump(const Duration(milliseconds: 50));
          expect(pending, hasLength(1));
        }
        pending.first.complete(
          scenario == 'malformed'
              ? http.Response(
                jsonEncode({
                  'ok': true,
                  'results': [42],
                }),
                200,
              )
              : result('old_player'),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (scenario == 'newer') {
          expect(state.results.single['uid'], 'new_player');
        } else if (scenario == 'duplicate') {
          expect(state.results.single['uid'], 'old_player');
        } else {
          expect(state.results, isEmpty);
        }
        if (scenario == 'malformed') {
          expect(state.searchError, isNotNull);
          expect(find.text('Oyuncu bulunamadı.'), findsNothing);
        }
        if (scenario == 'account') expect(find.byType(SnackBar), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
