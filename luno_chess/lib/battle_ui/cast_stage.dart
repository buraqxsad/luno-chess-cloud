import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import 'cards.dart';
import 'card_motion.dart';
import 'feedback.dart';
import 'spell_vfx.dart';
import 'effect_timing.dart';
import 'accepted_frames.dart';
import 'cast_trail.dart';

Offset battleCastPoint(Offset from, Offset to, double progress) {
  final t = Curves.easeInOutCubic.transform(progress.clamp(0, 1));
  final lift = math.min(90.0, (to - from).distance * .22);
  return Offset.lerp(from, to, t)! - Offset(0, math.sin(t * math.pi) * lift);
}

class _CardFlight {
  final CardId card;
  final Offset from, to;
  final double arrivalScale;
  final int startedAt;
  final String key;
  final BattleSpellCue cue;
  const _CardFlight(
    this.card,
    this.from,
    this.to,
    this.arrivalScale,
    this.startedAt,
    this.key,
    this.cue,
  );
}

/// Presentation only. Origins are measured before a used card leaves the hand;
/// targets come only from the accepted player projection, never a pending tap.
class BattleCastStage extends StatefulWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final GlobalKey board, own, opponent;
  final Map<CardId, GlobalKey> cards;
  final Widget child;
  final int synchronizationEpoch;
  const BattleCastStage({
    super.key,
    required this.view,
    this.acceptedFrames,
    required this.board,
    required this.own,
    required this.opponent,
    required this.cards,
    required this.child,
    this.synchronizationEpoch = 0,
  });
  @override
  State<BattleCastStage> createState() => _BattleCastStageState();
}

class _BattleCastStageState extends State<BattleCastStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _surface = GlobalKey();
  final _origins = <CardId, Offset>{};
  late final AnimationController _motion;
  List<_CardFlight> _flights = const [];
  int _generation = 0;
  int _flightSequence = 0;
  int _lastAcceptedSequence = 0;
  bool _foreground = true, _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _lastAcceptedSequence = widget.acceptedFrames?.lastOrNull?.sequence ?? 0;
    _motion = AnimationController(
      vsync: this,
      duration: battleEffectDuration(CardId.boardSeal),
    );
  }

  RenderBox? _box(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  Offset? _center(GlobalKey key) {
    final box = _box(key), surface = _box(_surface);
    if (box == null || surface == null) return null;
    return surface.globalToLocal(
      box.localToGlobal(box.size.center(Offset.zero)),
    );
  }

  bool get _enabled =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  void _clear() {
    _generation++;
    _motion.stop();
    _flights = const [];
    _origins.clear();
  }

  void _measure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _captureHand(widget.view.ownHand);
    });
  }

  void _captureHand(Iterable<CardId> hand) {
    for (final card in hand) {
      final key = widget.cards[card];
      final point = key == null ? null : _center(key);
      if (point != null) _origins[card] = point;
    }
  }

  @override
  void didUpdateWidget(BattleCastStage old) {
    super.didUpdateWidget(old);
    if (old.synchronizationEpoch != widget.synchronizationEpoch ||
        battleAcceptedHistoryReset(old.acceptedFrames, widget.acceptedFrames) ||
        !_enabled ||
        old.view.viewer != widget.view.viewer ||
        widget.view.rules.terminal != null ||
        widget.view.rules.ply < old.view.rules.ply ||
        widget.view.rules.effectSequence < old.view.rules.effectSequence) {
      _clear();
      _lastAcceptedSequence =
          widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
      return;
    }
    _captureHand(old.view.ownHand);
    final frames =
        widget.acceptedFrames == null
            ? [BattleAcceptedFrame(0, old.view, widget.view)]
            : widget.acceptedFrames!
                .where((frame) => frame.sequence > _lastAcceptedSequence)
                .toList();
    _lastAcceptedSequence =
        widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
    final casts = [
      for (final frame in frames)
        if (frame.before.viewer == widget.view.viewer &&
            frame.after.viewer == widget.view.viewer)
          for (final cast in acceptedBattleCasts(frame.before, frame.after))
            (
              card: cast.card,
              side: cast.side,
              cue: BattleSpellCue.fromViews(
                cast.card,
                cast.side,
                frame.before,
                frame.after,
              ),
            ),
    ];
    if (casts.isEmpty) return;
    final generation = ++_generation;
    final origins = Map<CardId, Offset>.of(_origins);
    final after = widget.view;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || !_enabled) return;
      final board = _box(widget.board), surface = _box(_surface);
      if (board == null || surface == null) return;
      final own = _center(widget.own), opponent = _center(widget.opponent);
      final boardOrigin = surface.globalToLocal(
        board.localToGlobal(const Offset(6, 6)),
      );
      final cell = (board.size.shortestSide - 12) / 8;
      final flights = <_CardFlight>[];
      final elapsed =
          _motion.isAnimating
              ? (_motion.value * _motion.duration!.inMicroseconds).round()
              : 0;
      if (_motion.isAnimating) {
        flights.addAll(
          _flights.where(
            (flight) =>
                elapsed - flight.startedAt <
                battleEffectDuration(flight.card).inMicroseconds *
                    battleCastCardFadeEndFraction,
          ),
        );
      }
      for (final cast in casts) {
        final ours = cast.side == after.viewer;
        final from = ours ? origins[cast.card] ?? own : opponent;
        if (from == null) continue;
        final cue = cast.cue.following(after.rules);
        if (!cue.isActive) continue;
        final resourceSide =
            cue.resourceSide ??
            (cardDefinitions[cast.card]!.target == CardTargetType.opponentCard
                ? cast.side.opposite
                : cast.side);
        final to =
            cue.squares.isEmpty
                ? (resourceSide == after.viewer ? own : opponent)
                : boardOrigin +
                    cue.squares
                            .map(
                              (s) => battleSquareCenter(s, after.viewer, cell),
                            )
                            .reduce((a, b) => a + b) /
                        cue.squares.length.toDouble();
        if (to != null) {
          flights.add(
            _CardFlight(
              cast.card,
              from,
              to,
              cue.squares.isEmpty ? .4 : (cell * .82 / 76).clamp(.18, .7),
              elapsed,
              'card-flight-${cast.card.wire}${flights.any((flight) => flight.card == cast.card) ? '-${++_flightSequence}' : ''}',
              cue,
            ),
          );
        }
      }
      if (flights.isEmpty) return;
      final bounded = flights.skip(math.max(0, flights.length - 3)).toList();
      final end = bounded
          .map(
            (flight) =>
                flight.startedAt +
                battleEffectDuration(flight.card).inMicroseconds,
          )
          .reduce(math.max);
      _motion.duration = Duration(microseconds: end);
      setState(() => _flights = bounded);
      _motion.forward(from: elapsed / end);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled) _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    return Stack(
      key: _surface,
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (_, _) {
                    final t = _motion.value;
                    final elapsed = t * _motion.duration!.inMicroseconds;
                    double progressFor(_CardFlight flight) => ((elapsed -
                                flight.startedAt) /
                            battleEffectDuration(flight.card).inMicroseconds)
                        .clamp(0.0, 1.0);
                    if (t >= 1 || _flights.isEmpty || !_enabled) {
                      return const SizedBox.shrink();
                    }
                    return Stack(
                      children: [
                        for (final flight in _flights)
                          if (progressFor(flight) <
                                  battleCastCardFadeEndFraction &&
                              flight.cue.following(widget.view.rules).isActive)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: BattleCastTrailPainter(
                                  card: flight.card,
                                  from: flight.from,
                                  to: _destination(flight),
                                  progress: progressFor(flight),
                                  color: battleAbilityColor(flight.card),
                                ),
                              ),
                            ),
                        for (final flight in _flights)
                          if (progressFor(flight) <
                              battleCastCardFadeEndFraction)
                            _flight(flight, progressFor(flight)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _destination(_CardFlight flight) {
    var destination = flight.to;
    if (flight.cue.boundPieceIds.isNotEmpty) {
      final cue = flight.cue.following(widget.view.rules);
      final board = _box(widget.board), surface = _box(_surface);
      if (board != null && surface != null && cue.squares.isNotEmpty) {
        final origin = surface.globalToLocal(
          board.localToGlobal(const Offset(6, 6)),
        );
        final cell = (board.size.shortestSide - 12) / 8;
        destination =
            origin +
            cue.squares
                    .map(
                      (square) =>
                          battleSquareCenter(square, widget.view.viewer, cell),
                    )
                    .reduce((a, b) => a + b) /
                cue.squares.length.toDouble();
      }
    }
    return destination;
  }

  Widget _flight(_CardFlight flight, double t) {
    if (!flight.cue.following(widget.view.rules).isActive) {
      return const SizedBox.shrink();
    }
    final travel = battleTravelProgress(t);
    final destination = _destination(flight);
    final position = battleCardFlightPoint(
      flight.card,
      flight.from,
      destination,
      travel,
    );
    final motion = battleCardMotion(flight.card, travel);
    final scale =
        motion.scale *
        (1 + (flight.arrivalScale - 1) * Curves.easeInCubic.transform(travel));
    final fade = battleCastCardOpacity(t);
    final color = battleAbilityColor(flight.card);
    return Positioned(
      key: ValueKey(flight.key),
      left: position.dx - 29,
      top: position.dy - 38,
      width: 58,
      height: 76,
      child: Opacity(
        opacity: fade.clamp(0, 1),
        child: Transform(
          alignment: Alignment.center,
          transform:
              Matrix4.identity()
                ..setEntry(3, 2, .002)
                ..rotateY(motion.turn)
                ..rotateZ(motion.tilt)
                ..scaleByDouble(scale, scale, 1, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF0172930),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .38),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .3),
                  offset: const Offset(0, 5),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: BattleCardArt(card: flight.card),
            ),
          ),
        ),
      ),
    );
  }
}
