import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_billing_service.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'luno_billing_service_test.dart' show FakePlay, FakeBackend, receipt;
import 'online_request_session_test.dart' show TestAuth;
import 'v215_visual_capture.dart';

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final size in [const Size(320, 568), const Size(768, 1024)]) {
      for (final premium in [true, false]) {
        testWidgets(
          'Billing ${premium ? 'membership' : 'shop'} $language ${size.width} text180',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            SharedPreferences.setMockInitialValues({});
            final store =
                GameStore.createForTesting()
                  ..loaded = true
                  ..accountUid = 'first';
            final online = LunoOnlineService.forTesting(
              bootstrap: () async {},
              auth: TestAuth(),
              appCheck: () async => 'test-only',
              client: MockClient(
                (request) async => http.Response(
                  jsonEncode(
                    request.url.path.endsWith('/getBattleV1Deck')
                        ? response()
                        : {
                          'ok': true,
                          'state': {
                            'uid': 'first',
                            'gold': 1250,
                            'gems': 30,
                            'membership': {'active': false, 'expiresAt': 0},
                            'passState': {'premium': true},
                          },
                        },
                  ),
                  200,
                ),
              ),
            );
            final play =
                FakePlay()
                  ..catalog = [
                    for (final id in lunoBillingCatalog.keys)
                      LunoBillingProduct(
                        id: id,
                        title: id,
                        description: 'Store product',
                        localizedPrice: 'TRY 9.999,99',
                        rawPrice: 9999.99,
                        currencyCode: 'TRY',
                      ),
                  ];
            final backend =
                FakeBackend()..account = const LunoBillingOwner('first', 1);
            final billing = LunoBillingService(play: play, backend: backend);
            addTearDown(() async {
              billing.dispose();
              backend.dispose();
              online.dispose();
              store.dispose();
              await play.controller.close();
            });
            await tester.runAsync(() async {
              await online.start();
              await billing.start();
            });
            await tester.pumpWidget(
              shell(
                premium
                    ? LunoPremiumScreen(
                      online: online,
                      playerStore: store,
                      billingService: billing,
                    )
                    : ShopScreen(
                      online: online,
                      playerStore: store,
                      billingService: billing,
                    ),
                language: language,
                scale: 1.8,
                reduced: true,
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pumpAndSettle();
            if (!premium) {
              tester
                  .widget<SegmentedButton<String>>(
                    find.byType(SegmentedButton<String>),
                  )
                  .onSelectionChanged!({'currency'});
              await tester.pumpAndSettle();
            }
            final id = premium ? 'luno_premium_month' : 'luno_gold_1000';
            final key = ValueKey(
              premium ? 'membership-purchase' : 'store-product-$id',
            );
            final action = find.byKey(key);
            await tester.scrollUntilVisible(
              action,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            noOverflow(tester);
            if (premium) {
              expect(
                find.byKey(const ValueKey('membership-store-price')),
                findsOneWidget,
              );
              expect(tester.widget<LunoButton>(action).onPressed, isNotNull);
            } else {
              expect(find.text('TRY 9.999,99'), findsWidgets);
              expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
            }
            await captureV215(
              tester,
              'billing-${premium ? 'premium' : 'shop'}-$language-${size.width.toInt()}-180',
            );
            await tester.tap(action);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            play.emit([
              receipt(
                id: id,
                token: '',
                status: LunoPlayPurchaseStatus.pending,
              ),
            ]);
            await tester.pump();
            noOverflow(tester);
            if (premium) {
              expect(tester.widget<LunoButton>(action).onPressed, isNull);
            } else {
              expect(tester.widget<FilledButton>(action).onPressed, isNull);
            }
            expect(play.launches, 1);
            expect(backend.verifications, 0);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
