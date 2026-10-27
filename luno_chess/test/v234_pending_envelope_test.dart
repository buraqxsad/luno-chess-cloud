import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/battle_v1/pending_store.dart';

import 'helpers/battle_v1_response.dart';

Map<String, dynamic> _envelope({
  Object? version = 0,
  Object? actionId = 'a0_0123456789abcdef0123456789abcdef',
  Object? intent = const {'type': 'move', 'uci': 'e2e4'},
}) => {
  'matchId': v1MatchId,
  'protocolVersion': battleV1Protocol,
  'expectedStateVersion': version,
  'actionId': actionId,
  'intent': intent,
};

class _SavedSlot {
  String? json;
  bool removeSucceeds = true;
  int writes = 0, removals = 0;

  _SavedSlot(Map<String, dynamic> envelope) : json = jsonEncode(envelope);

  BattleV1PendingStore store() => BattleV1PendingStore.forTesting(
    storageIdentity: this,
    uid: 'self',
    matchId: v1MatchId,
    read: (_) => json,
    write: (_, value) async {
      writes++;
      json = value;
      return true;
    },
    remove: (_) async {
      removals++;
      if (!removeSucceeds) return false;
      json = null;
      return true;
    },
  );
}

BattleV1Controller _controller(
  BattleV1PendingStore store,
  BattleV1Request request,
) => BattleV1Controller(
  uid: 'self',
  matchId: v1MatchId,
  initialResponse: v1Response(),
  pendingJson: store.pendingJson,
  pendingPersisted: store.pendingPersisted,
  persistPending: store.persist,
  request: request,
);

void main() {
  final invalidEnvelopes = <String, Map<String, dynamic>>{
    'negative version': _envelope(
      version: -1,
      actionId: 'a-1_0123456789abcdef0123456789abcdef',
    ),
    'unsafe integer version': _envelope(
      version: 9007199254740992,
      actionId: 'a9007199254740992_0123456789abcdef',
    ),
    'fractional version': _envelope(version: 0.5),
    'string version': _envelope(version: '0'),
    'null version': _envelope(version: null),
    'truncated action ID': _envelope(actionId: 'a0_'),
    'eleven-character action ID': _envelope(actionId: 'a0_12345678'),
    'oversize action ID': _envelope(
      actionId: 'a0_${List.filled(78, 'x').join()}',
    ),
    'invalid action ID alphabet': _envelope(actionId: 'a0_12345678!'),
    'wrong version anchor': _envelope(actionId: 'a1_0123456789abcdef'),
    'ill-typed action ID': _envelope(actionId: 123456789012),
    'extra envelope field': {..._envelope(), 'extra': true},
    'missing intent': _envelope()..remove('intent'),
  };
  final invalidIntents = <String, Object?>{
    'missing type': <String, Object?>{},
    'unknown type': {'type': 'draw'},
    'ill-typed type': {'type': 1},
    'missing move UCI': {'type': 'move'},
    'ill-typed move UCI': {'type': 'move', 'uci': 1234},
    'invalid move square': {'type': 'move', 'uci': 'e2i4'},
    'invalid promotion': {'type': 'move', 'uci': 'e7e8k'},
    'extra move field': {'type': 'move', 'uci': 'e2e4', 'target': 28},
    'missing play card': {'type': 'play'},
    'ill-typed play card': {'type': 'play', 'card': 7},
    'oversize play card': {'type': 'play', 'card': List.filled(33, 'x').join()},
    'extra play field': {'type': 'play', 'card': 'radar', 'order': []},
    'negative target': {'type': 'play', 'card': 'radar', 'target': -1},
    'out-of-board target': {'type': 'play', 'card': 'radar', 'target': 64},
    'fractional target': {'type': 'play', 'card': 'radar', 'target': 1.5},
    'null target': {'type': 'play', 'card': 'radar', 'target': null},
    'boolean target': {'type': 'play', 'card': 'radar', 'target': true},
    'list target': {'type': 'play', 'card': 'radar', 'target': []},
    'object target': {'type': 'play', 'card': 'radar', 'target': {}},
    'oversize string target': {
      'type': 'play',
      'card': 'radar',
      'target': List.filled(81, 'x').join(),
    },
    'ill-typed sacrifice': {'type': 'play', 'card': 'radar', 'sacrifice': 3},
    'null sacrifice': {'type': 'play', 'card': 'radar', 'sacrifice': null},
    'missing discard card': {'type': 'discard'},
    'ill-typed discard card': {'type': 'discard', 'card': []},
    'oversize discard card': {
      'type': 'discard',
      'card': List.filled(33, 'x').join(),
    },
    'extra discard field': {'type': 'discard', 'card': 'radar', 'target': 0},
    'missing resolution order': {'type': 'resolve'},
    'ill-typed resolution order': {'type': 'resolve', 'order': 'radar'},
    'ill-typed resolution member': {
      'type': 'resolve',
      'order': [1],
    },
    'oversize resolution order': {
      'type': 'resolve',
      'order': ['radar', 'purify', 'freeze', 'mine'],
    },
    'duplicate resolution member': {
      'type': 'resolve',
      'order': ['radar', 'radar'],
    },
    'ill-typed selected card': {'type': 'resolve', 'order': [], 'selected': 1},
    'null selected card': {'type': 'resolve', 'order': [], 'selected': null},
    'extra resolution field': {'type': 'resolve', 'order': [], 'card': 'radar'},
    'extra pass field': {'type': 'pass', 'uci': 'e2e4'},
    'extra resign field': {'type': 'resign', 'uci': 'e2e4'},
    'null resign field': {'type': 'resign', 'card': null},
  };
  for (final entry in invalidIntents.entries) {
    invalidEnvelopes[entry.key] = _envelope(intent: entry.value);
  }

  for (final entry in invalidEnvelopes.entries) {
    test('invalid saved envelope is cleanup-only: ${entry.key}', () async {
      final slot = _SavedSlot(entry.value);
      final store = slot.store();
      var requests = 0;
      final controller = _controller(store, (_, _) async {
        requests++;
        return v1Response(version: 1);
      });
      addTearDown(controller.dispose);

      await controller.retryPending();
      expect(requests, 0);
      expect(slot.writes, 0);
      expect(slot.removals, 1);
      expect(slot.json, isNull);
      expect(store.pendingJson, isNull);
      expect(controller.hasPendingIntent, isFalse);
      expect(controller.error, isNull);
      expect(controller.snapshot!.stateVersion, 0);
    });
  }

  final validEnvelopes = <String, Map<String, dynamic>>{
    'move': _envelope(),
    'promotion': _envelope(intent: {'type': 'move', 'uci': 'e7e8q'}),
    'play without optional fields': _envelope(
      intent: {'type': 'play', 'card': 'radar'},
    ),
    'play numeric target': _envelope(
      intent: {'type': 'play', 'card': 'freeze', 'target': 0},
    ),
    'play integral JSON double target': _envelope(
      intent: {'type': 'play', 'card': 'freeze', 'target': 63.0},
    ),
    'play string target and sacrifice': _envelope(
      intent: {
        'type': 'play',
        'card': 'shadow_contract',
        'target': 'radar',
        'sacrifice': 'purify',
      },
    ),
    'play server string boundaries': _envelope(
      intent: {
        'type': 'play',
        'card': List.filled(32, 'c').join(),
        'target': List.filled(80, 't').join(),
        'sacrifice': List.filled(90, 's').join(),
      },
    ),
    'discard': _envelope(intent: {'type': 'discard', 'card': 'radar'}),
    'resolve': _envelope(
      intent: {
        'type': 'resolve',
        'order': ['radar', 'purify', 'freeze'],
        'selected': 'purify',
      },
    ),
    'resolve without selected': _envelope(
      intent: {
        'type': 'resolve',
        'order': ['radar'],
      },
    ),
    'resolve empty order': _envelope(intent: {'type': 'resolve', 'order': []}),
    'pass': _envelope(intent: {'type': 'pass'}),
    'resign': _envelope(
      actionId: 'a0_resign_12345678',
      intent: {'type': 'resign'},
    ),
    'minimum action ID length': _envelope(actionId: 'a0_123456789'),
    'maximum action ID length': _envelope(
      actionId: 'a0_${List.filled(77, 'x').join()}',
    ),
    'non-hex action ID': _envelope(actionId: 'a0_Recovered-ID_1234'),
    'integral JSON double version': _envelope(
      version: 7.0,
      actionId: 'a7_Recovered-ID_1234',
    ),
    'maximum safe version': _envelope(
      version: 9007199254740991,
      actionId: 'a9007199254740991_Recovered-ID',
    ),
  };
  for (final entry in validEnvelopes.entries) {
    test(
      'server-valid saved envelope preserves its ID: ${entry.key}',
      () async {
        final slot = _SavedSlot(entry.value);
        final original = jsonDecode(slot.json!) as Map<String, dynamic>;
        final expected = Map<String, dynamic>.from(original);
        final resign = (original['intent'] as Map)['type'] == 'resign';
        if (resign) expected.remove('intent');
        final requests = <(String, Map<String, dynamic>)>[];
        final controller = _controller(slot.store(), (path, body) async {
          requests.add((path, Map.of(body)));
          expect(slot.json, isNotNull);
          return v1Response(version: 1);
        });
        addTearDown(controller.dispose);

        await controller.retryPending();
        expect(requests, hasLength(1));
        expect(
          requests.single.$1,
          resign ? '/resignBattleV1' : '/submitBattleV1Action',
        );
        expect(requests.single.$2, expected);
        expect(requests.single.$2['actionId'], original['actionId']);
        expect(slot.writes, 0);
        expect(slot.removals, 1);
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
      },
    );
  }

  test(
    'invalid resign cleanup failure never dispatches a resignation',
    () async {
      final slot = _SavedSlot(
        _envelope(intent: {'type': 'resign', 'uci': 'e2e4'}),
      )..removeSucceeds = false;
      final store = slot.store();
      final paths = <String>[];
      final controller = _controller(store, (path, _) async {
        paths.add(path);
        return v1Response(version: path == '/getBattleV1' ? 0 : 1);
      });
      addTearDown(controller.dispose);

      await controller.reconnect();
      await controller.retryPending();
      expect(paths, ['/getBattleV1']);
      expect(controller.error, isA<BattleV1PendingStorageException>());
      expect(controller.hasPendingIntent, isTrue);
      expect(slot.json, isNotNull);
      expect(await controller.submit(const ChessMoveAction('e2e4')), isFalse);
      await controller.resign();
      expect(paths, ['/getBattleV1']);

      slot.removeSucceeds = true;
      await controller.retryPending();
      expect(paths, ['/getBattleV1']);
      expect(controller.hasPendingIntent, isFalse);
      expect(controller.error, isNull);
      expect(store.pendingJson, isNull);
      expect(await controller.submit(const ChessMoveAction('e2e4')), isTrue);
      expect(paths, ['/getBattleV1', '/submitBattleV1Action']);
    },
  );
}
