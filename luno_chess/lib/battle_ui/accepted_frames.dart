import '../battle_v1/model.dart';

class BattleAcceptedFrame {
  final int sequence;
  final PlayerView before, after;
  const BattleAcceptedFrame(this.sequence, this.before, this.after);
}

/// An empty/replaced history is a new baseline, not continuity for pending VFX.
bool battleAcceptedHistoryReset(
  List<BattleAcceptedFrame>? before,
  List<BattleAcceptedFrame>? after,
) =>
    before != null &&
    before.isNotEmpty &&
    after != null &&
    (after.isEmpty || after.last.sequence < before.last.sequence);

/// Retain accepted projection deltas even when Flutter combines several updates
/// into one build. A reconnect establishes a baseline, never replays history.
class BattlePresentationTracker {
  PlayerView? _previous;
  int? _version, _epoch;
  int _sequence = 0;
  final List<BattleAcceptedFrame> _frames = [];

  List<BattleAcceptedFrame> get frames => List.unmodifiable(_frames);

  void reset() {
    _previous = null;
    _version = _epoch = null;
    _frames.clear();
  }

  void observe(PlayerView next, int version, {int epoch = 0}) {
    if (_version == version &&
        _epoch == epoch &&
        _previous?.viewer == next.viewer) {
      return;
    }
    final before = _previous, previousVersion = _version;
    final synchronized = _epoch != epoch;
    _previous = next;
    _version = version;
    _epoch = epoch;
    if (before == null ||
        synchronized ||
        before.viewer != next.viewer ||
        previousVersion == null ||
        version != previousVersion + 1 ||
        next.rules.ply < before.rules.ply ||
        next.rules.effectSequence < before.rules.effectSequence) {
      _frames.clear();
      return;
    }
    if (before.rules.terminal != null) return;
    _frames.add(BattleAcceptedFrame(++_sequence, before, next));
    if (_frames.length > 6) _frames.removeAt(0);
  }
}
