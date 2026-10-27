import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/battle_v1/pending_store.dart';

import 'helpers/battle_v1_response.dart';

String _key(String uid) => 'battle_v1_pending:$uid:$v1MatchId';

String _savedIntent({String nonce = '0123456789abcdef0123456789abcdef'}) =>
    jsonEncode({
      'matchId': v1MatchId,
      'protocolVersion': battleV1Protocol,
      'expectedStateVersion': 0,
      'actionId': 'a0_$nonce',
      'intent': const ChessMoveAction('e2e4').toJson(),
    });

class _Storage {
  final values = <String, String>{};
  int writes = 0, removals = 0;
  bool removeSucceeds = true;
  Completer<void>? removalStarted;
  Future<void>? removalGate;

  BattleV1PendingStore store({String uid = 'self'}) =>
      BattleV1PendingStore.forTesting(
        storageIdentity: this,
        uid: uid,
        matchId: v1MatchId,
        read: (key) => values[key],
        write: (key, value) async {
          writes++;
          values[key] = value;
          return true;
        },
        remove: (key) async {
          removals++;
          final started = removalStarted;
          if (started != null && !started.isCompleted) started.complete();
          final gate = removalGate;
          if (gate != null) await gate;
          if (!removeSucceeds) return false;
          values.remove(key);
          return true;
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
  pendingJson: store.pendingJson,
  pendingPersisted: store.pendingPersisted,
  persistPending: store.persist,
  request: request,
  isSessionCurrent: owner,
);

void main() {
  final invalidIntents = {
    'malformed JSON': '{broken',
    'wrong shape': '[]',
    'wrong protocol': jsonEncode({
      ...jsonDecode(_savedIntent()) as Map<String, dynamic>,
      'protocolVersion': 'legacy',
    }),
    'wrong match': jsonEncode({
      ...jsonDecode(_savedIntent()) as Map<String, dynamic>,
      'matchId': 'bv1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    }),
  };

  for (final entry in invalidIntents.entries) {
    test('reconnect removes ${entry.key} before the next action', () async {
      final storage = _Storage()..values[_key('self')] = entry.value;
      final store = storage.store();
      final paths = <String>[];
      final controller = _controller(
        store,
        request: (path, body) async {
          paths.add(path);
          if (path == '/getBattleV1') return v1Response();
          expect(storage.values[_key('self')], jsonEncode(body));
          return v1Response(version: 1);
        },
      );
      addTearDown(controller.dispose);

      await controller.reconnect();
      expect(controller.snapshot, isNotNull);
      expect(controller.error, isNull);
      expect(controller.hasPendingIntent, isFalse);
      expect(store.pendingJson, isNull);
      expect(storage.values, isEmpty);
      expect(paths, ['/getBattleV1']);

      expect(await controller.submit(const ChessMoveAction('e2e4')), isTrue);
      expect(paths, ['/getBattleV1', '/submitBattleV1Action']);
      expect(storage.writes, 1);
      expect(storage.removals, 2);
      expect(store.pendingJson, isNull);
    });
  }

  test(
    'failed invalid-intent cleanup blocks dispatch and retries cleanup only',
    () async {
      final storage =
          _Storage()
            ..values[_key('self')] = '{broken'
            ..removeSucceeds = false;
      final store = storage.store();
      final paths = <String>[];
      final controller = _controller(
        store,
        request: (path, _) async {
          paths.add(path);
          return v1Response(version: path == '/getBattleV1' ? 0 : 1);
        },
      );
      addTearDown(controller.dispose);

      await controller.reconnect();
      expect(controller.snapshot, isNotNull);
      expect(controller.error, isA<BattleV1PendingStorageException>());
      expect(controller.hasPendingIntent, isTrue);
      expect(store.pendingJson, '{broken');
      expect(await controller.submit(const ChessMoveAction('e2e4')), isFalse);
      await controller.resign();
      expect(paths, ['/getBattleV1']);
      expect(storage.writes, 0);

      storage.removeSucceeds = true;
      await controller.retryPending();
      expect(controller.error, isNull);
      expect(controller.hasPendingIntent, isFalse);
      expect(store.pendingJson, isNull);
      expect(paths, ['/getBattleV1']);
      expect(storage.removals, 2);
      expect(await controller.submit(const ChessMoveAction('e2e4')), isTrue);
    },
  );

  test(
    'overlapping recovered owners can both finish the same saved action',
    () async {
      final storage = _Storage()..values[_key('self')] = _savedIntent();
      final firstResponse = Completer<Map<String, dynamic>>();
      final secondResponse = Completer<Map<String, dynamic>>();
      final bodies = <Map<String, dynamic>>[];
      final first = _controller(
        storage.store(),
        request: (_, body) {
          bodies.add(Map.of(body));
          return firstResponse.future;
        },
      );
      final second = _controller(
        storage.store(),
        request: (_, body) {
          bodies.add(Map.of(body));
          return secondResponse.future;
        },
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final firstRetry = first.retryPending();
      final secondRetry = second.retryPending();
      expect(bodies, hasLength(2));
      expect(bodies.first, bodies.last);
      firstResponse.complete(v1Response(version: 1));
      await firstRetry;
      secondResponse.complete(v1Response(version: 1));
      await secondRetry;

      for (final controller in [first, second]) {
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.snapshot!.stateVersion, 1);
        await controller.retryPending();
      }
      expect(bodies, hasLength(2));
      expect(storage.values, isEmpty);
      expect(storage.removals, 1);
    },
  );

  test('queued duplicate cleanup removes the saved action only once', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final storage =
        _Storage()
          ..removalGate = gate.future
          ..removalStarted = started;
    final store = storage.store();
    await store.persist(_savedIntent());
    final first = store.persist(null);
    await started.future;
    final second = store.persist(null);
    gate.complete();
    await Future.wait([first, second]);

    expect(storage.removals, 1);
    expect(storage.values, isEmpty);
    expect(store.pendingJson, isNull);
    expect(store.pendingPersisted, isFalse);
  });

  test('stale cleanup cannot remove a newer saved action', () async {
    final storage = _Storage()..values[_key('self')] = _savedIntent();
    final current = storage.store(), stale = storage.store();
    await current.persist(null);
    final newer = _savedIntent(nonce: 'fedcba9876543210fedcba9876543210');
    await current.persist(newer);

    await expectLater(
      stale.persist(null),
      throwsA(
        isA<BattleV1PendingStorageException>().having(
          (error) => error.operation,
          'operation',
          'action changed',
        ),
      ),
    );
    expect(current.pendingJson, newer);
    expect(storage.values[_key('self')], newer);
    expect(storage.removals, 1);
  });

  test('in-flight cleanup remains scoped to its original account', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final storage =
        _Storage()
          ..values[_key('self')] = _savedIntent()
          ..removalGate = gate.future
          ..removalStarted = started;
    final first = storage.store(), other = storage.store(uid: 'other');
    final cleanup = first.persist(null);
    await started.future;
    await other.persist('other-account-action');
    gate.complete();
    await cleanup;

    expect(first.pendingJson, isNull);
    expect(other.pendingJson, 'other-account-action');
    expect(storage.values, {_key('other'): 'other-account-action'});
  });

  test(
    'late invalid-intent cleanup cannot restore an invalidated session',
    () async {
      final gate = Completer<void>(), started = Completer<void>();
      final storage =
          _Storage()
            ..values[_key('self')] = '{broken'
            ..removalGate = gate.future
            ..removalStarted = started;
      var current = true, requests = 0;
      final controller = _controller(
        storage.store(),
        owner: () => current,
        request: (_, _) async {
          requests++;
          return v1Response();
        },
      );
      addTearDown(controller.dispose);
      final refreshing = controller.reconnect();
      await started.future;
      current = false;
      controller.invalidateSession();
      current = true;
      gate.complete();
      await refreshing;
      await controller.retryPending();

      expect(controller.snapshot, isNull);
      expect(controller.busy, isFalse);
      expect(controller.refreshing, isFalse);
      expect(
        controller.error,
        isA<BattleV1Rejection>().having(
          (error) => error.code,
          'code',
          'session-changed',
        ),
      );
      expect(requests, 1);
      expect(storage.writes, 0);
    },
  );

  test(
    'late active snapshot cannot revive a terminal match or its clock',
    () async {
      final terminal =
          v1Response(version: 2)
            ..['status'] = 'finished'
            ..['serverNow'] = 20000;
      final public = (terminal['view'] as Map)['public'] as Map;
      public['result'] = {'reason': 'timeout', 'winner': 'b'};
      (public['clock'] as Map)['w'] = 0;
      (public['clock'] as Map)['startedAt'] = 20000;
      final stale = v1Response(version: 1)..['serverNow'] = 90000;
      var requests = 0;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(version: 1)..['serverNow'] = 5000,
        persistPending: (_) async {},
        request: (_, _) async => requests++ == 0 ? terminal : stale,
      );
      addTearDown(controller.dispose);

      await controller.reconnect();
      await controller.reconnect();
      expect(controller.snapshot!.stateVersion, 2);
      expect(controller.snapshot!.result!['reason'], 'timeout');
      expect(controller.legalActions, isEmpty);
      expect(controller.remainingMillis('w'), 0);
      expect(controller.remainingMillis('b'), 300000);
    },
  );
}
