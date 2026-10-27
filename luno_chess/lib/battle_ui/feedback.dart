import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../battle_v1/model.dart';
import '../battle_v1/core.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import '../theme/luno_visual_assets.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/battle_learning_copy.dart';
import 'cards.dart';
import 'art.dart';
import 'effects.dart';
import 'tokens.dart';
import 'spell_vfx.dart';
import 'effect_timing.dart';
import 'accepted_frames.dart';

List<({CardId card, PieceColor side})> acceptedBattleCasts(
  PlayerView before,
  PlayerView after,
) {
  if (before.viewer != after.viewer ||
      before.rules.terminal != null ||
      after.rules.ply < before.rules.ply ||
      after.rules.effectSequence < before.rules.effectSequence) {
    return const [];
  }
  for (final side in PieceColor.values) {
    if (before.rules.used[side]!.any(
      (card) => !after.rules.used[side]!.contains(card),
    )) {
      return const [];
    }
  }
  return [
    for (final side in PieceColor.values)
      for (final card in after.rules.used[side]!.toSet())
        if (!before.rules.used[side]!.contains(card)) (card: card, side: side),
  ];
}

List<CardId> acceptedBattleCards(PlayerView before, PlayerView after) =>
    acceptedBattleCasts(before, after).map((cast) => cast.card).toList();

typedef BattleVowPayoff = ({CardId card, PieceColor side, int square});

List<BattleVowPayoff> acceptedBattleVowPayoffs(
  PlayerView before,
  PlayerView after,
) {
  final old = before.rules, next = after.rules;
  if (before.viewer != after.viewer ||
      next.ply != old.ply + 1 ||
      next.effectSequence < old.effectSequence ||
      old.terminal != null) {
    return const [];
  }
  final mover = old.board.turn;
  final seen = <String>{};
  return [
    for (final vow in old.vows)
      if (seen.add(vow.id) &&
          vow.remainingMoves > 0 &&
          !next.vows.any((v) => v.id == vow.id))
        if (vow.type == VowType.hunt &&
            vow.owner == mover &&
            old.special == null &&
            vow.pieceId != null &&
            old.pieceIds.contains(vow.pieceId) &&
            old.pieceIds.indexOf(vow.pieceId) < 64 &&
            !next.pieceIds.contains(vow.pieceId))
          (
            card: CardId.huntVow,
            side: vow.owner,
            square: old.pieceIds.indexOf(vow.pieceId),
          )
        else if (vow.type == VowType.watch &&
            vow.owner != mover &&
            vow.square != null &&
            vow.square! >= 0 &&
            vow.square! < 64 &&
            next.board.pieceAt(vow.square!)?.color == mover)
          (card: CardId.watchVow, side: vow.owner, square: vow.square!),
  ];
}

Color battleAbilityColor(CardId card) => switch (cardDefinitions[card]!
    .category) {
  CardCategory.knowledge => const Color(0xFF82D9FF),
  CardCategory.protection => const Color(0xFF65ECD5),
  CardCategory.restriction =>
    card == CardId.freeze ? const Color(0xFFB4EEFF) : const Color(0xFFF6AA69),
  CardCategory.movement => const Color(0xFFB1EF92),
  CardCategory.board => const Color(0xFFEDBD79),
  CardCategory.removal => const Color(0xFFF8F3CF),
  CardCategory.modifier => const Color(0xFFFF8797),
  CardCategory.vow => const Color(0xFFFFCF69),
};

class _Pulse {
  final int square;
  final String art;
  final CardId? card;
  final PieceColor? owner;
  final String? pieceId;
  const _Pulse(this.square, this.art, [this.card, this.owner, this.pieceId]);
}

class _FeedbackAnimation {
  final AnimationController controller;
  final List<_Pulse> pulses;
  final List<({CardId card, PieceColor side})> casts;
  final List<BattleSpellCue> spells;
  _FeedbackAnimation(this.controller, this.pulses, this.casts, this.spells);
}

/// Read-only feedback from the already-redacted, accepted player projection.
/// A refresh, initial snapshot or viewer handoff must not replay a cast.
class BattleAcceptedFeedback extends StatefulWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final bool showAnnouncements;
  final bool showProjectiles;
  final int synchronizationEpoch;
  const BattleAcceptedFeedback({
    super.key,
    required this.view,
    this.acceptedFrames,
    this.showAnnouncements = true,
    this.showProjectiles = true,
    this.synchronizationEpoch = 0,
  });
  @override
  State<BattleAcceptedFeedback> createState() => _BattleAcceptedFeedbackState();
}

class _BattleAcceptedFeedbackState extends State<BattleAcceptedFeedback>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<_FeedbackAnimation> _animations = [];
  bool _foreground = true;
  int _lastAcceptedSequence = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _lastAcceptedSequence = widget.acceptedFrames?.lastOrNull?.sequence ?? 0;
  }

  Map<String, _Pulse> _visible(PlayerView view) {
    final rules = view.rules;
    final result = <String, _Pulse>{};
    for (final effect in rules.boardEffects) {
      for (final square in effect.squares) {
        if (square < 0 || square >= 64) continue;
        result['b:${effect.id}:$square'] = _Pulse(
          square,
          BattleArt.path(boardEffectArt(effect.type)),
          boardEffectCard(effect.type),
          effect.owner,
        );
      }
    }
    for (final effect in rules.pieceEffects) {
      final square = rules.pieceIds.indexOf(effect.pieceId);
      if (square < 0 || square >= 64) continue;
      result['p:${effect.id}'] = _Pulse(
        square,
        effect.type == PieceEffectType.mineDebuff
            ? LunoVisualAssets.impact
            : BattleArt.path(
              effect.type == PieceEffectType.freeze ||
                      effect.type == PieceEffectType.shelter
                  ? 'board-${pieceEffectArt(effect.type)}'
                  : pieceEffectArt(effect.type),
            ),
        pieceEffectCard(effect.type),
        effect.owner,
        effect.pieceId,
      );
    }
    for (final vow in rules.vows) {
      final square =
          vow.square ??
          (vow.pieceId == null ? -1 : rules.pieceIds.indexOf(vow.pieceId));
      if (square >= 0 && square < 64) {
        final card =
            vow.type == VowType.hunt ? CardId.huntVow : CardId.watchVow;
        result['v:${vow.id}'] = _Pulse(
          square,
          BattleArt.path('vow'),
          card,
          vow.owner,
        );
      }
    }
    return result;
  }

  void _clear() {
    for (final animation in _animations) {
      animation.controller.dispose();
    }
    _animations.clear();
  }

  @override
  void didUpdateWidget(BattleAcceptedFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.view, after = widget.view;
    if (oldWidget.synchronizationEpoch != widget.synchronizationEpoch ||
        battleAcceptedHistoryReset(
          oldWidget.acceptedFrames,
          widget.acceptedFrames,
        ) ||
        !_foreground ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        before.viewer != after.viewer ||
        after.rules.terminal != null ||
        after.rules.ply < before.rules.ply ||
        after.rules.effectSequence < before.rules.effectSequence) {
      _clear();
      _lastAcceptedSequence =
          widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
      return;
    }
    final frames = widget.acceptedFrames;
    if (frames != null) {
      for (final frame in frames) {
        if (frame.sequence <= _lastAcceptedSequence) continue;
        _lastAcceptedSequence = frame.sequence;
        if (frame.before.viewer == after.viewer &&
            frame.after.viewer == after.viewer) {
          _recordTransition(frame.before, frame.after);
        }
      }
    } else {
      _recordTransition(before, after);
    }
  }

  void _recordTransition(PlayerView before, PlayerView after) {
    if (after.rules.terminal != null) return;
    final previous = _visible(before), current = _visible(after);
    final pulses = <int, _Pulse>{};
    for (final entry in current.entries) {
      if (!previous.containsKey(entry.key)) {
        pulses[entry.value.square] = entry.value;
      }
    }
    for (final entry in previous.entries) {
      if (!current.containsKey(entry.key)) {
        final moved =
            entry.value.pieceId == null
                ? -1
                : after.rules.pieceIds.indexOf(entry.value.pieceId);
        final square = moved >= 0 ? moved : entry.value.square;
        pulses.putIfAbsent(
          square,
          () => _Pulse(square, LunoVisualAssets.cleanse),
        );
      }
    }
    final casts = acceptedBattleCasts(before, after);
    if (pulses.isNotEmpty || casts.isNotEmpty) {
      final visiblePulses = pulses.values.take(4).toList(growable: false);
      final visibleCasts = casts.take(2).toList(growable: false);
      final spells = [
        for (final cast in visibleCasts)
          BattleSpellCue.fromViews(cast.card, cast.side, before, after),
        for (final pulse in visiblePulses)
          if (pulse.card != null && !casts.any((c) => c.card == pulse.card))
            BattleSpellCue(pulse.card!, pulse.owner ?? after.viewer, [
              pulse.square,
            ]),
        for (final modifier in before.rules.modifiers)
          if (modifier.type == ModifierType.echo &&
              !after.rules.modifiers.any((m) => m.id == modifier.id) &&
              casts.any(
                (c) =>
                    c.side == modifier.responseSide &&
                    c.card == modifier.targetCard,
              ))
            BattleSpellCue(CardId.echo, modifier.owner, []),
        for (final payoff in acceptedBattleVowPayoffs(before, after))
          BattleSpellCue(payoff.card, payoff.side, [payoff.square]),
      ].take(4).toList(growable: false);
      // Expiration markers must not restart or cut short an accepted cast.
      if (spells.isEmpty && _animations.isNotEmpty) return;
      while (_animations.length >= 3) {
        _animations.removeAt(0).controller.dispose();
      }
      final controller = AnimationController(
        vsync: this,
        duration:
            spells.isEmpty
                ? battleCleanupDuration
                : spells
                    .map((spell) => battleEffectDuration(spell.card))
                    .reduce((a, b) => a > b ? a : b),
      );
      final animation = _FeedbackAnimation(
        controller,
        visiblePulses,
        visibleCasts,
        spells,
      );
      _animations.add(animation);
      controller.addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_animations.remove(animation)) return;
          controller.dispose();
          setState(() {});
        });
      });
      controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final animation in _animations)
        Positioned.fill(
          key: ObjectKey(animation),
          child: _playback(context, animation),
        ),
    ],
  );

  Widget _playback(BuildContext context, _FeedbackAnimation animation) {
    final controller = animation.controller;
    final pulses = animation.pulses;
    final casts = animation.casts;
    final spells =
        animation.spells
            .map((spell) => spell.following(widget.view.rules))
            .where((spell) => spell.isActive)
            .toList();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRect(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  if ((pulses.isEmpty && casts.isEmpty) ||
                      controller.value >= 1) {
                    return const SizedBox.shrink();
                  }
                  final progress = controller.value;
                  double progressFor(CardId? card) => (progress *
                          controller.duration!.inMicroseconds /
                          (card == null
                              ? battleCleanupDuration.inMicroseconds
                              : battleEffectDuration(card).inMicroseconds))
                      .clamp(0.0, 1.0);
                  double impactProgressFor(CardId? card) {
                    final ownProgress = progressFor(card);
                    return widget.showProjectiles || card == null
                        ? ownProgress
                        : battleExternalImpactProgress(ownProgress);
                  }

                  return LayoutBuilder(
                    builder: (context, box) {
                      final cell = box.maxWidth / 8;
                      final impacts = <int, ({CardId card, double progress})>{};
                      for (final spell in spells) {
                        final ownProgress = impactProgressFor(spell.card);
                        if (ownProgress <= .3 || ownProgress >= .7) continue;
                        for (final square in spell.squares) {
                          if (impacts.length < 4 ||
                              impacts.containsKey(square)) {
                            impacts[square] = (
                              card: spell.card,
                              progress: ownProgress,
                            );
                          }
                        }
                      }
                      return Stack(
                        children: [
                          for (var i = 0; i < spells.length; i++)
                            if (progressFor(spells[i].card) < 1)
                              Positioned.fill(
                                child: CustomPaint(
                                  key: ValueKey(
                                    'spell-${spells[i].card.wire}-$i',
                                  ),
                                  painter: BattleSpellPainter(
                                    cue: spells[i],
                                    viewer: widget.view.viewer,
                                    progress: impactProgressFor(spells[i].card),
                                    color: battleAbilityColor(spells[i].card),
                                    showProjectile: widget.showProjectiles,
                                  ),
                                ),
                              ),
                          for (final impact in impacts.entries)
                            Positioned(
                              key: ValueKey('impact-ring-${impact.key}'),
                              left:
                                  (widget.view.viewer.isWhite
                                          ? Square.fileOf(impact.key)
                                          : 7 - Square.fileOf(impact.key)) *
                                      cell -
                                  cell * .175,
                              top:
                                  (widget.view.viewer.isWhite
                                          ? 7 - Square.rankOf(impact.key)
                                          : Square.rankOf(impact.key)) *
                                      cell -
                                  cell * .175,
                              width: cell * 1.35,
                              height: cell * 1.35,
                              child: Opacity(
                                opacity:
                                    math.sin(
                                      (impact.value.progress - .3) /
                                          .4 *
                                          math.pi,
                                    ) *
                                    .42,
                                child: Transform.scale(
                                  scale:
                                      .8 +
                                      .35 * (impact.value.progress - .3) / .4,
                                  child: Image.asset(
                                    'assets/native_art/battle-impact-v209.webp',
                                    color: battleAbilityColor(
                                      impact.value.card,
                                    ),
                                    colorBlendMode: BlendMode.modulate,
                                    cacheWidth: 192,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          for (final pulse in pulses)
                            if (progressFor(pulse.card) < 1)
                              Positioned(
                                key: ValueKey('accepted-pulse-${pulse.square}'),
                                left:
                                    (widget.view.viewer.isWhite
                                        ? Square.fileOf(pulse.square)
                                        : 7 - Square.fileOf(pulse.square)) *
                                    cell,
                                top:
                                    (widget.view.viewer.isWhite
                                        ? 7 - Square.rankOf(pulse.square)
                                        : Square.rankOf(pulse.square)) *
                                    cell,
                                width: cell,
                                height: cell,
                                child: Opacity(
                                  opacity:
                                      impactProgressFor(pulse.card) < .3
                                          ? 0
                                          : (pulse.card == null ? .8 : .34) *
                                              battleSpellEnvelope(
                                                impactProgressFor(pulse.card),
                                              ),
                                  child: Transform.scale(
                                    scale:
                                        .85 +
                                        .3 *
                                            Curves.easeOutCubic.transform(
                                              (impactProgressFor(pulse.card) /
                                                      .35)
                                                  .clamp(0, 1),
                                            ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.asset(
                                          pulse.art,
                                          cacheWidth: 128,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          for (
                            var i = 0;
                            widget.showAnnouncements && i < casts.length;
                            i++
                          )
                            if (progressFor(casts[i].card) < 1)
                              Positioned(
                                key: ValueKey(
                                  'accepted-card-${casts[i].card.wire}${i == 0 ? '' : '-$i'}',
                                ),
                                left: cell,
                                right: cell,
                                bottom: 3 + i * 36,
                                child: Opacity(
                                  opacity:
                                      progressFor(casts[i].card) < .7
                                          ? 1
                                          : (1 - progressFor(casts[i].card)) /
                                              .3,
                                  child: Transform.translate(
                                    offset: Offset(
                                      0,
                                      (1 -
                                              Curves.easeOutCubic.transform(
                                                (progressFor(casts[i].card) * 3)
                                                    .clamp(0, 1),
                                              )) *
                                          cell *
                                          2,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: BattleTokens.background
                                            .withValues(alpha: .93),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: battleAbilityColor(
                                            casts[i].card,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox.square(
                                            dimension: 24,
                                            child: BattleCardArt(
                                              card: casts[i].card,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${LunoLocalizations.of(context).battle(casts[i].side == widget.view.viewer ? BattleCopy.you : BattleCopy.opponent)} · ${LunoLocalizations.of(context).battleCardName(casts[i].card)}',
                                              maxLines: 2,
                                              style: BattleTokens.card.copyWith(
                                                fontSize: 12,
                                                height: 1.1,
                                                color: battleAbilityColor(
                                                  casts[i].card,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The live screen keeps cast copy outside the playable squares.
class BattleCastNotice extends StatefulWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final Widget child;
  final int synchronizationEpoch;
  const BattleCastNotice({
    super.key,
    required this.view,
    this.acceptedFrames,
    required this.child,
    this.synchronizationEpoch = 0,
  });
  @override
  State<BattleCastNotice> createState() => _BattleCastNoticeState();
}

class _BattleCastNoticeState extends State<BattleCastNotice>
    with WidgetsBindingObserver {
  Timer? _expiry;
  ({CardId card, PieceColor side})? _cast;
  bool _discarded = false;
  int? _spent = 0;
  bool _foreground = true;
  int _presentation = 0;
  int _lastAcceptedSequence = 0;
  Set<String> _boundEffects = {};
  @override
  void initState() {
    super.initState();
    _lastAcceptedSequence = widget.acceptedFrames?.lastOrNull?.sequence ?? 0;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  void _clear() {
    _expiry?.cancel();
    _cast = null;
    _boundEffects = {};
    _presentation++;
  }

  @override
  void didUpdateWidget(BattleCastNotice old) {
    super.didUpdateWidget(old);
    if (old.synchronizationEpoch != widget.synchronizationEpoch ||
        battleAcceptedHistoryReset(old.acceptedFrames, widget.acceptedFrames) ||
        !_foreground ||
        !TickerMode.valuesOf(context).enabled ||
        old.view.viewer != widget.view.viewer ||
        widget.view.rules.terminal != null ||
        widget.view.rules.ply < old.view.rules.ply ||
        widget.view.rules.effectSequence < old.view.rules.effectSequence) {
      _clear();
      _lastAcceptedSequence =
          widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
      return;
    }
    final frames = widget.acceptedFrames;
    if (frames == null) {
      _recordTransition(old.view, widget.view);
    } else {
      if (frames.isEmpty) _clear();
      for (final frame in frames) {
        if (frame.sequence <= _lastAcceptedSequence) continue;
        _lastAcceptedSequence = frame.sequence;
        _recordTransition(frame.before, frame.after);
      }
    }
  }

  Set<String> _effectIds(RuleState rules) => {
    ...rules.pieceEffects.map((effect) => effect.id),
    ...rules.boardEffects.map((effect) => effect.id),
    ...rules.modifiers.map((effect) => effect.id),
    ...rules.vows.map((effect) => effect.id),
  };

  void _recordTransition(PlayerView before, PlayerView after) {
    final cast = _cast;
    if (cast != null &&
        _boundEffects.isNotEmpty &&
        !_effectIds(after.rules).any(_boundEffects.contains)) {
      _clear();
    }
    final casts = acceptedBattleCasts(before, after);
    final discards = [
      for (final side in PieceColor.values)
        for (final card in after.rules.discarded[side]!)
          if (!before.rules.discarded[side]!.contains(card))
            (card: card, side: side),
    ];
    // Set differences cannot establish chronology across a skipped response.
    if (casts.length > 1 || (casts.isEmpty && discards.length > 1)) {
      _clear();
      return;
    }
    if (casts.isNotEmpty || discards.isNotEmpty) {
      _expiry?.cancel();
      _discarded = casts.isEmpty;
      _cast = _discarded ? discards.last : casts.last;
      _spent =
          _discarded
              ? 0
              : before.rules.ownTurns[_cast!.side] ==
                  after.rules.ownTurns[_cast!.side]
              ? BattleRulesCore.effectiveCost(
                before.rules,
                _cast!.side,
                _cast!.card,
              )
              : null;
      _boundEffects =
          _discarded
              ? {}
              : _effectIds(after.rules).difference(_effectIds(before.rules));
      _expiry = Timer(const Duration(milliseconds: 3600), () {
        if (mounted) setState(_clear);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_clear);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cast = _cast, l = LunoLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 0),
      child: AnimatedSwitcher(
        key: ValueKey(_presentation),
        duration: BattleTokens.duration(context),
        transitionBuilder:
            (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(.08, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
        child:
            cast == null
                ? widget.child
                : Semantics(
                  key: ValueKey(
                    '${_discarded ? 'discard' : 'cast'}-notice-${cast.card.wire}',
                  ),
                  liveRegion: true,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 66),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: BattleTokens.surface,
                      border: Border(
                        left: BorderSide(
                          color:
                              _discarded
                                  ? BattleTokens.danger
                                  : battleAbilityColor(cast.card),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 44,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey('cast-art-${cast.card.wire}'),
                            tween: Tween(begin: 0, end: 1),
                            duration:
                                MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 420),
                            curve: Curves.easeOutBack,
                            builder:
                                (_, value, child) => Transform.rotate(
                                  angle: -.15 * (1 - value),
                                  child: Transform.scale(
                                    scale: .75 + .25 * value,
                                    child: child,
                                  ),
                                ),
                            child: BattleCardArt(card: cast.card),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l.battleCardName(cast.card),
                                style: BattleTokens.card.copyWith(
                                  color: battleAbilityColor(cast.card),
                                ),
                              ),
                              Text(
                                _discarded
                                    ? l.learning(
                                      '${l.battle(cast.side == widget.view.viewer ? BattleCopy.you : BattleCopy.opponent)} feda etti · Mana değişmedi',
                                      '${l.battle(cast.side == widget.view.viewer ? BattleCopy.you : BattleCopy.opponent)} discarded · Mana unchanged',
                                    )
                                    : _spent == null
                                    ? l.learning(
                                      '${l.battle(cast.side == widget.view.viewer ? BattleCopy.you : BattleCopy.opponent)} · Etki uygulandı',
                                      '${l.battle(cast.side == widget.view.viewer ? BattleCopy.you : BattleCopy.opponent)} · Effect applied',
                                    )
                                    : '${l.battle(cast.side == widget.view.viewer ? BattleCopy.you : BattleCopy.opponent)} · $_spent mana',
                                style: BattleTokens.caption,
                              ),
                              Text(
                                _discarded
                                    ? cast.side == widget.view.viewer
                                        ? l.learning(
                                          'Elinde bir kartlık yer açıldı.',
                                          'One hand slot was freed.',
                                        )
                                        : l.learning(
                                          'Rakibin elinde bir kartlık yer açıldı.',
                                          "One slot in the opponent's hand was freed.",
                                        )
                                    : movementCards.contains(cast.card) &&
                                        widget.view.rules.special?.card !=
                                            cast.card
                                    ? l.learning(
                                      'Kartın özel taş hamlesi tamamlandı.',
                                      "The card's special chess move is complete.",
                                    )
                                    : l.battleCardOutcome(
                                      cast.card,
                                      ours: cast.side == widget.view.viewer,
                                      choicePending:
                                          widget.view.rules.phase ==
                                              BattlePhase.pending &&
                                          widget.view.rules.pending?.card ==
                                              cast.card,
                                    ),
                                style: BattleTokens.body.copyWith(height: 1.3),
                              ),
                              Text(
                                widget.view.rules.board.turn !=
                                        widget.view.viewer
                                    ? l.learning(
                                      'Rakibin hamlesini bekle.',
                                      'Wait for the opponent to move.',
                                    )
                                    : widget.view.rules.phase ==
                                        BattlePhase.pending
                                    ? l.battlePendingChoiceInstruction(
                                      widget.view.rules.pending!.card,
                                    )
                                    : widget.view.rules.phase ==
                                        BattlePhase.card
                                    ? l.learning(
                                      'Yeni kart aşaması: kart seç veya geç.',
                                      'New card phase: choose a card or skip.',
                                    )
                                    : l.learning(
                                      'Şimdi taş hamleni yap.',
                                      'Now make your chess move.',
                                    ),
                                style: BattleTokens.caption.copyWith(
                                  color: BattleTokens.ivory,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}
