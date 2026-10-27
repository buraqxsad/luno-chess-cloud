import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth;
import 'battle_deck_account_test.dart' show response;
import 'v215_progression_product_test.dart' show modernProgress;
import 'v215_cosmetic_surfaces_test.dart' show capture;

LunoOnlineService service(
  GameStore store,
  Future<http.Response> Function(http.Request) handler,
) => LunoOnlineService.forTesting(
  bootstrap: () async {},
  auth: TestAuth(),
  appCheck: () async => 'test-only',
  client: MockClient(handler),
);

Map<String, dynamic> snapshot({bool membership = false, bool pass = false}) => {
  'membership': {
    'active': membership,
    'expiresAt': membership ? 2000000000000 : 0,
  },
  'passState': {'premium': pass},
};

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final daily in [false, true]) {
      testWidgets(
        'shop $language ${daily ? 'daily unlock' : 'welcome recovery'} confirms card then offers deck',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 568);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          final store =
              GameStore.createForTesting()
                ..loaded = true
                ..accountUid = 'first'
                ..firstSessionMatchCompleted = true;
          var welcome = daily, days = daily ? 1 : 0, claims = 0;
          final online = service(store, (request) async {
            if (request.url.path.endsWith('/getBattleV1Deck')) {
              final progression = modernProgress(0, days, welcome);
              final owned = [
                ...starterDeck,
                if (welcome) CardId.mine,
                if (days >= 2) CardId.breakSeal,
                if (days >= 3) CardId.fog,
              ];
              return http.Response(
                jsonEncode({
                  ...response(owned: owned.map((card) => card.wire).toList()),
                  'progression': progression,
                }),
                200,
              );
            }
            if (request.url.path.endsWith('/claimOnboardingReward') ||
                request.url.path.endsWith('/claimDailyReward')) {
              claims++;
              if (daily) {
                days = 2;
              } else {
                welcome = true;
              }
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'granted': true,
                  'idempotent': false,
                  'reward': {'gold': daily ? 100 : 500},
                  if (!daily)
                    'welcome': {
                      'version': 1,
                      'claimed': true,
                      'card': 'mine',
                      'eligibility': 'account_welcome',
                    },
                  'state': {'gold': daily ? 1350 : 1750},
                }),
                200,
              );
            }
            return http.Response('{"ok":true,"state":{}}', 200);
          });
          addTearDown(() {
            online.dispose();
            store.dispose();
          });
          await tester.runAsync(() async {
            await online.start();
          });
          await tester.pumpWidget(
            shell(
              ShopScreen(online: online, playerStore: store),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pumpAndSettle();
          if (!daily) await capture(tester, 'shop-welcome-$language-320-150');
          if (daily) {
            final claim = find.widgetWithText(
              FilledButton,
              language == 'en' ? 'CLAIM' : 'AL',
            );
            await tester.scrollUntilVisible(
              claim,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            final callback = tester.widget<FilledButton>(claim).onPressed!;
            callback();
            callback();
          } else {
            final callback =
                tester
                    .widget<LunoButton>(
                      find.byKey(const ValueKey('shop-welcome-reward')),
                    )
                    .onPressed!;
            callback();
            callback();
          }
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pumpAndSettle();
          expect(claims, 1);
          expect(
            online.cachedBattleDeck!.owned,
            contains(daily ? CardId.breakSeal : CardId.mine),
          );
          expect(find.byType(ShopRewardDialog), findsOneWidget);
          await capture(
            tester,
            'shop-${daily ? 'daily-unlock' : 'welcome-confirmed'}-$language-320-150',
          );
          final edit = find.widgetWithText(
            LunoButton,
            language == 'en' ? 'EDIT DECK' : 'DESTENİ DÜZENLE',
          );
          await tester.ensureVisible(edit);
          tester.widget<LunoButton>(edit).onPressed!();
          await tester.pumpAndSettle();
          expect(find.byType(BattleDeckScreen), findsOneWidget);
          expect(
            tester
                .widget<BattleDeckScreen>(find.byType(BattleDeckScreen))
                .focusCard,
            daily ? CardId.breakSeal : CardId.mine,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final language in ['tr', 'en']) {
    testWidgets('Premium $language shows injected catalog prices verbatim', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      final online = service(
        store,
        (_) async =>
            http.Response(jsonEncode({'ok': true, 'state': snapshot()}), 200),
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await tester.runAsync(() async => online.start());
      await tester.pumpWidget(
        shell(
          LunoPremiumScreen(
            online: online,
            playerStore: store,
            membershipPrices: const {
              'luno_premium_month': 'Play monthly catalog price',
              'luno_premium_year': 'Play yearly catalog price',
            },
          ),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('membership-catalog-price')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Play monthly catalog price'), findsOneWidget);
      expect(find.text('Play yearly catalog price'), findsNothing);
      expect(
        tester
            .widget<LunoButton>(
              find.byKey(const ValueKey('membership-purchase')),
            )
            .onPressed,
        isNull,
      );
      await capture(tester, 'premium-catalog-$language-320-150');
      await tester.tap(find.text(language == 'en' ? 'Yearly' : 'Yıllık'));
      await tester.pumpAndSettle();
      expect(find.text('Play yearly catalog price'), findsOneWidget);
      expect(find.text('Play monthly catalog price'), findsNothing);
      expect(store.data.isMembershipActive, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  for (final member in [false, true]) {
    for (final pass in [false, true]) {
      testWidgets('membership $member stays independent of paid Pass $pass', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        var purchases = 0;
        final online = service(store, (request) async {
          if (request.url.path.endsWith('/purchaseSoftItem')) purchases++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'state': snapshot(membership: member, pass: pass),
            }),
            200,
          );
        });
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await tester.runAsync(() async {
          await online.start();
        });
        await tester.pumpWidget(
          shell(
            LunoPremiumScreen(online: online, playerStore: store),
            language: 'en',
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(store.data.isMembershipActive, member);
        expect(store.data.premium, pass);
        expect(
          find.text(member ? 'MEMBERSHIP ACTIVE' : 'NO MEMBERSHIP'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('membership-purchase')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final buy = tester.widget<LunoButton>(
          find.byKey(const ValueKey('membership-purchase')),
        );
        expect(buy.onPressed, isNull);
        expect(
          purchases,
          0,
          reason: 'Membership must never buy the seasonal Pass',
        );
        expect(
          find.byKey(const ValueKey('membership-not-pass')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final accountChange in [false, true]) {
    testWidgets(
      'membership provider callback serializes taps accountChange=$accountChange',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        var active = false, billingCalls = 0;
        String? productId;
        final pending = Completer<void>();
        final online = service(
          store,
          (_) async => http.Response(
            jsonEncode({'ok': true, 'state': snapshot(membership: active)}),
            200,
          ),
        );
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await tester.runAsync(() async {
          await online.start();
        });
        await tester.pumpWidget(
          shell(
            LunoPremiumScreen(
              online: online,
              playerStore: store,
              purchaseMembership: (sku) {
                billingCalls++;
                productId = sku;
                return pending.future;
              },
            ),
            language: 'en',
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('membership-purchase')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final callback =
            tester
                .widget<LunoButton>(
                  find.byKey(const ValueKey('membership-purchase')),
                )
                .onPressed!;
        callback();
        callback();
        await tester.pump();
        expect(billingCalls, 1);
        expect(productId, 'luno_premium_month');
        if (accountChange) {
          store.accountUid = 'second';
          store.data = PlayerData.initial();
        }
        active = true;
        pending.complete();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(store.data.isMembershipActive, !accountChange);
        expect(store.data.premium, false);
        await tester.pumpWidget(const SizedBox());
        callback();
        expect(billingCalls, 1);
      },
    );
  }

  testWidgets(
    'paid Pass never displays membership and members still need a paid track',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      store.data
        ..membershipActive = true
        ..premiumUntil = 2000000000000
        ..gems = 1000;
      final online = service(
        store,
        (_) async => http.Response('{"ok":true,"state":{}}', 200),
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await tester.pumpWidget(
        shell(PassScreen(online: online, playerStore: store), language: 'en'),
      );
      await tester.pumpAndSettle();
      expect(store.data.premium, false);
      expect(find.byKey(const ValueKey('pass-not-membership')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is LunoButton && w.label.contains('GET PASS PREMIUM'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scenario in ['success', 'failure', 'account']) {
    testWidgets(
      'costume equip remains confirmed-only and serialized: $scenario',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        store.data.ownedPieceSets.addAll(['ottoman', 'roma']);
        final pending = Completer<http.Response>();
        var equips = 0;
        final online = service(store, (request) async {
          if (request.url.path.endsWith('/getPlayerState')) {
            return http.Response('{"ok":true,"state":{}}', 200);
          }
          equips++;
          return pending.future;
        });
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await tester.runAsync(() async {
          await online.start();
        });
        await tester.pumpWidget(
          shell(PieceCostumeScreen(online: online, playerStore: store)),
        );
        await tester.pumpAndSettle();
        Finder tile(String id) => find.byWidgetPredicate(
          (w) =>
              w.runtimeType.toString() == '_PieceSetTile' &&
              (w as dynamic).id == id,
        );
        final callback =
            (tester.widget(tile('ottoman')) as dynamic).onTap as VoidCallback;
        callback();
        callback();
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        expect(
          store.data.pieceSet,
          'luno',
          reason: 'Pending equip must not masquerade as confirmed',
        );
        expect(equips, 1);
        if (scenario == 'account') {
          store.accountUid = 'second';
          store.data = PlayerData.initial();
        }
        pending.complete(
          scenario == 'failure'
              ? http.Response('{"error":"locked-selection"}', 409)
              : http.Response(
                jsonEncode({
                  'ok': true,
                  'state': {
                    'profile': {'activePieceSet': 'ottoman'},
                    'inventory': {
                      'activePieceSet': 'ottoman',
                      'ownedSets': ['std', 'ottoman', 'roma'],
                    },
                  },
                }),
                200,
              ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(store.data.pieceSet, scenario == 'success' ? 'ottoman' : 'luno');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        callback();
        expect(equips, 1);
      },
    );
  }
}
