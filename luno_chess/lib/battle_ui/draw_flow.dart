import '../battle_v1/model.dart';
import '../engine/piece.dart';

enum BattleArrivalKind { draw, exchange }

class BattleDrawNotice {
  final int version;
  final CardId? ownCard;
  final BattleArrivalKind kind;
  final bool opponent;
  const BattleDrawNotice(
    this.version, {
    this.ownCard,
    this.kind = BattleArrivalKind.draw,
    this.opponent = false,
  });
}

/// Presentation-only deltas from redacted, version-paired player projections.
/// A synchronization boundary establishes a baseline, never replays history.
class BattleDrawTracker {
  PlayerView? _previous;
  int? _version, _epoch;
  BattleDrawNotice? notice;

  void reset() {
    _previous = null;
    _version = _epoch = null;
    notice = null;
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
    notice = null;
    if (before == null ||
        synchronized ||
        before.viewer != next.viewer ||
        previousVersion == null ||
        version != previousVersion + 1 ||
        before.rules.terminal != null ||
        next.rules.terminal != null) {
      return;
    }
    final side = next.viewer;
    final added =
        next.ownHand.where((card) => !before.ownHand.contains(card)).toList();
    final exchanged =
        before.rules.pending?.owner == side &&
        before.rules.pending?.card == CardId.fateExchange &&
        next.rules.pending == null &&
        next.rules.ply == before.rules.ply &&
        next.rules.deckCounts[side] == before.rules.deckCounts[side]! - 1 &&
        next.rules.drawCounts[side] == before.rules.drawCounts[side]! + 1 &&
        added.length == 1 &&
        next.ownHand.length == before.ownHand.length + 1;
    if (exchanged) {
      notice = BattleDrawNotice(
        version,
        ownCard: added.single,
        kind: BattleArrivalKind.exchange,
      );
      return;
    }
    if (next.rules.ply != before.rules.ply + 1) return;
    bool drew(PieceColor player) =>
        next.rules.drawCounts[player] == before.rules.drawCounts[player]! + 1 &&
        next.rules.deckCounts[player] == before.rules.deckCounts[player]! - 1 &&
        next.rules.handCounts[player] == before.rules.handCounts[player]! + 1;
    if (drew(side) && added.length == 1) {
      notice = BattleDrawNotice(version, ownCard: added.single);
    } else if (drew(side.opposite)) {
      notice = BattleDrawNotice(version, opponent: true);
    }
  }
}
