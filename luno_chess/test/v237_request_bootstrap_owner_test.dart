import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

class _AnonymousUser extends TestUser {
  _AnonymousUser(super.uid);
  @override
  bool get isAnonymous => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final phase in ['cold bootstrap', 'reconnect']) {
    for (final change in ['same account', 'other account', 'sign out']) {
      test('$phase cannot transfer a queued purchase after $change', () async {
        final auth = TestAuth();
        final entered = Completer<void>();
        final bootstrap = Completer<void>();
        var holdBootstrap = phase == 'cold bootstrap';
        final requests = <http.Request>[];
        final store = GameStore.createForTesting();
        addTearDown(store.dispose);
        final online = LunoOnlineService.forTesting(
          auth: auth,
          playerStore: store,
          bootstrap: () async {
            if (holdBootstrap) {
              entered.complete();
              await bootstrap.future;
            }
          },
          appCheck: () async => 'test-check',
          client: MockClient((request) async {
            requests.add(request);
            return http.Response('{"ok":true}', 200);
          }),
        );
        addTearDown(online.dispose);
        if (!holdBootstrap) {
          await online.start();
          holdBootstrap = true;
          online.ready = false;
        }
        final purchase = online.api('/purchaseSoftItem', {
          'itemId': 'skin:obsidian',
        });
        await entered.future;
        if (change == 'other account') {
          // Native currentUser can change before its auth event is delivered.
          auth.currentUser = TestUser('second');
          await store.bindAccount('second');
        } else if (change == 'sign out') {
          auth.currentUser = null;
          await store.bindAccount(null);
        } else {
          // A refreshed User object for the same session remains legitimate.
          auth.currentUser = TestUser('first');
        }
        final assertion =
            change == 'same account'
                ? expectLater(purchase, completion(containsPair('ok', true)))
                : expectLater(
                  purchase,
                  throwsA(
                    isA<LunoApiException>().having(
                      (error) => error.code,
                      'code',
                      'session-changed',
                    ),
                  ),
                );
        bootstrap.complete();
        await assertion;
        expect(requests, hasLength(change == 'same account' ? 1 : 0));
        if (requests.isNotEmpty) {
          expect(jsonDecode(requests.single.body), {'itemId': 'skin:obsidian'});
        }
      });
    }
  }

  for (final action in [
    'permanent purchase',
    'premium pass',
    'shop chest',
    'pass chest',
    'account deletion',
    'Google link',
  ]) {
    test('$action keeps the account that confirmed before recovery', () async {
      final auth = TestAuth()..currentUser = _AnonymousUser('first');
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      final entered = Completer<void>();
      final bootstrap = Completer<void>();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        auth: auth,
        playerStore: store,
        bootstrap: () async {
          entered.complete();
          await bootstrap.future;
        },
        appCheck: () async => 'test-check',
        client: MockClient((request) async {
          requests++;
          // A failed mock response bounds the unfixed request before any
          // subsequent operation; no real backend is contacted.
          return http.Response('{"ok":false,"error":"test-stop"}', 400);
        }),
      );
      addTearDown(online.dispose);
      final Future<Object?> operation = switch (action) {
        'permanent purchase' => online.purchaseSoftItem('piece_set:roma'),
        'premium pass' => online.purchaseSoftItem('pass:premium'),
        'shop chest' => online.openChest('rare'),
        'pass chest' => online.openPassChest('rare'),
        'account deletion' => online.deleteAccount(confirmed: true),
        _ => online.linkGoogle(),
      };
      await entered.future;
      auth.currentUser = _AnonymousUser('second');
      await store.bindAccount('second');
      final assertion = expectLater(
        operation,
        throwsA(
          isA<LunoApiException>().having(
            (error) => error.code,
            'code',
            'session-changed',
          ),
        ),
      );
      bootstrap.complete();
      await assertion;
      expect(requests, 0);
      expect(await store.pendingPermanentPurchaseItems('second'), isEmpty);
      expect(await store.pendingShopChestRequestKinds('second'), isEmpty);
      expect(await store.pendingPassChestRequestKinds('second'), isEmpty);
    });
  }
}
