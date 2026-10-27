import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'battle_deck_account_test.dart' as deck_fixture;
import 'v220_billing_odds_fixture.dart';

void main() {
  for (final kind in ['daily', 'shop-chest', 'pass-chest']) {
    for (final change in ['auth', 'store', 'covered']) {
      testWidgets('$kind reward modal closes only itself on $change change', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        store.data.gold = 9999;
        store.data.pendingChests = ['common'];
        final auth = TestAuth();
        final events = StreamController<User?>.broadcast(sync: true);
        var mutations = 0;
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          authChanges: events.stream,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/getBattleV1Deck')) {
              return http.Response(jsonEncode(deck_fixture.response()), 200);
            }
            if (request.url.path.endsWith('/getPlayerState')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'state': kind == 'shop-chest' ? v220ChestState('first') : {},
                }),
                200,
              );
            }
            mutations++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'state': {'gold': 777},
                if (kind == 'daily') ...{
                  'granted': true,
                  'reward': {'gold': 120},
                },
                if (kind != 'daily') ...{
                  'opened': true,
                  'chestId': 'common',
                  'rewards': [
                    {'type': 'gold', 'amount': 100},
                  ],
                },
              }),
              200,
            );
          }),
          appCheck: () async => 'check',
        );
        addTearDown(() async {
          online.dispose();
          store.dispose();
          await events.close();
        });
        await online.start();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: LunoTheme.dark,
            home:
                kind == 'pass-chest'
                    ? PassScreen(online: online, playerStore: store)
                    : ShopScreen(online: online, playerStore: store),
          ),
        );
        await tester.pumpAndSettle();
        final label =
            kind == 'daily'
                ? 'AL'
                : kind == 'shop-chest'
                ? '500'
                : 'AÇ';
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, label))
            .onPressed!();
        await tester.pumpAndSettle();
        if (kind == 'shop-chest') {
          expect(mutations, 0);
          await tester.tap(find.byKey(const ValueKey('chest-odds-confirm')));
          await tester.pumpAndSettle();
        }
        expect(mutations, 1);
        expect(store.data.gold, 777);
        final modalType =
            kind == 'daily' ? ShopRewardDialog : ChestRevealDialog;
        expect(find.byType(modalType), findsOneWidget);
        expect(
          tester
              .widget<ModalBarrier>(find.byType(ModalBarrier).last)
              .dismissible,
          kind == 'daily',
        );
        if (change == 'covered') {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Keep this screen')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        if (change == 'store') {
          store.accountUid = 'second';
          store.notifyListeners();
        } else {
          auth.currentUser = TestUser('second');
          events.add(auth.currentUser);
        }
        await tester.pumpAndSettle();
        expect(find.byType(modalType, skipOffstage: false), findsNothing);
        expect(mutations, 1);
        if (change == 'covered') {
          expect(find.text('Keep this screen'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        }
        expect(navigator.currentState!.canPop(), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
