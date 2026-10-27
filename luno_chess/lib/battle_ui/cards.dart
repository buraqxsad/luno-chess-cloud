import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import 'tokens.dart';
import 'art.dart';
import 'draw_flow.dart';
import 'draw_motion.dart';
import 'accepted_frames.dart';

String battleCardArtAsset(CardId card) => switch (card) {
  CardId.radar => 'assets/native_art/battle-card-v204-radar.png',
  CardId.prophecy => 'assets/native_art/battle-card-v204-prophecy.png',
  CardId.shelter => 'assets/native_art/battle-card-v204-shelter.png',
  CardId.chain => 'assets/native_art/battle-card-v204-chain.png',
  CardId.slow => 'assets/native_art/battle-card-v204-slow.png',
  CardId.pawnDeviation =>
    'assets/native_art/battle-card-v204-pawn-deviation.png',
  CardId.pawnAdvance => 'assets/native_art/battle-card-v204-pawn-advance.png',
  CardId.lockedSquare => 'assets/native_art/battle-card-v204-locked-square.png',
  CardId.freeze => 'assets/native_art/battle-card-v204-freeze.png',
  CardId.purify => 'assets/native_art/battle-card-v204-purify.png',
  CardId.mine => 'assets/native_art/battle-card-v204-mine.png',
  CardId.breakSeal => 'assets/native_art/battle-card-v204-break-seal.png',
  CardId.fog => 'assets/native_art/battle-card-v204-fog.png',
  CardId.manaSabotage => 'assets/native_art/battle-card-v204-mana-sabotage.png',
  CardId.cardBlock => 'assets/native_art/battle-card-v204-card-block.png',
  CardId.rookBend => 'assets/native_art/battle-card-v204-rook-bend.png',
  CardId.angryN => 'assets/native_art/battle-card-v204-angry-n.png',
  CardId.shadowPass => 'assets/native_art/battle-card-v204-shadow-pass.png',
  CardId.huntVow => 'assets/native_art/battle-card-v204-hunt-vow.png',
  CardId.watchVow => 'assets/native_art/battle-card-v204-watch-vow.png',
  CardId.echo => 'assets/native_art/battle-card-v204-echo.png',
  CardId.fateExchange => 'assets/native_art/battle-card-v204-fate-exchange.png',
  CardId.shadowContract =>
    'assets/native_art/battle-card-v204-shadow-contract.png',
  CardId.boardSeal => 'assets/native_art/battle-card-v204-board-seal.png',
};

Color battleRarityColor(Rarity rarity) => switch (rarity) {
  Rarity.common => const Color(0xFFB7CFCA),
  Rarity.rare => const Color(0xFF5DDDA9),
  Rarity.epic => const Color(0xFF64CAFF),
  Rarity.legendary => const Color(0xFFFFCD62),
};

class BattleCardArt extends StatelessWidget {
  final CardId card;
  final String? asset;
  const BattleCardArt({super.key, required this.card, this.asset});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final dimensions = [
          constraints.maxWidth,
          constraints.maxHeight,
        ].where((value) => value.isFinite && value > 0);
        // All approved card illustrations are square and 640px wide. Buckets
        // keep cache keys stable while matching the actual painted size.
        final pixels =
            dimensions.isEmpty
                ? 384
                : ((dimensions.reduce(math.min) *
                                MediaQuery.devicePixelRatioOf(context) /
                                64)
                            .ceil() *
                        64)
                    .clamp(64, 640);
        return Image.asset(
          asset ?? battleCardArtAsset(card),
          fit: BoxFit.contain,
          cacheWidth: pixels,
          filterQuality: FilterQuality.medium,
        );
      },
    ),
  );
}

class BattleCardTile extends StatelessWidget {
  final CardId card;
  final int cost;
  final bool selected, enabled;
  final bool compact;
  final VoidCallback? onSelect, onDetail;
  final String? stateLabel;
  final List<PendingModifier> modifiers;
  const BattleCardTile({
    super.key,
    required this.card,
    required this.cost,
    this.selected = false,
    this.enabled = true,
    this.compact = false,
    this.onSelect,
    this.onDetail,
    this.stateLabel,
    this.modifiers = const [],
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled || onDetail != null,
      label:
          '${l.battleCardName(card)}, ${l.battle(BattleCopy.mana)} $cost${stateLabel == null ? '' : ', $stateLabel'}',
      child: _BattleCardMotion(
        enabled: enabled || onDetail != null,
        selected: selected,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BattleTokens.radius),
            border: Border.all(
              color:
                  selected
                      ? BattleTokens.gold
                      : battleRarityColor(
                        cardDefinitions[card]!.rarity,
                      ).withValues(alpha: enabled ? .8 : .4),
              width: 2,
            ),
            boxShadow:
                selected
                    ? [
                      BoxShadow(
                        color: BattleTokens.mana.withValues(alpha: .5),
                        blurRadius: 14,
                      ),
                    ]
                    : const [],
          ),
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/native_art/battle-card-face-v211.webp',
                      fit: BoxFit.fill,
                      cacheWidth: 360,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: enabled ? onSelect : onDetail,
                    onLongPress: onDetail,
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        ExcludeSemantics(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 4 : 5,
                              2,
                              compact ? 4 : 5,
                              compact
                                  ? (BattleTokens.shortPortrait(context)
                                      ? 4
                                      : 5)
                                  : 7,
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height:
                                      (compact ? 24 : 28) +
                                      (MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(13) /
                                                  13 -
                                              1) *
                                          20,
                                  child: Row(
                                    children: [
                                      SizedBox.square(
                                        dimension: 32,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const BattleArt('mana', size: 18),
                                              const SizedBox(width: 2),
                                              Text(
                                                '$cost',
                                                key: ValueKey(
                                                  'card-cost-${card.wire}',
                                                ),
                                                textScaler:
                                                    TextScaler.noScaling,
                                                style: BattleTokens.card
                                                    .copyWith(
                                                      fontSize: 17,
                                                      color:
                                                          enabled
                                                              ? BattleTokens
                                                                  .ivory
                                                              : BattleTokens
                                                                  .disabled,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                      vertical: 2,
                                    ),
                                    child: Opacity(
                                      opacity: enabled ? 1 : .78,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          BattleCardArt(card: card),
                                          if (modifiers.isNotEmpty)
                                            Align(
                                              alignment: Alignment.bottomRight,
                                              child: BattleModifierMarks(
                                                modifiers: modifiers,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(compact ? 12 : 13) *
                                      3.3,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: Center(
                                      child: _BattleCardName(
                                        name: l.battleCardName(card),
                                        compact: compact,
                                      ),
                                    ),
                                  ),
                                ),
                                if (stateLabel != null)
                                  Text(
                                    stateLabel!,
                                    textAlign: TextAlign.center,
                                    style: BattleTokens.caption,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (onDetail != null)
                          Positioned(
                            top: 0,
                            right: 2,
                            child: SizedBox.square(
                              dimension: 44,
                              child: IconButton(
                                key: ValueKey('detail-${card.wire}'),
                                tooltip:
                                    '${l.battle(BattleCopy.detail)}: ${l.battleCardName(card)}',
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.only(
                                  top: 5,
                                  right: 4,
                                ),
                                onPressed: onDetail,
                                icon: const BattleArt('info', size: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _BattleCardMotion extends StatefulWidget {
  final bool selected, enabled;
  final Widget child;
  const _BattleCardMotion({
    required this.selected,
    required this.enabled,
    required this.child,
  });

  @override
  State<_BattleCardMotion> createState() => _BattleCardMotionState();
}

class _BattleCardMotionState extends State<_BattleCardMotion>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.selected ? 1 : 0,
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 85),
    reverseDuration: const Duration(milliseconds: 190),
  );
  bool _foreground = true, _dragged = false, _showFlash = false;
  int? _pointer;
  Offset? _downPosition;
  bool get _motion =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _showFlash = widget.selected;
  }

  void _reset() {
    _pointer = null;
    _downPosition = null;
    _dragged = false;
    _showFlash = false;
    _press.value = 0;
    _selection.value = widget.selected ? 1 : 0;
  }

  void _down(PointerDownEvent event) {
    if (!_motion ||
        !widget.enabled ||
        _pointer != null ||
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _dragged = false;
    _press.forward();
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _dragged || _downPosition == null) return;
    if ((event.position - _downPosition!).distance > kTouchSlop) {
      _dragged = true;
      _press.reverse();
    }
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _downPosition = null;
    _dragged = false;
    if (_motion) {
      _press.reverse();
    } else {
      _press.value = 0;
    }
  }

  @override
  void didUpdateWidget(_BattleCardMotion old) {
    super.didUpdateWidget(old);
    if (!_motion || !widget.enabled) {
      _reset();
    } else if (old.selected != widget.selected) {
      _showFlash = widget.selected;
      widget.selected ? _selection.forward() : _selection.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motion) _reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_reset);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _press.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: AnimatedBuilder(
      animation: Listenable.merge([_selection, _press]),
      child: widget.child,
      builder: (context, child) {
        final lift =
            _motion
                ? Curves.easeOutBack.transform(_selection.value)
                : (widget.selected ? 1.0 : 0.0);
        final press =
            _motion ? Curves.easeOutCubic.transform(_press.value) : 0.0;
        final scale = 1 + .012 * lift - .042 * press;
        return Transform(
          key: const ValueKey('hand-card-pose'),
          alignment: Alignment.center,
          transformHitTests: false,
          transform:
              Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..translateByDouble(0, -6 * lift + 2 * press, 0, 1)
                ..rotateX(press * .055)
                ..scaleByDouble(scale, scale, scale, 1),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              if (_showFlash && widget.selected)
                const Positioned.fill(
                  child: IgnorePointer(child: BattleCardSelectionFlash()),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _BattleCardName extends StatelessWidget {
  final String name;
  final bool compact;
  const _BattleCardName({required this.name, required this.compact});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      var font = compact ? 12.0 : 13.0;
      if (box.maxWidth > 0) {
        var widest = 0.0;
        for (final word in name.split(RegExp(r'\s+'))) {
          final text = TextPainter(
            text: TextSpan(
              text: word,
              style: BattleTokens.card.copyWith(fontSize: font),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          if (text.width > widest) widest = text.width;
          text.dispose();
        }
        if (widest > box.maxWidth) font *= box.maxWidth / widest;
      }
      return Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 3,
        style: BattleTokens.card.copyWith(fontSize: font, height: 1.1),
      );
    },
  );
}

class BattleHand extends StatelessWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final int synchronizationEpoch;
  final CardId? selected;
  final bool enabled;
  final bool compact;
  final GlobalKey? drawSource;
  final Offset? exchangeOrigin;
  final BattleDrawNotice? arrival;
  final Map<CardId, GlobalKey>? cardSources;
  final int Function(CardId) cost;
  final bool Function(CardId) selectable;
  final void Function(CardId) onSelect, onDetail;
  const BattleHand({
    super.key,
    required this.view,
    this.acceptedFrames,
    this.synchronizationEpoch = 0,
    this.selected,
    required this.enabled,
    this.compact = false,
    this.drawSource,
    this.exchangeOrigin,
    this.arrival,
    this.cardSources,
    required this.cost,
    required this.selectable,
    required this.onSelect,
    required this.onDetail,
  });
  @override
  Widget build(BuildContext context) => _BattleHandDiscard(
    view: view,
    acceptedFrames: acceptedFrames,
    synchronizationEpoch: synchronizationEpoch,
    departure:
        (card) =>
            BattleCardTile(card: card, cost: cost(card), compact: compact),
    builder: (slots) => _buildHand(context, slots),
  );

  Widget _buildHand(BuildContext context, Map<CardId, GlobalKey> slots) {
    if (view.ownHand.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            LunoLocalizations.of(context).battle(BattleCopy.emptyHand),
            style: BattleTokens.body,
          ),
        ),
      );
    }
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final short = BattleTokens.shortPortrait(context);
    final shortHeight =
        116.0 +
        (BattleTokens.compactText(context)
            ? ((MediaQuery.sizeOf(context).height - 568) * .5).clamp(0.0, 38.0)
            : 0.0);
    return SizedBox(
      height: (compact ? (short ? shortHeight : 154) : 184) + (scale - 1) * 90,
      child: LayoutBuilder(
        builder:
            (context, box) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < view.ownHand.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  SizedBox(
                    key: ValueKey(
                      'hand-slot-${view.viewer.name}-${view.ownHand[i].wire}',
                    ),
                    width: math.min(140, (box.maxWidth - 15) / 4),
                    child: KeyedSubtree(
                      key: slots.putIfAbsent(view.ownHand[i], GlobalKey.new),
                      child: BattleCardArrival(
                        key: cardSources?[view.ownHand[i]],
                        card: view.ownHand[i],
                        source: drawSource,
                        absoluteOrigin:
                            arrival?.kind == BattleArrivalKind.exchange
                                ? exchangeOrigin
                                : null,
                        trigger:
                            arrival?.ownCard == view.ownHand[i]
                                ? arrival?.version
                                : null,
                        exchange: arrival?.kind == BattleArrivalKind.exchange,
                        child: BattleCardTile(
                          compact: compact,
                          key: ValueKey('hand-${view.ownHand[i].wire}'),
                          card: view.ownHand[i],
                          cost: cost(view.ownHand[i]),
                          modifiers:
                              view.rules.modifiers
                                  .where(
                                    (m) =>
                                        m.responseSide == view.viewer &&
                                        (m.targetCard == null ||
                                            m.targetCard == view.ownHand[i]),
                                  )
                                  .toList(),
                          selected: selected == view.ownHand[i],
                          enabled: enabled && selectable(view.ownHand[i]),
                          onSelect: () => onSelect(view.ownHand[i]),
                          onDetail: () => onDetail(view.ownHand[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }
}

class _BattleHandDiscard extends StatefulWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final int synchronizationEpoch;
  final Widget Function(Map<CardId, GlobalKey>) builder;
  final Widget Function(CardId) departure;
  const _BattleHandDiscard({
    required this.view,
    required this.acceptedFrames,
    required this.synchronizationEpoch,
    required this.builder,
    required this.departure,
  });

  @override
  State<_BattleHandDiscard> createState() => _BattleHandDiscardState();
}

class _BattleHandDiscardState extends State<_BattleHandDiscard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _stage = GlobalKey();
  final _slots = <CardId, GlobalKey>{};
  late final AnimationController _discard = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _departure = null);
    }
  });
  Rect? _rect;
  Widget? _departure;
  bool _foreground = true;
  int _lastAcceptedSequence = 0;
  bool get _motion =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _lastAcceptedSequence = widget.acceptedFrames?.lastOrNull?.sequence ?? 0;
  }

  void _clear() {
    _discard.stop();
    _departure = null;
    _rect = null;
  }

  @override
  void didUpdateWidget(_BattleHandDiscard old) {
    super.didUpdateWidget(old);
    final before = old.view, after = widget.view;
    if (old.synchronizationEpoch != widget.synchronizationEpoch ||
        battleAcceptedHistoryReset(old.acceptedFrames, widget.acceptedFrames) ||
        !_motion ||
        before.viewer != after.viewer ||
        after.rules.terminal != null ||
        after.rules.ply < before.rules.ply ||
        after.rules.effectSequence < before.rules.effectSequence ||
        (widget.acceptedFrames == null &&
            after.rules.ply > before.rules.ply + 1)) {
      _clear();
      _lastAcceptedSequence =
          widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
      if (before.viewer != after.viewer) _slots.clear();
      return;
    }
    final frames =
        widget.acceptedFrames == null
            ? [BattleAcceptedFrame(0, before, after)]
            : widget.acceptedFrames!
                .where((frame) => frame.sequence > _lastAcceptedSequence)
                .toList();
    _lastAcceptedSequence =
        widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
    CardId? departed;
    for (final frame in frames) {
      final previousView = frame.before, currentView = frame.after;
      if (previousView.viewer != after.viewer ||
          currentView.viewer != after.viewer ||
          previousView.rules.terminal != null ||
          currentView.rules.terminal != null) {
        continue;
      }
      final previous = previousView.rules.discarded[after.viewer]!;
      final current = currentView.rules.discarded[after.viewer]!;
      if (!previous.every(current.contains)) {
        _clear();
        continue;
      }
      final added = current.where((card) => !previous.contains(card)).toList();
      if (added.length == 1 &&
          previousView.ownHand.contains(added.single) &&
          !currentView.ownHand.contains(added.single) &&
          before.ownHand.contains(added.single) &&
          !after.ownHand.contains(added.single)) {
        departed = added.single;
      }
    }
    if (departed == null) return;
    final box = _slots[departed]?.currentContext?.findRenderObject();
    final stage = _stage.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        stage is! RenderBox ||
        !box.attached ||
        !stage.attached ||
        !box.hasSize ||
        !stage.hasSize ||
        box.size.isEmpty) {
      return;
    }
    final origin = stage.globalToLocal(box.localToGlobal(Offset.zero));
    if (!origin.dx.isFinite || !origin.dy.isFinite) return;
    _rect = origin & box.size;
    _departure = old.departure(departed);
    _discard.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motion) _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _slots.removeWhere((card, _) => !widget.view.ownHand.contains(card));
    return Stack(
      key: _stage,
      clipBehavior: Clip.none,
      children: [
        widget.builder(_slots),
        AnimatedBuilder(
          animation: _discard,
          child: _departure,
          builder: (context, child) {
            if (!_motion ||
                child == null ||
                _rect == null ||
                _discard.value >= 1) {
              return const SizedBox.shrink();
            }
            final p = _discard.value;
            final release = Curves.easeOutCubic.transform(p);
            final scale = 1 - .16 * release;
            return Positioned.fromRect(
              rect: _rect!,
              child: IgnorePointer(
                key: const ValueKey('hand-discard-departure'),
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: (1 - p * p).clamp(0.0, 1.0),
                    child: Transform(
                      alignment: Alignment.center,
                      transformHitTests: false,
                      transform:
                          Matrix4.identity()
                            ..translateByDouble(
                              8 * release,
                              -12 * math.sin(p * math.pi),
                              0,
                              1,
                            )
                            ..rotateZ(.10 * release)
                            ..scaleByDouble(scale, scale, scale, 1),
                      child: TickerMode(enabled: false, child: child),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class BattleCardArrival extends StatefulWidget {
  final CardId card;
  final Widget child;
  final GlobalKey? source;
  final Offset? absoluteOrigin;
  final int? trigger;
  final bool exchange;
  const BattleCardArrival({
    super.key,
    required this.card,
    required this.child,
    this.source,
    this.absoluteOrigin,
    this.trigger,
    this.exchange = false,
  });
  @override
  State<BattleCardArrival> createState() => _BattleCardArrivalState();
}

class _BattleCardArrivalState extends State<BattleCardArrival>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _target = GlobalKey();
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    value: 1,
  );
  Offset _origin = Offset.zero;
  double _startScale = .82;
  bool _foreground = true;
  int _generation = 0;
  bool get _motion =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motion) {
      _finish();
    } else if (_generation == 0) {
      _schedule();
    }
  }

  @override
  void didUpdateWidget(BattleCardArrival old) {
    super.didUpdateWidget(old);
    if (!_motion || widget.trigger == null) {
      _finish();
    } else if (old.trigger != widget.trigger || old.card != widget.card) {
      _schedule();
    }
  }

  void _finish() {
    _generation++;
    _origin = Offset.zero;
    _startScale = 1;
    _arrival.value = 1;
  }

  void _schedule() {
    final generation = ++_generation;
    final trigger = widget.trigger;
    if (trigger == null ||
        (widget.source == null && widget.absoluteOrigin == null)) {
      _arrival.value = 1;
      return;
    }
    _arrival.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          widget.trigger != trigger ||
          !_motion) {
        return;
      }
      final from = widget.source?.currentContext?.findRenderObject();
      final to = _target.currentContext?.findRenderObject();
      if (to is! RenderBox || !to.attached || !to.hasSize || to.size.isEmpty) {
        _finish();
        return;
      }
      if (widget.absoluteOrigin != null) {
        _origin =
            widget.absoluteOrigin! -
            to.localToGlobal(to.size.center(Offset.zero));
        _startScale = .7;
      } else if (from is RenderBox &&
          from.attached &&
          from.hasSize &&
          !from.size.isEmpty) {
        _origin =
            from.localToGlobal(from.size.center(Offset.zero)) -
            to.localToGlobal(to.size.center(Offset.zero));
        _startScale = (from.size.shortestSide / to.size.longestSide).clamp(
          .25,
          .82,
        );
      } else {
        _finish();
        return;
      }
      if (!_origin.dx.isFinite || !_origin.dy.isFinite) {
        _finish();
        return;
      }
      _arrival.forward(from: 0);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_finish);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: _target,
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _arrival,
        child: widget.child,
        builder: (context, child) {
          final value = _arrival.value;
          final travel = Curves.easeInOutCubic.transform(
            (value / .72).clamp(0.0, 1.0),
          );
          final settle = ((value - .72) / .28).clamp(0.0, 1.0);
          final reveal =
              widget.exchange
                  ? 1.0
                  : Curves.easeOutCubic.transform(
                    ((value - .52) / .18).clamp(0.0, 1.0),
                  );
          return Opacity(
            opacity: (value * 8).clamp(0, 1),
            child: Transform.translate(
              key: const ValueKey('hand-arrival-position'),
              transformHitTests: false,
              offset:
                  _origin * (1 - travel) -
                  Offset(
                    0,
                    math.sin(travel * math.pi) *
                            math.min(40.0, _origin.distance * .12) +
                        math.sin(settle * math.pi) * 3,
                  ),
              child: Transform(
                alignment: Alignment.center,
                transformHitTests: false,
                transform:
                    Matrix4.identity()
                      ..setEntry(3, 2, .0015)
                      ..rotateY(widget.exchange ? 0 : -.65 * (1 - travel))
                      ..rotateZ(
                        .14 * math.sin(travel * math.pi) * (1 - travel),
                      ),
                child: Transform.scale(
                  transformHitTests: false,
                  scale:
                      _startScale +
                      (1 - _startScale) * travel +
                      .025 * math.sin(settle * math.pi),
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Opacity(opacity: reveal, child: child!),
                      if (reveal < 1)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 1 - reveal,
                              child: const BattleClosedCard(),
                            ),
                          ),
                        ),
                      if (value >= .65 && value < 1)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: BattleTokens.mana.withValues(
                                    alpha: (1 - value) / .35,
                                  ),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (value < 1)
                        Positioned(
                          key: ValueKey('draw-source-${widget.card.wire}'),
                          top: 28,
                          left: 3,
                          right: 3,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Opacity(
                                opacity:
                                    value < .8
                                        ? 1
                                        : ((1 - value) / .2).clamp(0, 1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: BattleTokens.background.withValues(
                                      alpha: .9,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: BattleTokens.gold,
                                    ),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const BattleArt('arsenal', size: 12),
                                        const SizedBox(width: 3),
                                        Text(
                                          LunoLocalizations.of(
                                                    context,
                                                  ).locale.languageCode ==
                                                  'en'
                                              ? (widget.exchange
                                                  ? 'Selected card'
                                                  : 'From deck')
                                              : (widget.exchange
                                                  ? 'Seçtiğin kart'
                                                  : 'Desteden'),
                                          textScaler: TextScaler.noScaling,
                                          style: BattleTokens.caption.copyWith(
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class BattleCardSelectionFlash extends StatefulWidget {
  const BattleCardSelectionFlash({super.key});
  @override
  State<BattleCardSelectionFlash> createState() =>
      _BattleCardSelectionFlashState();
}

class _BattleCardSelectionFlashState extends State<BattleCardSelectionFlash>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 540),
  );
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final life = WidgetsBinding.instance.lifecycleState;
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        (life != null && life != AppLifecycleState.resumed)) {
      _started = true;
      _flash.value = 1;
    } else if (!_started) {
      _started = true;
      _flash.forward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flash.value = 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _flash,
        builder:
            (context, _) =>
                CustomPaint(painter: _CardSelectionPainter(_flash.value)),
      ),
    ),
  );
}

class _CardSelectionPainter extends CustomPainter {
  final double progress;
  const _CardSelectionPainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1 || size.shortestSide <= 3) return;
    final rect = Offset.zero & size;
    final fade = math.sin(progress * math.pi);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    final x = size.width * (-.4 + progress * 1.8);
    final beam =
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + size.width * .28, 0)
          ..lineTo(x - size.width * .2, size.height)
          ..lineTo(x - size.width * .48, size.height)
          ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BattleTokens.mana.withValues(alpha: .06 * fade),
            Colors.white.withValues(alpha: .34 * fade),
            BattleTokens.gold.withValues(alpha: .10 * fade),
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    final outline =
        Path()..addRRect(
          RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(5)),
        );
    final metric = outline.computeMetrics().first;
    final head = metric.length * Curves.easeOutCubic.transform(progress);
    canvas.drawPath(
      metric.extractPath(math.max(0.0, head - metric.length * .24), head),
      Paint()
        ..color = BattleTokens.gold.withValues(alpha: .8 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardSelectionPainter old) => old.progress != progress;
}

CardId battleModifierCard(ModifierType type) => switch (type) {
  ModifierType.cardBlock => CardId.cardBlock,
  ModifierType.manaSabotage => CardId.manaSabotage,
  ModifierType.echo => CardId.echo,
  ModifierType.discount => CardId.shadowContract,
};

class BattleModifierMarks extends StatelessWidget {
  final List<PendingModifier> modifiers;
  const BattleModifierMarks({super.key, required this.modifiers});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 2,
    runSpacing: 2,
    children: [
      for (final modifier in modifiers)
        Tooltip(
          message: LunoLocalizations.of(
            context,
          ).battleCardName(battleModifierCard(modifier.type)),
          child: Semantics(
            label: LunoLocalizations.of(
              context,
            ).battleCardName(battleModifierCard(modifier.type)),
            child: SizedBox.square(
              dimension: 20,
              child: BattleCardArt(card: battleModifierCard(modifier.type)),
            ),
          ),
        ),
    ],
  );
}
