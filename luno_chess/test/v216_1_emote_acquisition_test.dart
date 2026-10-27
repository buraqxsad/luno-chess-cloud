import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/widgets/cosmetic_emote_art.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final flow in ['shop', 'pass']) {
    for (final scenario in ['success', 'account', 'missing-ownership', 'duplicate',
      if (flow == 'shop') 'wrong-receipt', if (flow == 'pass') 'wrong-content']) {
      testWidgets('$flow emote acquisition confirms $scenario without duplicate requests', (tester) async {
        final store = GameStore.createForTesting();
        await store.bindAccount('first');
        store.data.gold = 20000;
        store.data.passXp = 1000;
        final auth = TestAuth();
        final held = Completer<http.Response>();
        var requests = 0;
        Object? requestedValue;
        final online = LunoOnlineService.forTesting(bootstrap: () async {}, auth: auth,
          appCheck: () async => 'local-test-only', client: MockClient((r) async {
            if (r.url.path.endsWith('purchaseSoftItem') || r.url.path.endsWith('claimPassReward')) {
              requests++;
              final body = jsonDecode(r.body) as Map;
              requestedValue = body[flow == 'shop' ? 'itemId' : 'level'];
              return held.future;
            }
            return http.Response('{"ok":true,"state":{}}', 200);
          }));
        await online.start();
        addTearDown(online.dispose); addTearDown(store.dispose);
        await tester.pumpWidget(shell(flow == 'shop'
          ? ShopScreen(online: online, playerStore: store)
          : PassScreen(online: online, playerStore: store), reduced: true));
        await tester.pumpAndSettle();
        if (flow == 'shop') {
          await tester.tap(find.text('Kozmetik'));
          await tester.pumpAndSettle();
        }
        final button = find.byKey(ValueKey(flow == 'shop' ? 'shop-emote-heart' : 'pass-claim-free-4'));
        await tester.scrollUntilVisible(button, 350, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(button); await tester.pumpAndSettle();
        final callback = tester.widget<LunoButton>(button).onPressed!;
        callback(); callback();
        await tester.pump(const Duration(milliseconds: 100));
        expect(requests, 1);
        expect(requestedValue, flow == 'shop' ? 'emoji:heart' : 4);
        expect(store.data.ownedEmojis, isNot(contains(flow == 'shop' ? 'heart' : 'laugh')));
        if (scenario == 'account') auth.currentUser = TestUser('other');
        final id = flow == 'shop' ? 'heart' : 'laugh';
        held.complete(http.Response(jsonEncode({
          'ok': true,
          if (flow == 'shop') ...{
            'purchased': scenario != 'duplicate', 'idempotent': false,
            'itemId': scenario == 'wrong-receipt' ? 'emoji:cry' : 'emoji:heart',
            'transactionId': 'confirmed-purchase', 'grant': {'kind': 'emoji', 'id': 'heart'},
          } else ...{
            'granted': scenario != 'duplicate',
            'content': {'kind': 'emoji', 'id': scenario == 'wrong-content' ? 'cry' : 'laugh', 'duplicate': scenario == 'duplicate'},
          },
          'state': {'gold': 19500, 'inventory': {
            'ownedEmojis': ['smile', if (scenario != 'missing-ownership') id],
          }},
        }), 200));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(find.byType(ShopRewardDialog), scenario == 'success' ? findsOneWidget : findsNothing,
          reason: 'Owned: ${store.data.ownedEmojis}; gold: ${store.data.gold}; notices: ${tester.widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text))).map((w) => w.data).toList()}');
        if (scenario == 'success') {
          expect(find.descendant(of: find.byType(ShopRewardDialog), matching: find.byType(CosmeticEmoteArt)), findsOneWidget);
          expect(store.data.ownedEmojis, contains(id));
          await capture(tester, '$flow-emote-unlock', outputDirectory: 'qa/v216_1/after/acquisition');
        }
        if (scenario == 'account' || scenario == 'wrong-receipt' || scenario == 'missing-ownership' || scenario == 'wrong-content') {
          expect(store.data.ownedEmojis, isNot(contains(id)));
          expect(store.data.gold, 20000);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
