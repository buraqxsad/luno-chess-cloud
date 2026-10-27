import '../battle_v1/core.dart';
import '../battle_v1/model.dart';

/// UI-only reuse for immutable projections. Submission still validates afresh.
class BattleLegalActionCache {
  PlayerView? _view;
  List<BattleAction> _actions = const [];

  List<BattleAction> forView(PlayerView view) {
    final previous = _view;
    if (previous != null &&
        identical(previous.rules, view.rules) &&
        previous.viewer == view.viewer &&
        identical(previous.knowledge, view.knowledge) &&
        _sameHand(previous.ownHand, view.ownHand)) {
      return _actions;
    }
    final actions = List<BattleAction>.unmodifiable(
      BattleRulesCore.legalActions(view),
    );
    _view = view;
    _actions = actions;
    return actions;
  }

  bool _sameHand(List<CardId> before, List<CardId> after) {
    if (before.length != after.length) return false;
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) return false;
    }
    return true;
  }
}
