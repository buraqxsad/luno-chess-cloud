import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../engine/piece.dart';
import '../engine/ai.dart';
import 'authoritative.dart';
import 'bot_policy.dart';
import 'core.dart';
import 'local_clock.dart';
import 'model.dart';

String _chooseLocalChess((PlayerView, List<String>, AiLevel, int) input) {
  final (view, allowed, level, seed) = input;
  final board = view.rules.board;
  final moves =
      BattleRulesCore.legalMoves(
        view.rules,
        view.viewer,
        authorization: view.rules.special,
      ).where((m) => allowed.contains(m.uci)).toList();
  if (moves.isEmpty) return allowed.first;
  return AiEngine()
      .pickAmong(
        board,
        moves,
        level,
        Random(seed),
        budget: Duration(milliseconds: level.thinkBudgetMs),
      )
      .uci;
}

BattleAction? _chooseLocalCard((PlayerView, AiLevel, int) input) {
  final (view, level, seed) = input;
  return BattleV1BotPolicy.decide(view, level, Random(seed)).action;
}

/// Private local authority stays behind the same redacted boundary as online play.
class BattleV1LocalSession extends ChangeNotifier {
  late AuthoritativeBattleState _state;
  late BattleV1LocalClock _clock;
  final bool hotseat;
  final AiLevel level;
  final bool practice;
  final Duration Function(CardId)? cardFeedbackDelay;
  final Random _random;
  final Stopwatch _elapsed = Stopwatch()..start();
  Timer? _timeoutTimer;
  bool _closed = false, _botRunning = false, _active = true;
  int version = 0;
  void observe(bool active) {
    _active = active;
    _timeoutTimer?.cancel();
    if (_closed || !active) return;
    if (practice) {
      if (!hotseat && _state.rules.board.turn == PieceColor.black) {
        unawaited(_bot());
      }
      return;
    }
    checkTimeout();
    if (terminal == null) {
      _timeoutTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => checkTimeout(),
      );
    }
    if (!hotseat && _state.rules.board.turn == PieceColor.black) {
      unawaited(_bot());
    }
  }

  /// [clockNow] supplies monotonic milliseconds; normal play uses a Stopwatch.
  BattleV1LocalSession({
    this.hotseat = false,
    int minutes = 5,
    this.level = const AiLevel(
      id: 'bebek',
      name: 'Bebek Luno',
      desc: '',
      depth: 2,
      errorRate: .30,
      power: 100,
      rewardMult: .4,
      cardUseRate: .28,
      thinkBudgetMs: 30,
    ),
    this.practice = false,
    this.cardFeedbackDelay,
    List<CardId>? practiceDeck,
    List<CardId>? activeDeck,
    Random? random,
    int Function()? clockNow,
  }) : _random = random ?? Random.secure() {
    _state = DeckManager.newBattle(
      white:
          practiceDeck ??
          ([...(hotseat ? starterDeck : activeDeck ?? starterDeck)]
            ..shuffle(_random)),
      black: [...starterDeck]..shuffle(_random),
    );
    _clock = BattleV1LocalClock(
      now: clockNow ?? () => _elapsed.elapsedMilliseconds,
      minutes: minutes,
    );
    if (practice) _clock.stop();
    observe(true);
  }
  PlayerView get view => BattleV1BotPolicy.planningView(
    _state.view(hotseat ? _state.rules.board.turn : PieceColor.white),
  );
  TerminalState? get terminal => _state.rules.terminal;
  bool get busy => _botRunning;
  List<BattleAction> get legalActions =>
      terminal == null ? BattleRulesCore.legalActions(view) : const [];
  int remaining(PieceColor side) => _clock.remaining(side);
  void checkTimeout() {
    if (practice || _closed || terminal != null || !_clock.expired) return;
    _finish(TerminalState('timeout', winner: _clock.active.opposite));
  }

  void _finish(TerminalState result) {
    final draft =
        RuleDraft(_state.rules)
          ..phase = BattlePhase.terminal
          ..terminal = result
          ..pending = null
          ..special = null;
    // A finished match must not retain a private card-choice transaction.
    _state = AuthoritativeBattleState(
      draft.freeze(),
      AuthoritativeHiddenState(
        hands: _state.hidden.hands,
        decks: _state.hidden.decks,
        knowledge: {
          for (final side in PieceColor.values)
            side: _state.hidden.knowledge[side]!.copyWith(pendingCards: []),
        },
      ),
    );
    _clock.stop();
    _timeoutTimer?.cancel();
    version++;
    notifyListeners();
  }

  Future<bool> submit(BattleAction action) async {
    checkTimeout();
    if (_closed ||
        !_active ||
        terminal != null ||
        busy ||
        !BattleRulesCore.isLegalAction(view, action) ||
        !BattleRulesCore.isLegalAction(_state.view(view.viewer), action)) {
      return false;
    }
    if (!_apply(action)) return false;
    if (!hotseat &&
        terminal == null &&
        _state.rules.board.turn == PieceColor.black) {
      unawaited(_bot());
    }
    return true;
  }

  bool _apply(BattleAction action) {
    final next = DeckManager.apply(_state, action);
    final acting = _clock.active;
    _clock.advance(
      next.rules.board.turn,
      chessMove: action is ChessMoveAction,
      terminal: next.rules.phase == BattlePhase.terminal,
    );
    // Rule evaluation may cross flag fall; publish only a clock-accepted draft.
    if (!practice && _clock.ended && _clock.remaining(acting) == 0) {
      checkTimeout();
      return false;
    }
    _state = next;
    if (terminal != null) _timeoutTimer?.cancel();
    version++;
    notifyListeners();
    return true;
  }

  Future<void> _bot() async {
    if (_closed || !_active || _botRunning || terminal != null) return;
    _botRunning = true;
    notifyListeners();
    try {
      for (
        var i = 0;
        i < 4 &&
            !_closed &&
            _active &&
            terminal == null &&
            _state.rules.board.turn == PieceColor.black;
        i++
      ) {
        await Future<void>.delayed(
          Duration(milliseconds: practice ? 900 : 450),
        );
        if (_closed || !_active) return;
        checkTimeout();
        if (terminal != null) return;
        final botView = BattleV1BotPolicy.planningView(
          _state.view(PieceColor.black),
        );
        final legal = BattleRulesCore.legalActions(botView);
        BattleAction? action;
        final acceptedVersion = version;
        final chess = legal.whereType<ChessMoveAction>().toList();
        if (chess.isNotEmpty) {
          String uci;
          try {
            uci = await compute(_chooseLocalChess, (
              botView,
              chess.map((a) => a.uci).toList(),
              level,
              _random.nextInt(0x7fffffff),
            ));
          } catch (_) {
            // An unavailable worker must not strand a legal local turn.
            uci = chess.first.uci;
          }
          if (_closed || !_active || version != acceptedVersion) return;
          action = chess.firstWhere(
            (a) => a.uci == uci,
            orElse: () => chess.first,
          );
        } else {
          try {
            action = await compute(_chooseLocalCard, (
              botView,
              level,
              _random.nextInt(0x7fffffff),
            ));
          } catch (_) {
            // Worker failure is safe: do not invent an unvalidated card target.
            action =
                legal.whereType<PassAction>().firstOrNull ?? legal.firstOrNull;
          }
        }
        if (_closed || !_active || version != acceptedVersion) return;
        checkTimeout();
        if (terminal != null || action == null) return;
        final authorityLegal = BattleRulesCore.legalActions(
          _state.view(PieceColor.black),
        );
        if (!authorityLegal.any((a) => a.key == action!.key)) {
          // An unknown enemy mine can invalidate a placement. Authority still
          // decides legality; its concealed location is never fed to the policy.
          action = authorityLegal.whereType<PassAction>().firstOrNull;
        }
        if (action == null) return;
        final feedbackCard =
            action is PlayCardAction
                ? action.card
                : action is ResolveAction
                ? _state.rules.pending?.card
                : null;
        if (!_apply(action)) return;
        if (action is PlayCardAction || action is ResolveAction) {
          final delay =
              feedbackCard == null
                  ? Duration.zero
                  : cardFeedbackDelay?.call(feedbackCard) ?? Duration.zero;
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
        }
      }
    } finally {
      if (!_closed) {
        _botRunning = false;
        notifyListeners();
        if (_active &&
            terminal == null &&
            _state.rules.board.turn == PieceColor.black) {
          unawaited(_bot());
        }
      }
    }
  }

  void resign() {
    checkTimeout();
    if (_closed || terminal != null) return;
    _clock.stop();
    checkTimeout();
    if (_closed || terminal != null) return;
    _finish(TerminalState('resign', winner: view.viewer.opposite));
  }

  @override
  void dispose() {
    _closed = true;
    _timeoutTimer?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}
