import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/online.dart';

import 'helpers/battle_v1_response.dart';

void main() {
  test('initial response must belong to the controller match', () {
    expect(
      () => BattleV1Controller(
        uid: 'self',
        matchId: 'bv1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        initialResponse: v1Response(),
        request: (_, _) async => v1Response(),
        persistPending: (_) async {},
      ),
      throwsFormatException,
    );
  });

  test(
    'same-version older server timestamp cannot refund clock time',
    () async {
      final initial = v1Response()..['serverNow'] = 5000;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: initial,
        request: (_, _) async => v1Response(),
        persistPending: (_) async {},
      );
      addTearDown(controller.dispose);
      final before = controller.remainingMillis('w');
      await controller.reconnect();
      expect(controller.snapshot!.serverNow, 5000);
      expect(controller.remainingMillis('w'), lessThanOrEqualTo(before));
    },
  );

  test(
    'repeated cached snapshot cannot reset locally elapsed clock time',
    () async {
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(),
        request: (_, _) async => v1Response(),
        persistPending: (_) async {},
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final before = controller.remainingMillis('w');
      await controller.reconnect();
      expect(controller.remainingMillis('w'), lessThanOrEqualTo(before));
    },
  );

  test('clock snapshot is detached from mutable response data', () {
    final response = v1Response();
    final rawClock =
        ((response['view'] as Map)['public'] as Map)['clock'] as Map;
    final snapshot = BattleV1Snapshot.fromResponse(response, 'self');
    rawClock['w'] = 0;
    expect((snapshot.public['clock'] as Map)['w'], 300000);
    expect(
      () => (snapshot.public['clock'] as Map)['w'] = 0,
      throwsUnsupportedError,
    );
  });

  for (final kind in [
    'result',
    'winner',
    'players',
    'bot',
    'pieceIds',
    'counts',
    'serverNow',
    'startedAt',
  ]) {
    test('invalid snapshot boundary is rejected: $kind', () {
      final response = v1Response();
      final public = (response['view'] as Map)['public'] as Map;
      switch (kind) {
        case 'result':
          response['status'] = 'finished';
          public['result'] = 'finished';
        case 'winner':
          response['status'] = 'finished';
          public['result'] = {'reason': 'resign', 'winner': 'other'};
        case 'players':
          public['players'] = [];
        case 'bot':
          ((public['players'] as Map)['w'] as Map)['bot'] = true;
        case 'pieceIds':
        case 'counts':
          final rules = jsonDecode(public['rulesJson'] as String) as Map;
          if (kind == 'pieceIds') {
            rules['pieceIds'] = [];
          } else {
            (rules['handCounts'] as Map)['b'] = -1;
          }
          public['rulesJson'] = jsonEncode(rules);
        case 'serverNow':
          response['serverNow'] = -1;
        case 'startedAt':
          (public['clock'] as Map)['startedAt'] = -1;
      }
      expect(
        () => BattleV1Snapshot.fromResponse(response, 'self'),
        throwsFormatException,
      );
    });
  }
}
