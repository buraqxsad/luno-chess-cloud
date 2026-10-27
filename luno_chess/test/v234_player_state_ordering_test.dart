import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth;

Map<String, dynamic> _state(int revision, int observedAt, int gold) => {
  'uid': 'first',
  'stateRevision': revision,
  'stateObservedAt': observedAt,
  'gold': gold,
  'gems': gold ~/ 10,
  'profile': {'username': 'first_player', 'bio': 'revision-$revision'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('late old HTTP state cannot undo a newer reward snapshot', () async {
    final store = GameStore.createForTesting();
    final oldRead = Completer<http.Response>();
    final readStarted = Completer<void>();
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      playerStore: store,
      appCheck: () async => 'check',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/getPlayerState')) {
          readStarted.complete();
          return oldRead.future;
        }
        return http.Response(
          jsonEncode({'ok': true, 'state': _state(12, 200, 1500)}),
          200,
        );
      }),
    );
    addTearDown(() async {
      service.dispose();
      await store.flush();
      store.dispose();
    });
    await service.start();
    final delayed = service.api('/getPlayerState', {});
    await readStarted.future;
    final reward = await service.api('/claimDailyReward', {});
    store.applyServerState(Map<String, dynamic>.from(reward['state'] as Map));
    expect(store.data.gold, 1500);
    var changes = 0;
    store.addListener(() => changes++);

    oldRead.complete(
      http.Response(
        jsonEncode({'ok': true, 'state': _state(11, 100, 1000)}),
        200,
      ),
    );
    final older = await delayed;
    store.applyServerState(Map<String, dynamic>.from(older['state'] as Map));
    expect(store.data.gold, 1500);
    expect(store.data.gems, 150);
    expect(store.data.bio, 'revision-12');
    expect(changes, 0);
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    final disk = jsonDecode(prefs.getString('luno_player_v1')!) as Map;
    expect((disk['data'] as Map?)?['gold'] ?? disk['gold'], 1500);
  });

  test('commit revision outranks request-start and device clocks', () async {
    final store = GameStore.createForTesting();
    await store.load();
    addTearDown(store.dispose);
    store.applyServerState(_state(4, 90000, 1000));
    store.applyServerState(_state(5, 100, 1600));
    expect(store.data.gold, 1600);
    store.applyServerState(_state(4, 999999, 1000));
    expect(store.data.gold, 1600);
    await store.flush();
  });

  test(
    'same-revision old projection cannot re-enable expired membership',
    () async {
      final store = GameStore.createForTesting();
      await store.load();
      addTearDown(store.dispose);
      Map<String, dynamic> projection(int at, bool active) => {
        ..._state(7, at, 1000),
        'membership': {'active': active, 'expiresAt': 2000},
      };
      store.applyServerState(projection(3000, false));
      store.applyServerState(projection(1000, true));
      expect(store.data.isMembershipActive, isFalse);
      store.applyServerState(projection(4000, false));
      expect(store.data.isMembershipActive, isFalse);
      await store.flush();
    },
  );

  test('legacy snapshots work until versioned authority is observed', () async {
    final store = GameStore.createForTesting();
    await store.load();
    addTearDown(store.dispose);
    store.applyServerState({'gold': 900});
    expect(store.data.gold, 900);
    store.applyServerState(_state(1, 100, 1200));
    store.applyServerState({'gold': 800});
    expect(store.data.gold, 1200);
    await store.flush();
  });

  test(
    'account rebinding resets ordering but not response ownership',
    () async {
      final store = GameStore.createForTesting();
      await store.load();
      await store.bindAccount('first');
      addTearDown(store.dispose);
      Map<String, dynamic> owned(int revision, int gold) => {
        ..._state(revision, 100, gold),
        GameStore.serverStateOwnerKey: store.accountUid,
        GameStore.serverStateEpochKey: store.serverStateEpoch,
      };
      final old = owned(99, 9999);
      store.applyServerState(old);
      await store.bindAccount('second');
      store.applyServerState({...owned(1, 600), 'uid': 'second'});
      store.applyServerState(old);
      expect(store.data.gold, 600);
      await store.bindAccount('first');
      store.applyServerState(owned(100, 10000));
      expect(store.data.gold, 10000);
      await store.flush();
    },
  );

  for (final bad in [-1, 1.5, '2', double.infinity, 9007199254740992]) {
    test('invalid state revision $bad cannot mutate player data', () async {
      final store = GameStore.createForTesting();
      await store.load();
      addTearDown(store.dispose);
      final before = store.data.gold;
      store.applyServerState({..._state(1, 100, 0), 'stateRevision': bad});
      expect(store.data.gold, before);
      await store.flush();
    });
  }
}
