import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';

import 'helpers/battle_v1_response.dart';

String _savedIntent() => jsonEncode({
  'matchId': v1MatchId,
  'protocolVersion': battleV1Protocol,
  'expectedStateVersion': 0,
  'actionId': 'a0_0123456789abcdef0123456789abcdef',
  'intent': const ChessMoveAction('e2e4').toJson(),
});

void _expectInvalidated(BattleV1Controller controller) {
  expect(controller.snapshot, isNull);
  expect(controller.view, isNull);
  expect(controller.legalActions, isEmpty);
  expect(controller.remainingMillis('w'), 0);
  expect(controller.busy, isFalse);
  expect(
    controller.error,
    isA<BattleV1Rejection>().having(
      (error) => error.code,
      'code',
      'session-changed',
    ),
  );
}

void main() {
  for (final operation in ['reconnect', 'retryPending']) {
    for (final explicitInvalidation in [false, true]) {
      test('$operation stops I/O after a start listener invalidates ownership: '
          'explicit=$explicitInvalidation', () async {
        var current = true, requests = 0;
        final writes = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: v1Response(),
          pendingJson: operation == 'retryPending' ? _savedIntent() : null,
          pendingPersisted: false,
          isSessionCurrent: () => current,
          persistPending: (value) async => writes.add(value),
          request: (_, _) async {
            requests++;
            return v1Response(version: 1);
          },
        );
        addTearDown(controller.dispose);
        controller.addListener(() {
          if (!controller.busy) return;
          current = false;
          if (explicitInvalidation) controller.invalidateSession();
        });

        if (operation == 'reconnect') {
          await controller.reconnect();
        } else {
          await controller.retryPending();
        }

        _expectInvalidated(controller);
        expect(controller.refreshing, isFalse);
        expect(requests, 0);
        expect(writes, isEmpty);
        expect(controller.hasPendingIntent, operation == 'retryPending');
        current = true;
        await controller.reconnect();
        await controller.retryPending();
        expect(requests, 0);
        expect(writes, isEmpty);
        _expectInvalidated(controller);
      });
    }
  }

  for (final operation in [
    'reconnect',
    'submit',
    'retryPending',
    'resign',
    'clearRejectedPending',
  ]) {
    test('$operation invalidates a session lost before entry', () async {
      var current = true, requests = 0, notifications = 0;
      final writes = <String?>[];
      final saved =
          operation == 'retryPending' || operation == 'clearRejectedPending'
              ? _savedIntent()
              : null;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(),
        pendingJson: saved,
        isSessionCurrent: () => current,
        persistPending: (value) async => writes.add(value),
        request: (_, _) async {
          requests++;
          return v1Response(version: 1);
        },
      );
      addTearDown(controller.dispose);
      controller.addListener(() => notifications++);
      expect(controller.view, isNotNull);
      current = false;

      switch (operation) {
        case 'reconnect':
          await controller.reconnect();
        case 'submit':
          expect(
            await controller.submit(const ChessMoveAction('e2e4')),
            isFalse,
          );
        case 'retryPending':
          await controller.retryPending();
        case 'resign':
          await controller.resign();
        case 'clearRejectedPending':
          await controller.clearRejectedPending();
      }

      _expectInvalidated(controller);
      expect(controller.hasPendingIntent, saved != null);
      expect(notifications, 1);
      expect(requests, 0);
      expect(writes, isEmpty);

      current = true;
      await controller.reconnect();
      await controller.retryPending();
      expect(await controller.submit(const ChessMoveAction('e2e4')), isFalse);
      await controller.resign();
      await controller.clearRejectedPending();
      _expectInvalidated(controller);
      expect(controller.hasPendingIntent, saved != null);
      expect(notifications, 1);
      expect(requests, 0);
      expect(writes, isEmpty);
    });
  }

  for (final failure in [false, true]) {
    test(
      'preflight invalidation ignores a late refresh: failure=$failure',
      () async {
        var current = true, requests = 0, notifications = 0;
        final response = Completer<Map<String, dynamic>>();
        final writes = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: v1Response(),
          pendingJson: _savedIntent(),
          isSessionCurrent: () => current,
          persistPending: (value) async => writes.add(value),
          request: (_, _) {
            requests++;
            return response.future;
          },
        );
        addTearDown(controller.dispose);
        controller.addListener(() => notifications++);
        final refreshing = controller.reconnect(synchronization: false);
        expect(controller.refreshing, isTrue);
        current = false;

        final retrying = controller.retryPending();
        current = true;
        if (failure) {
          response.completeError(StateError('late network failure'));
        } else {
          response.complete(v1Response(version: 9));
        }
        await refreshing;
        await retrying;

        _expectInvalidated(controller);
        expect(controller.refreshing, isFalse);
        expect(controller.synchronizationEpoch, 0);
        expect(controller.hasPendingIntent, isTrue);
        expect(notifications, 1);
        expect(requests, 1);
        expect(writes, isEmpty);
      },
    );
  }

  test('preflight invalidation preserves an in-flight saved action', () async {
    var current = true, requests = 0;
    final started = Completer<void>();
    final response = Completer<Map<String, dynamic>>();
    final writes = <String?>[];
    final controller = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: v1Response(),
      isSessionCurrent: () => current,
      persistPending: (value) async => writes.add(value),
      request: (_, _) {
        requests++;
        started.complete();
        return response.future;
      },
    );
    addTearDown(controller.dispose);
    final submitting = controller.submit(const ChessMoveAction('e2e4'));
    await started.future;
    expect(writes, hasLength(1));
    expect(writes.single, isNotNull);
    current = false;

    await controller.reconnect();
    _expectInvalidated(controller);
    current = true;
    response.complete(v1Response(version: 1));
    expect(await submitting, isFalse);
    await controller.retryPending();

    _expectInvalidated(controller);
    expect(controller.hasPendingIntent, isTrue);
    expect(requests, 1);
    expect(writes, hasLength(1));
    expect(writes.single, isNotNull);
  });
}
