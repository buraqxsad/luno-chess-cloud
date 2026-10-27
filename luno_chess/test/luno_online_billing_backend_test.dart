import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_billing_models.dart';
import 'package:luno_chess/services/luno_online_billing_backend.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  test('billing uses existing Auth/App Check API and exact verification payload', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(request.url.path.endsWith('verifyPurchase') ? {
        'ok': true, 'verified': true, 'entitlementGranted': true, 'idempotent': true,
      } : {'ok': true, 'state': {'uid': 'first', 'gold': 1000}}), 200);
    });
    final online = LunoOnlineService.forTesting(bootstrap: () async {},
      auth: TestAuth(), client: client, appCheck: () async => 'app-check');
    addTearDown(online.dispose);
    addTearDown(client.close);
    await online.start();
    final backend = LunoOnlineBillingBackend(online);
    final owner = backend.currentOwner!;
    final result = await backend.verify(owner, 'luno_gold_1000', 'private-receipt');
    expect(result['entitlementGranted'], true);
    expect(result.containsKey('state'), false);
    final state = await backend.getPlayerState(owner);
    expect(state['state'], containsPair('uid', 'first'));
    expect(jsonDecode(requests.first.body), {
      'productId': 'luno_gold_1000', 'purchaseToken': 'private-receipt',
    });
    expect(requests.first.headers['Authorization'], 'Bearer test-token');
    expect(requests.first.headers['X-Firebase-AppCheck'], 'app-check');
    expect(requests.first.headers['X-Luno-Request-Id'], isNotEmpty);
  });

  test('production network retries are bounded and retain a request ID', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"ok":false,"error":"play-billing-unavailable"}', 503);
    });
    final online = LunoOnlineService.forTesting(bootstrap: () async {},
      auth: TestAuth(), client: client, appCheck: () async => 'check');
    addTearDown(online.dispose);
    addTearDown(client.close);
    await online.start();
    final backend = LunoOnlineBillingBackend(online);
    await expectLater(backend.verify(backend.currentOwner!, 'luno_gold_1000', 'private-receipt'),
      throwsA(isA<LunoBillingFailure>().having((e) => e.retryable, 'retryable', true)));
    expect(requests.length, 3);
    expect(requests.map((r) => r.headers['X-Luno-Request-Id']).toSet().length, 1);
  });

  test('HTTP response after owner loss does not escape into billing', () async {
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    final auth = TestAuth();
    final client = MockClient((_) async {
      entered.complete();
      return response.future;
    });
    final online = LunoOnlineService.forTesting(bootstrap: () async {},
      auth: auth, client: client, appCheck: () async => 'check');
    addTearDown(online.dispose);
    addTearDown(client.close);
    await online.start();
    final backend = LunoOnlineBillingBackend(online);
    final pending = backend.verify(backend.currentOwner!, 'luno_gold_1000', 'private-receipt');
    await entered.future;
    auth.currentUser = TestUser('second');
    final assertion = expectLater(pending, throwsA(isA<LunoBillingFailure>()));
    response.complete(http.Response('{"ok":true,"verified":true,"entitlementGranted":true}', 200));
    await assertion;
  });

  test('arbitrary server error codes cannot leak purchase tokens', () async {
    final client = MockClient((_) async =>
      http.Response('{"ok":false,"error":"private-receipt"}', 400));
    final online = LunoOnlineService.forTesting(bootstrap: () async {},
      auth: TestAuth(), client: client, appCheck: () async => 'check');
    addTearDown(online.dispose);
    addTearDown(client.close);
    await online.start();
    final backend = LunoOnlineBillingBackend(online);
    await expectLater(backend.verify(backend.currentOwner!, 'luno_gold_1000', 'private-receipt'),
      throwsA(isA<LunoBillingFailure>().having((e) => e.toString(), 'redacted',
        isNot(contains('private-receipt')))));
  });
}
