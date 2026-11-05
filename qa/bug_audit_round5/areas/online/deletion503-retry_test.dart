import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/workspace/luno-chess/luno_chess/test/account_deletion_flow_test.dart'
    show DeletionAuth, DeletionUser;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a bound real deletion service can explicitly resume after processing503', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.createForTesting();
    final auth = DeletionAuth()..currentUser = DeletionUser('round5-owner');
    var exhausted = true;
    var calls = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth,
      playerStore: store,
      appCheck: () async => 'local-round5-check',
      client: MockClient((request) async {
        expect(request.url.path.endsWith('/deleteAccount'), isTrue);
        calls++;
        return http.Response(
          jsonEncode(exhausted
              ? {'ok': false, 'error': 'account-deletion-in-progress'}
              : {'ok': true, 'deleted': true}),
          exhausted ? 503 : 200,
        );
      }),
    );
    addTearDown(() async {
      service.dispose();
      await store.flush();
      store.dispose();
    });
    await service.start();
    store.data.bio = 'retained until backend completion';
    await expectLater(
      service.deleteAccount(confirmed: true),
      throwsA(isA<LunoApiException>().having((error) => error.code, 'code', 'session-changed')),
    );
    expect(service.accountFailure?.code, 'account-deletion-in-progress');
    expect(auth.currentUser?.uid, 'round5-owner');
    expect(auth.signouts, 0);
    expect(store.data.bio, 'retained until backend completion');
    expect(calls, 1);
    exhausted = false;
    expect(await service.deleteAccount(confirmed: true), 'round5-owner');
    expect(calls, 2);
    expect(auth.signouts, 1);
    expect(auth.currentUser, isNull);
    expect(store.accountUid, isNull);
  });
}
