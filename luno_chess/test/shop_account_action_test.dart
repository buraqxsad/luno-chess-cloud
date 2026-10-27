import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'battle_deck_account_test.dart' as deck_fixture;
import 'v220_billing_odds_fixture.dart';

void main() {
  for (final action in ['daily', 'chest', 'activate', 'purchase']) {
    for (final scenario in [
      'success',
      'account',
      'covered',
      if (action == 'activate' || action == 'daily') 'malformed',
      if (action == 'purchase') 'already-owned',
    ]) {
      testWidgets(
        'shop $action guards $scenario result and duplicate callbacks',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final store =
              GameStore.createForTesting()
                ..loaded = true
                ..accountUid = 'first';
          store.data.gold = 9999;
          store.data.gems = 9999;
          if (action == 'activate') store.data.ownedPieceSets.add('ottoman');
          final auth = TestAuth();
          final response = Completer<http.Response>();
          var requests = 0;
          final online = LunoOnlineService.forTesting(
            bootstrap: () async {},
            auth: auth,
            client: MockClient((request) async {
              if (request.url.path.endsWith('/getPlayerState')) {
                return http.Response(
                  jsonEncode({
                    'ok': true,
                    'state': action == 'chest' ? v220ChestState('first') : {},
                  }),
                  200,
                );
              }
              if (request.url.path.endsWith('/getBattleV1Deck')) {
                return http.Response(jsonEncode(deck_fixture.response()), 200);
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
              home: ShopScreen(online: online, playerStore: store),
            ),
          );
          await tester.pumpAndSettle();
          Finder button;
          if (action == 'daily') {
            button = find.widgetWithText(FilledButton, 'AL');
          } else if (action == 'chest') {
            button = find.widgetWithText(FilledButton, '500');
          } else {
            await tester.scrollUntilVisible(
              find.text('OSMANLI'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            final product =
                find
                    .ancestor(
                      of: find.text('OSMANLI'),
                      matching: find.byWidgetPredicate(
                        (w) => w is SizedBox && w.width == 154,
                      ),
                    )
                    .first;
            button = find.descendant(
              of: product,
              matching: find.byType(FilledButton),
            );
          }
          final callback = tester.widget<FilledButton>(button).onPressed!;
          callback();
          callback();
          if (action == 'chest') {
            await tester.pumpAndSettle();
            expect(requests, 0);
            await tester.tap(find.byKey(const ValueKey('chest-odds-confirm')));
          }
          await tester.pump(const Duration(milliseconds: 200));
          expect(requests, 1);
          if (scenario == 'account') auth.currentUser = TestUser('second');
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
                if (action == 'daily') ...{
                  'granted': true,
                  'reward': {'gold': scenario == 'malformed' ? -1 : 120},
                },
                if (action == 'chest') ...{'opened': false, 'rewards': []},
                if (action == 'purchase')
                  'purchased': scenario != 'already-owned',
                'state': {
                  'gold': 777,
                  'inventory': {
                    'activePieceSet':
                        scenario == 'malformed' ? 'roma' : 'ottoman',
                  },
                },
              }),
              200,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            store.data.gold,
            scenario == 'account' || scenario == 'malformed' ? isNot(777) : 777,
          );
          if (scenario == 'account' || scenario == 'covered') {
            expect(find.byType(SnackBar), findsNothing);
            expect(find.byType(ShopRewardDialog), findsNothing);
            expect(find.byType(ChestRevealDialog), findsNothing);
          }
          if (scenario == 'malformed') {
            expect(find.byType(ShopRewardDialog), findsNothing);
          }
          if (scenario == 'already-owned') {
            expect(find.byType(ShopRewardDialog), findsNothing);
            expect(
              find.text('Bu ürün zaten hesabında bulunuyor.'),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final switchAccount in [false, true]) {
    testWidgets(
      'entry refresh completes before daily mutation: switch=$switchAccount',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        final auth = TestAuth();
        final refresh = Completer<http.Response>();
        var claims = 0;
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/getPlayerState')) {
              return refresh.future;
            }
            if (request.url.path.endsWith('/getBattleV1Deck')) {
              return http.Response(jsonEncode(deck_fixture.response()), 200);
            }
            claims++;
            return http.Response('{"ok":true,"granted":false,"state":{}}', 200);
          }),
          appCheck: () async => 'check',
        );
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await online.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: ShopScreen(online: online, playerStore: store),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'AL'))
            .onPressed!();
        await tester.pump(const Duration(milliseconds: 100));
        expect(claims, 0);
        if (switchAccount) auth.currentUser = TestUser('second');
        refresh.complete(http.Response('{"ok":true,"state":{}}', 200));
        await tester.pumpAndSettle();
        expect(claims, switchAccount ? 0 : 1);
        if (switchAccount) expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
