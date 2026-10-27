import '../engine/piece.dart';

/// Monotonic offline clock. This never grants server rewards or rating.
class BattleV1LocalClock {
  final int Function() now;
  final int incrementMillis;
  final Map<PieceColor, int> _remaining;
  PieceColor active = PieceColor.white;
  late int _startedAt;
  bool ended = false;
  BattleV1LocalClock({
    required this.now,
    int minutes = 5,
    this.incrementMillis = 2000,
  }) : _remaining = {
         for (final side in PieceColor.values) side: minutes * 60000,
       } {
    _startedAt = now();
  }
  int remaining(PieceColor side) {
    final elapsed =
        !ended && side == active
            ? (now() - _startedAt).clamp(0, 0x7fffffff)
            : 0;
    return (_remaining[side]! - elapsed).clamp(0, 0x7fffffff);
  }

  bool get expired => remaining(active) == 0;
  void advance(
    PieceColor next, {
    required bool chessMove,
    bool terminal = false,
  }) {
    if (ended) return;
    final charged = remaining(active);
    _remaining[active] = charged;
    if (charged == 0) {
      ended = true;
      return;
    }
    if (chessMove && next != active) {
      _remaining[active] = charged + incrementMillis;
    }
    active = next;
    _startedAt = now();
    ended = terminal;
  }

  void stop() {
    if (ended) return;
    _remaining[active] = remaining(active);
    _startedAt = now();
    ended = true;
  }
}
