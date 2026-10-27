import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import '../helpers/battle_v1_response.dart';

void main() {
  test('snapshot accepts only public and own private paired versions', () {
    final s = BattleV1Snapshot.fromResponse(v1Response(), 'self');
    expect(s.player.ownHand, hasLength(3));
    expect(s.stateVersion, 0);
  });
  for (final field in ['decks', 'hands', 'hidden', 'shuffleSeed']) {
    test('snapshot rejects secret field $field', () {
      final r = v1Response(), p = (r['view'] as Map)['public'] as Map;
      p[field] = {};
      expect(
        () => BattleV1Snapshot.fromResponse(r, 'self'),
        throwsFormatException,
      );
    });
  }
  test('wrong account, legacy protocol and mixed projections are rejected', () {
    for (final kind in [
      'account',
      'protocol',
      'version',
      'knowledge',
      'clock',
    ]) {
      final r = v1Response(),
          v = r['view'] as Map,
          p = v['public'] as Map,
          own = v['private'] as Map;
      switch (kind) {
        case 'account':
          own['viewer'] = 'b';
        case 'protocol':
          p['protocolVersion'] = 'legacy';
        case 'version':
          own['stateVersion'] = 1;
        case 'knowledge':
          own['knowledgeJson'] = '{"deck":["radar"]}';
        case 'clock':
          p['clock'] = {};
      }
      expect(
        () => BattleV1Snapshot.fromResponse(r, 'self'),
        throwsA(isA<Exception>()),
        reason: kind,
      );
    }
  });
  test(
    'reconnect never replays cards or draws; older response cannot roll state back',
    () async {
      var version = 2;
      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        request: (_, _) async => v1Response(version: version),
        persistPending: (_) async {},
      );
      await c.reconnect();
      final before = jsonEncode(c.view!.toJson());
      version = 1;
      await c.reconnect();
      expect(c.snapshot!.stateVersion, 2);
      expect(jsonEncode(c.view!.toJson()), before);
      c.dispose();
    },
  );
  test(
    'lost response/process death resends same ID rather than generating another action',
    () async {
      String? saved;
      final bodies = <Map<String, dynamic>>[];
      var fail = true;
      Future<Map<String, dynamic>> send(
        String path,
        Map<String, dynamic> body,
      ) async {
        bodies.add(Map.of(body));
        if (fail) throw StateError('connection lost');
        return v1Response(version: 1);
      }

      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(),
        request: send,
        persistPending: (s) async => saved = s,
      );
      await c.submit(const ChessMoveAction('e2e4'));
      expect(c.hasPendingIntent, true);
      c.dispose();
      fail = false;
      final recovered = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        pendingJson: saved,
        request: send,
        persistPending: (s) async => saved = s,
      );
      await recovered.retryPending();
      expect(bodies[0], bodies[1]);
      expect(recovered.hasPendingIntent, false);
      expect(saved, isNull);
      recovered.dispose();
    },
  );
  test(
    'definite server rejection clears pending, transient failure retains it',
    () async {
      for (final code in [
        'STALE_STATE',
        'INVALID_ACTION',
        'MATCH_TIMEOUT',
        'TEMPORARILY_UNAVAILABLE',
      ]) {
        String? saved;
        final c = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: v1Response(),
          request: (_, _) async => throw BattleV1Rejection(code),
          persistPending: (s) async => saved = s,
        );
        await c.submit(const ChessMoveAction('e2e4'));
        expect(c.hasPendingIntent, code == 'TEMPORARILY_UNAVAILABLE');
        expect(saved != null, code == 'TEMPORARILY_UNAVAILABLE');
        c.dispose();
      }
    },
  );
  test('persistence failure must not send an unrecorded intent', () async {
    var calls = 0;
    final c = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      initialResponse: v1Response(),
      request: (_, _) async {
        calls++;
        return v1Response();
      },
      persistPending: (_) async => throw StateError('disk full'),
    );
    await c.submit(const ChessMoveAction('e2e4'));
    expect(calls, 0);
    expect(c.error, isA<StateError>());
    expect(c.hasPendingIntent, true);
    c.dispose();
  });
  test(
    'disposed controller cannot expose a delayed account response',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        request: (_, _) => pending.future,
        persistPending: (_) async {},
      );
      final running = c.reconnect();
      c.dispose();
      pending.complete(v1Response());
      await running;
      expect(c.snapshot, isNull);
    },
  );
  test('malformed pending JSON cannot block canonical reconnect', () async {
    final c = BattleV1Controller(
      uid: 'self',
      matchId: v1MatchId,
      pendingJson: '{broken',
      request: (_, _) async => v1Response(),
      persistPending: (_) async {},
    );
    await c.reconnect();
    expect(c.snapshot, isNotNull);
    expect(c.hasPendingIntent, false);
    c.dispose();
  });
  test(
    'nullable core intent fields are omitted at strict network boundary',
    () async {
      var battle = DeckManager.newBattle(
        white: starterDeck,
        black: starterDeck,
      );
      battle = DeckManager.apply(battle, const ChessMoveAction('e2e4'));
      battle = DeckManager.apply(battle, const ChessMoveAction('e7e5'));
      Map<String, dynamic>? sent;
      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(state: battle),
        request: (_, body) async {
          sent = body;
          return v1Response(state: battle, version: 1);
        },
        persistPending: (_) async {},
      );
      final play = c.legalActions.whereType<PlayCardAction>().first;
      await c.submit(play);
      expect(sent, isNotNull);
      expect((sent!['intent'] as Map).values, isNot(contains(null)));
      expect((sent!['intent'] as Map).keys, isNot(contains('sacrifice')));
      c.dispose();
    },
  );
  test(
    'resignation persists and uses a separate strict intent endpoint',
    () async {
      String? saved;
      String? path;
      Map<String, dynamic>? payload;
      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(),
        request: (p, b) async {
          path = p;
          payload = b;
          expect(saved, isNotNull);
          return v1Response(version: 1);
        },
        persistPending: (s) async => saved = s,
      );
      await c.resign();
      expect(path, '/resignBattleV1');
      expect(payload!.keys, isNot(contains('intent')));
      expect(saved, isNull);
      c.dispose();
    },
  );
}
