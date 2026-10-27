import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final action in ['claim', 'premium', 'chest']) {
    for (final scenario in ['success', 'account', 'signout', 'covered']) {
      testWidgets(
        'Pass $action respects $scenario boundary and duplicate taps',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final store =
              GameStore.createForTesting()
                ..loaded = true
                ..accountUid = 'first';
          store.data.passXp = 250;
          store.data.gems = 9999;
          store.data.pendingChests = ['common'];
          final auth = TestAuth();
          final response = Completer<http.Response>();
          var requests = 0;
          final online = LunoOnlineService.forTesting(
            bootstrap: () async {},
            auth: auth,
            client: MockClient((request) async {
              if (request.url.path.endsWith('/getPlayerState')) {
                return http.Response('{"ok":true,"state":{}}', 200);
              }
              requests++;
              return response.future;
            }),
            appCheck: () async => 'check',
          );
          addTearDown(() {
            online.dispose();
            store.dispose();
          });
          await online.start();
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: LunoTheme.dark,
              home: PassScreen(online: online, playerStore: store),
            ),
          );
          await tester.pumpAndSettle();
          VoidCallback callback(String kind) {
            if (kind == 'chest') {
              return tester
                  .widget<FilledButton>(find.widgetWithText(FilledButton, 'AÇ'))
                  .onPressed!;
            }
            return tester
                .widget<LunoButton>(
                  find
                      .byWidgetPredicate(
                        (w) =>
                            w is LunoButton &&
                            (kind == 'claim'
                                ? w.label == 'AL'
                                : w.label.contains('PREMIUM AL')),
                      )
                      .first,
                )
                .onPressed!;
          }

          final callbacks = [
            callback('claim'),
            callback('premium'),
            callback('chest'),
          ];
          callback(action)();
          await tester.pump(const Duration(milliseconds: 100));
          for (final stale in callbacks) {
            stale();
          }
          await tester.pump(const Duration(milliseconds: 100));
          expect(requests, 1);
          if (scenario == 'account') auth.currentUser = TestUser('second');
          if (scenario == 'signout') auth.currentUser = null;
          if (scenario == 'covered') {
            unawaited(
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Other screen')),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
          }
          response.complete(
            http.Response(
              jsonEncode({
                'ok': true,
                if (action == 'claim') 'granted': true,
                if (action == 'premium') 'purchased': true,
                if (action == 'chest') ...{'opened': false, 'rewards': []},
                'state': {
                  'gold': 777,
                  'profile': {'isPremium': true},
                },
              }),
              200,
            ),
          );
          await tester.pumpAndSettle();
          final current = scenario == 'success' || scenario == 'covered';
          expect(store.data.gold, current ? 777 : isNot(777));
          if (scenario != 'success') {
            expect(find.byType(SnackBar), findsNothing);
          }
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
