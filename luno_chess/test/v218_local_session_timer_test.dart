import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';

void main() {
  test('resignation cancels the local timeout poll before disposal', () {
    final timers = <Timer>[];
    final session = _sessionWithTimers(timers);
    try {
      expect(timers.single.isActive, isTrue);
      session.resign();
      expect(session.terminal?.reason, 'resign');
      expect(timers.single.isActive, isFalse);
      session.observe(true);
      expect(timers.where((timer) => timer.isActive), isEmpty);
    } finally {
      session.dispose();
    }
  });

  test('checkmate cancels the local timeout poll before disposal', () async {
    final timers = <Timer>[];
    final session = _sessionWithTimers(timers);
    try {
      expect(timers.single.isActive, isTrue);
      for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        if (session.view.rules.phase == BattlePhase.card) {
          expect(await session.submit(const PassAction()), isTrue);
        }
        expect(await session.submit(ChessMoveAction(uci)), isTrue);
      }
      expect(session.terminal?.reason, 'checkmate');
      expect(timers.single.isActive, isFalse);
    } finally {
      session.dispose();
    }
  });
}

BattleV1LocalSession _sessionWithTimers(List<Timer> timers) => runZoned(
  () => BattleV1LocalSession(hotseat: true),
  zoneSpecification: ZoneSpecification(
    createPeriodicTimer: (self, parent, zone, duration, callback) {
      final timer = parent.createPeriodicTimer(zone, duration, callback);
      timers.add(timer);
      return timer;
    },
  ),
);
