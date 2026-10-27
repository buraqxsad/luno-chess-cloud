import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/battle_v1/pending_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'helpers/battle_v1_response.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

class _Storage {
  final cache = <String, String>{};
  final disk = <String, String>{};
  bool writeSucceeds = true, removeSucceeds = true;
  bool writeThrows = false, removeThrows = false;
  int writes = 0, removals = 0;

  BattleV1PendingStore store({String uid = 'self'}) =>
      BattleV1PendingStore.forTesting(
        storageIdentity: this,
        uid: uid,
        matchId: v1MatchId,
        read: (key) => cache[key],
        write: (key, value) async {
          writes++;
          cache[key] = value;
          if (writeThrows) throw StateError('write failed');
          if (writeSucceeds) disk[key] = value;
          return writeSucceeds;
        },
        remove: (key) async {
          removals++;
          cache.remove(key);
          if (removeThrows) throw StateError('remove failed');
          if (removeSucceeds) disk.remove(key);
          return removeSucceeds;
        },
      );
}

BattleV1Controller _controller(
  BattleV1PendingStore store, {
  required BattleV1Request request,
  bool Function()? owner,
}) => BattleV1Controller(
  uid: 'self',
  matchId: v1MatchId,
  initialResponse: v1Response(),
  request: request,
  persistPending: store.persist,
  pendingJson: store.pendingJson,
  pendingPersisted: store.pendingPersisted,
  isSessionCurrent: owner,
);

void main() {
  for (final removal in [false, true]) {
    test('thrown storage failure preserves the same intent: removal=$removal', () async {
      final storage = _Storage()
        ..writeThrows = !removal
        ..removeThrows = removal;
      final store = storage.store();
      var sends = 0;
      final controller = _controller(store, request: (_, _) async {
        sends++;
        return v1Response(version: 1);
      });
      addTearDown(controller.dispose);
      await controller.submit(const ChessMoveAction('e2e4'));
      final original = store.pendingJson;
      expect(original, isNotNull);
      expect(controller.error, isA<StateError>());
      expect(sends, removal ? 1 : 0);
      expect(storage.store().pendingJson, original);
      storage.writeThrows = false;
      storage.removeThrows = false;
      await controller.retryPending();
      expect(sends, 1);
      expect(controller.hasPendingIntent, isFalse);
    });
  }

  test('false write fails closed and recreation retries the same action ID', () async {
    final storage = _Storage()..writeSucceeds = false;
    final store = storage.store();
    final sent = <Map<String, dynamic>>[];
    Future<Map<String, dynamic>> request(String path, Map<String, dynamic> body) async {
      sent.add(Map.of(body));
      return v1Response(version: 1);
    }

    final first = _controller(store, request: request);
    await first.submit(const ChessMoveAction('e2e4'));
    final original = store.pendingJson!;
    expect(first.error, isA<BattleV1PendingStorageException>());
    expect(sent, isEmpty);
    expect(storage.disk, isEmpty);
    expect(store.pendingPersisted, isFalse);
    first.dispose();

    storage.writeSucceeds = true;
    final restored = _controller(storage.store(), request: request);
    addTearDown(restored.dispose);
    await restored.retryPending();
    expect(sent.single, jsonDecode(original));
    expect(storage.writes, 2);
    expect(restored.hasPendingIntent, isFalse);
  });

  test('failed removal survives cache deletion and controller recreation', () async {
    final storage = _Storage()..removeSucceeds = false;
    final store = storage.store();
    final bodies = <Map<String, dynamic>>[];
    Future<Map<String, dynamic>> request(String path, Map<String, dynamic> body) async {
      bodies.add(Map.of(body));
      return v1Response(version: 1);
    }

    final first = _controller(store, request: request);
    await first.submit(const ChessMoveAction('e2e4'));
    final original = store.pendingJson;
    expect(first.hasPendingIntent, isTrue);
    expect(storage.cache, isEmpty);
    expect(storage.disk.values.single, original);
    first.dispose();

    final restoredStore = storage.store();
    expect(restoredStore.pendingJson, original);
    storage.removeSucceeds = true;
    final restored = _controller(restoredStore, request: request);
    addTearDown(restored.dispose);
    await restored.retryPending();
    expect(bodies, hasLength(2));
    expect(bodies[1], bodies[0]);
    expect(restoredStore.pendingJson, isNull);
    expect(storage.disk, isEmpty);
  });

  for (final rejection in [false, true]) {
    test('resolved action retries cleanup only: rejected=$rejection', () async {
      final storage = _Storage()..removeSucceeds = false;
      var sends = 0;
      final controller = _controller(storage.store(), request: (_, _) async {
        sends++;
        if (rejection) throw const BattleV1Rejection('STALE_STATE');
        return v1Response(version: 1);
      });
      addTearDown(controller.dispose);
      await controller.submit(const ChessMoveAction('e2e4'));
      expect(controller.hasPendingIntent, isTrue);
      storage.removeSucceeds = true;
      await controller.retryPending();
      expect(sends, 1);
      expect(controller.hasPendingIntent, isFalse);
    });
  }

  test('terminal acceptance retains a cleanup-only retry after removal failure', () async {
    final storage = _Storage()..removeSucceeds = false;
    var sends = 0;
    final terminal = v1Response(version: 1)..['status'] = 'finished';
    final public = (terminal['view'] as Map)['public'] as Map;
    public['result'] = {'reason': 'resign', 'winner': 'b'};
    final controller = _controller(storage.store(), request: (_, _) async {
      sends++;
      return terminal;
    });
    addTearDown(controller.dispose);
    await controller.resign();
    expect(controller.snapshot!.result!['reason'], 'resign');
    expect(controller.hasPendingIntent, isTrue);
    storage.removeSucceeds = true;
    await controller.retryPending();
    expect(sends, 1);
    expect(controller.hasPendingIntent, isFalse);
  });

  test('session change during persistence prevents dispatch and clears private view', () async {
    final hold = Completer<void>();
    var current = true, sends = 0;
    String? saved;
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: v1Response(),
      isSessionCurrent: () => current,
      persistPending: (value) async {
        saved = value;
        await hold.future;
      },
      request: (_, _) async {
        sends++;
        return v1Response(version: 1);
      },
    );
    addTearDown(controller.dispose);
    final running = controller.submit(const ChessMoveAction('e2e4'));
    current = false;
    hold.complete();
    await running;
    expect(saved, isNotNull);
    expect(sends, 0);
    expect(controller.snapshot, isNull);
    expect(controller.busy, isFalse);
  });

  test('invalidation ignores late acceptance without removing the saved action', () async {
    final response = Completer<Map<String, dynamic>>();
    String? saved;
    var removals = 0;
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: v1Response(),
      persistPending: (value) async {
        if (value == null) removals++;
        saved = value;
      },
      request: (_, _) => response.future,
    );
    addTearDown(controller.dispose);
    final running = controller.submit(const ChessMoveAction('e2e4'));
    await Future<void>.delayed(Duration.zero);
    controller.invalidateSession();
    response.complete(v1Response(version: 1));
    await running;
    expect(saved, isNotNull);
    expect(removals, 0);
    expect(controller.snapshot, isNull);
  });

  test('repeated retries and reconnect cannot overlap a pending submission', () async {
    final hold = Completer<Map<String, dynamic>>();
    var requests = 0;
    final controller = _controller(_Storage().store(), request: (_, _) {
      requests++;
      return hold.future;
    });
    addTearDown(controller.dispose);
    final running = controller.submit(const ChessMoveAction('e2e4'));
    await Future<void>.delayed(Duration.zero);
    await Future.wait([
      controller.retryPending(),
      controller.retryPending(),
      controller.reconnect(),
    ]);
    expect(requests, 1);
    hold.complete(v1Response(version: 1));
    await running;
  });

  test('pending storage remains isolated between accounts', () async {
    final storage = _Storage();
    final first = storage.store(), second = storage.store(uid: 'other');
    await first.persist('original-action');
    expect(second.pendingJson, isNull);
    await second.persist('other-action');
    await second.persist(null);
    expect(first.pendingJson, 'original-action');
  });

  test('battle API owner is checked again after bootstrap readiness', () async {
    final hold = Completer<void>();
    final auth = TestAuth();
    var requests = 0;
    final service = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () => hold.future,
      appCheck: () async => 'check',
      client: MockClient((_) async {
        requests++;
        return http.Response('{"ok":true}', 200);
      }),
    );
    addTearDown(service.dispose);
    final assertion = expectLater(
      service.battleV1Api(
        '/submitBattleV1Action',
        {},
        ownerUid: 'first',
        ownerRevision: service.accountRevision,
      ),
      throwsA(isA<BattleV1Rejection>().having(
        (error) => error.code, 'code', 'session-changed',
      )),
    );
    auth.currentUser = TestUser('second');
    hold.complete();
    await assertion;
    expect(requests, 0);
  });

  test('unchanged idle refresh is nonblocking, single-flight and silent', () async {
    final hold = Completer<Map<String, dynamic>>();
    var requests = 0, notifications = 0;
    final controller = _controller(_Storage().store(), request: (_, _) {
      requests++;
      return hold.future;
    });
    addTearDown(controller.dispose);
    controller.addListener(() => notifications++);
    final first = controller.reconnect(synchronization: false);
    final second = controller.reconnect(synchronization: false);
    expect(identical(first, second), isTrue);
    expect(controller.busy, isFalse);
    expect(controller.refreshing, isTrue);
    expect(requests, 1);
    hold.complete(v1Response());
    await first;
    expect(controller.refreshing, isFalse);
    expect(notifications, 0);
  });

  test('resume coalesces idle refresh while preserving its synchronization epoch', () async {
    final hold = Completer<Map<String, dynamic>>();
    var requests = 0;
    final controller = _controller(_Storage().store(), request: (_, _) {
      requests++;
      return hold.future;
    });
    addTearDown(controller.dispose);
    final idle = controller.reconnect(synchronization: false);
    final resume = controller.reconnect();
    expect(identical(idle, resume), isTrue);
    hold.complete(v1Response());
    await resume;
    expect(requests, 1);
    expect(controller.synchronizationEpoch, 1);
  });

  test('submission waits for idle refresh and uses its authoritative version', () async {
    final hold = Completer<Map<String, dynamic>>();
    final paths = <String>[];
    Map<String, dynamic>? sent;
    final controller = _controller(_Storage().store(), request: (path, body) {
      paths.add(path);
      if (path == '/getBattleV1') return hold.future;
      sent = Map.of(body);
      return Future.value(v1Response(version: 2));
    });
    addTearDown(controller.dispose);
    final idle = controller.reconnect(synchronization: false);
    final action = controller.submit(const ChessMoveAction('e2e4'));
    expect(paths, ['/getBattleV1']);
    hold.complete(v1Response(version: 1));
    await idle;
    expect(await action, isTrue);
    expect(sent!['expectedStateVersion'], 1);
    expect(paths, ['/getBattleV1', '/submitBattleV1Action']);
  });

  test('idle refresh failure prevents a waiting submission', () async {
    final hold = Completer<Map<String, dynamic>>();
    var requests = 0;
    final controller = _controller(_Storage().store(), request: (_, _) {
      requests++;
      return hold.future;
    });
    addTearDown(controller.dispose);
    final idle = controller.reconnect(synchronization: false);
    final action = controller.submit(const ChessMoveAction('e2e4'));
    hold.completeError(StateError('network failed'));
    await idle;
    expect(await action, isFalse);
    expect(requests, 1);
    expect(controller.hasPendingIntent, isFalse);
  });

  test('initial server timestamp charges time already elapsed before reconnect', () {
    final response = v1Response()..['serverNow'] = 10000;
    final clock = ((response['view'] as Map)['public'] as Map)['clock'] as Map;
    clock['startedAt'] = 1000;
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: response,
      request: (_, _) async => response,
      persistPending: (_) async {},
    );
    addTearDown(controller.dispose);
    expect(controller.remainingMillis('w'), lessThanOrEqualTo(291000));
    expect(controller.remainingMillis('b'), 300000);
  });

  test('service clock sample is monotonic and scoped to its account', () async {
    final auth = TestAuth();
    var timestamp = 10000;
    final service = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
      appCheck: () async => 'check',
      client: MockClient((_) async => http.Response(jsonEncode({
        'ok': true,
        'matchId': v1MatchId,
        'serverNow': timestamp,
        'view': {},
      }), 200)),
    );
    addTearDown(service.dispose);
    await service.start();
    await service.battleV1Api('/getBattleV1', {});
    final first = service.battleV1ServerNow(v1MatchId)!;
    timestamp = 5000;
    await service.battleV1Api('/getBattleV1', {});
    expect(service.battleV1ServerNow(v1MatchId), greaterThanOrEqualTo(first));
    auth.currentUser = TestUser('second');
    expect(service.battleV1ServerNow(v1MatchId), isNull);
  });

}
