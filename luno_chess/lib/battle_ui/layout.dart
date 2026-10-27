import 'dart:async';
import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import '../theme/luno_assets.dart';
import 'art.dart';
import 'tokens.dart';
import 'primitives.dart';
import 'draw_counters.dart';

class BattleClock extends StatefulWidget {
  final int Function() remaining;
  final bool active, terminal;
  final bool compact;
  final String label;
  const BattleClock({
    super.key,
    required this.remaining,
    required this.label,
    required this.active,
    this.terminal = false,
    this.compact = false,
  });
  @override
  State<BattleClock> createState() => _BattleClockState();
}

class _BattleClockState extends State<BattleClock> with WidgetsBindingObserver {
  Timer? timer;
  int? lastSeconds;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _start();
  }

  void _start() {
    timer?.cancel();
    if (widget.terminal || !widget.active || !foreground) return;
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final seconds = (widget.remaining().clamp(0, 0x7fffffff) + 999) ~/ 1000;
      if (mounted && seconds != lastSeconds) setState(() {});
    });
  }

  @override
  void didUpdateWidget(BattleClock old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal || old.active != widget.active) {
      _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _start();
      if (mounted) setState(() {});
    } else {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (widget.remaining().clamp(0, 0x7fffffff) + 999) ~/ 1000;
    lastSeconds = seconds;
    final value =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: widget.label,
      value: value,
      child: ExcludeSemantics(
        child: BattleSkin(
          name: 'clock-panel',
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Text(
              value,
              style: BattleTokens.clock.copyWith(
                fontSize: widget.compact ? 18 : 20,
                color:
                    seconds <= 30 && !widget.terminal
                        ? BattleTokens.danger
                        : widget.active
                        ? BattleTokens.gold
                        : BattleTokens.ivory,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BattlePlayerHeader extends StatelessWidget {
  final String name;
  final PieceColor side;
  final PlayerView view;
  final Widget clock;
  final Widget? trailing;
  final Widget? deck;
  final GlobalKey? deckSource, handTarget;
  final String? portrait;
  final bool own;
  final bool compact;
  final bool sidebar;
  final int? selectedCost;
  const BattlePlayerHeader({
    super.key,
    required this.name,
    required this.side,
    required this.view,
    required this.clock,
    this.trailing,
    this.deck,
    this.deckSource,
    this.handTarget,
    this.portrait,
    this.own = false,
    this.compact = false,
    this.sidebar = false,
    this.selectedCost,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    if (own &&
        compact &&
        MediaQuery.orientationOf(context) == Orientation.portrait) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Tooltip(
              message: name,
              child: Semantics(
                label: name,
                child: ClipOval(
                  child: Image.asset(
                    portrait ?? LunoAssets.avatar('av_pawn'),
                    width: 24,
                    height: 24,
                    cacheWidth: 96,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            BattleMana(
              value: view.rules.mana[side]!,
              label: l.battle(BattleCopy.mana),
              previewCost: selectedCost,
              compact: true,
            ),
            const Spacer(),
            if (deck != null) deck!,
            clock,
            if (trailing != null) trailing!,
          ],
        ),
      );
    }
    if (sidebar) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.asset(
              portrait ?? LunoAssets.avatar(own ? 'av_pawn' : 'av_knight'),
              width: 24,
              height: 24,
              cacheWidth: 96,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BattleTokens.caption.copyWith(color: BattleTokens.ivory),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BattleMana(
              value: view.rules.mana[side]!,
              label: l.battle(BattleCopy.mana),
              previewCost: own ? selectedCost : null,
              compact: true,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: clock),
          if (trailing != null) trailing!,
        ],
      );
    }
    if (compact && !BattleTokens.compactText(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    portrait ??
                        LunoAssets.avatar(own ? 'av_pawn' : 'av_knight'),
                    width: 28,
                    height: 28,
                    cacheWidth: 96,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BattleTokens.card,
                  ),
                ),
                clock,
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BattleMana(
                          value: view.rules.mana[side]!,
                          label: l.battle(BattleCopy.mana),
                          previewCost: own ? selectedCost : null,
                          compact: true,
                        ),
                        if (!own) ...[
                          const SizedBox(width: 6),
                          BattleDrawCounters(
                            view: view,
                            side: side,
                            deckSource: deckSource,
                            handTarget: handTarget,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (deck != null) deck!,
                if (trailing != null) trailing!,
              ],
            ),
          ],
        ),
      );
    }
    if (MediaQuery.textScalerOf(context).scale(14) <= 17) {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: BattleTokens.shortPortrait(context) ? 0 : 2,
        ),
        child: Row(
          children: [
            ClipOval(
              child: Image.asset(
                portrait ?? LunoAssets.avatar(own ? 'av_pawn' : 'av_knight'),
                width: 28,
                height: 28,
                cacheWidth: 96,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BattleTokens.card,
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BattleMana(
                          value: view.rules.mana[side]!,
                          label: l.battle(BattleCopy.mana),
                          previewCost: own ? selectedCost : null,
                          compact: true,
                        ),
                        if (!own) const SizedBox(width: 4),
                        if (!own)
                          BattleDrawCounters(
                            view: view,
                            side: side,
                            deckSource: deckSource,
                            handTarget: handTarget,
                          ),
                        if (trailing != null) trailing!,
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (deck != null) deck!,
            clock,
          ],
        ),
      );
    }
    if (MediaQuery.textScalerOf(context).scale(14) > 16) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    portrait ??
                        LunoAssets.avatar(own ? 'av_pawn' : 'av_knight'),
                    width: 36,
                    height: 36,
                    cacheWidth: 96,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BattleTokens.title,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 2),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BattleMana(
                    value: view.rules.mana[side]!,
                    label: l.battle(BattleCopy.mana),
                    previewCost: own ? selectedCost : null,
                  ),
                  if (!own)
                    BattleDrawCounters(
                      view: view,
                      side: side,
                      deckSource: deckSource,
                      handTarget: handTarget,
                    ),
                  if (deck != null) deck!,
                  clock,
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              portrait ?? LunoAssets.avatar(own ? 'av_pawn' : 'av_knight'),
              width: 40,
              height: 40,
              cacheWidth: 96,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BattleTokens.title,
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BattleMana(
                      value: view.rules.mana[side]!,
                      label: l.battle(BattleCopy.mana),
                      previewCost: own ? selectedCost : null,
                    ),
                    if (!own)
                      BattleDrawCounters(
                        view: view,
                        side: side,
                        deckSource: deckSource,
                        handTarget: handTarget,
                      ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          clock,
        ],
      ),
    );
  }
}

class BattleResultHeading extends StatelessWidget {
  final PieceColor? winner;
  final PieceColor own;
  final String title, reason, pieceSet;
  const BattleResultHeading({
    super.key,
    required this.winner,
    required this.own,
    required this.title,
    required this.reason,
    required this.pieceSet,
  });
  @override
  Widget build(BuildContext context) {
    final color =
        winner == null
            ? BattleTokens.mana
            : winner == own
            ? BattleTokens.gold
            : BattleTokens.secondary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: Column(
        children: [
          SizedBox(
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  BattleArt.piecePath(
                    winner ?? own,
                    PieceType.king,
                    set: pieceSet,
                  ),
                  width: 80,
                  height: 80,
                  cacheWidth: 192,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Icon(
                    winner == null
                        ? Icons.handshake_rounded
                        : winner == own
                        ? Icons.emoji_events_rounded
                        : Icons.shield_outlined,
                    color: color,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            key: const ValueKey('battle-result-title'),
            textAlign: TextAlign.center,
            style: BattleTokens.title.copyWith(fontSize: 28, color: color),
          ),
          const SizedBox(height: 4),
          Text(reason, style: BattleTokens.body, textAlign: TextAlign.center),
          const SizedBox(height: 16),
        ],
      ),
      builder:
          (_, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 12),
              child: child,
            ),
          ),
    );
  }
}

class BattlePhaseIndicator extends StatelessWidget {
  final BattlePhase phase;
  final bool compact;
  const BattlePhaseIndicator({
    super.key,
    required this.phase,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    if (phase == BattlePhase.pending || phase == BattlePhase.terminal) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          l.battle(
            phase == BattlePhase.pending
                ? BattleCopy.choicePhase
                : BattleCopy.ended,
          ),
          style: BattleTokens.caption.copyWith(color: BattleTokens.moon),
        ),
      );
    }
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          l.battle(
            phase == BattlePhase.card ? BattleCopy.card : BattleCopy.move,
          ),
          style: BattleTokens.card.copyWith(
            color: BattleTokens.mana,
            fontSize: 12,
          ),
        ),
      );
    }
    return BattleSkin(
      name: 'phase-panel',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              (BattlePhase.card, BattleCopy.card),
              (BattlePhase.chess, BattleCopy.move),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  l.battle(entry.$2),
                  style: BattleTokens.card.copyWith(
                    color:
                        phase == entry.$1
                            ? BattleTokens.mana
                            : BattleTokens.disabled,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BattleV1Scaffold extends StatelessWidget {
  final Widget opponent, arsenal, board, own, hand, status, controls;
  final bool compactBoardDock;
  final bool controlsDockedAside;
  final bool lessonDock;
  final bool lessonBoardFocus;
  const BattleV1Scaffold({
    super.key,
    required this.opponent,
    required this.arsenal,
    required this.board,
    required this.own,
    required this.hand,
    required this.status,
    required this.controls,
    this.compactBoardDock = false,
    this.controlsDockedAside = false,
    this.lessonDock = false,
    this.lessonBoardFocus = false,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BattleTokens.background,
    body: Stack(
      children: [
        const Positioned.fill(
          child: BattleArt('background', fit: BoxFit.cover),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth >= 700 && box.maxHeight < 700) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 12,
                        child: Column(
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: box.maxHeight * .4,
                              ),
                              child: SingleChildScrollView(
                                primary: false,
                                child: opponent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: LayoutBuilder(
                                builder:
                                    (_, space) => Center(
                                      child: SizedBox.square(
                                        dimension:
                                            space.maxWidth < space.maxHeight
                                                ? space.maxWidth
                                                : space.maxHeight,
                                        child: board,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 9,
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                key: const ValueKey('battle-scroll'),
                                child: Column(
                                  children: [status, own, arsenal, hand],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: box.maxHeight * .4,
                              ),
                              child: SingleChildScrollView(
                                key: const ValueKey('battle-controls-scroll'),
                                primary: false,
                                child: controls,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              final width = box.maxWidth > 560 ? 560.0 : box.maxWidth;
              if (lessonDock && box.maxHeight > box.maxWidth) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        children: [
                          opponent,
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * .56,
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey('lesson-speech-scroll'),
                              primary: false,
                              child: status,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey('battle-scroll'),
                              child: Column(
                                children: [
                                  SizedBox.square(
                                    dimension: width - 16,
                                    child: board,
                                  ),
                                  own,
                                  arsenal,
                                  hand,
                                  controls,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (box.maxHeight >= 500 &&
                  box.maxHeight > box.maxWidth &&
                  (compactBoardDock || lessonDock)) {
                final boardWidth = width - 16;
                final speechHeight =
                    lessonDock ? (box.maxHeight * .13).clamp(56.0, 104.0) : 0.0;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        children: [
                          opponent,
                          if (lessonDock)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: speechHeight,
                              ),
                              child: SingleChildScrollView(
                                key: const ValueKey('lesson-speech-scroll'),
                                primary: false,
                                child: status,
                              ),
                            ),
                          SizedBox.square(dimension: boardWidth, child: board),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey('battle-scroll'),
                              primary: false,
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                children: [
                                  own,
                                  hand,
                                  controls,
                                  if (!lessonDock) status,
                                  arsenal,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (lessonDock && box.maxHeight >= 500) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        children: [
                          opponent,
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: (box.maxHeight *
                                      (lessonBoardFocus
                                          ? .4
                                          : BattleTokens.compactText(context)
                                          ? .23
                                          : .32))
                                  .clamp(
                                    110.0,
                                    lessonBoardFocus ? 260.0 : 180.0,
                                  ),
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey('lesson-speech-scroll'),
                              primary: false,
                              child: status,
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder:
                                  (_, space) => Center(
                                    child: SizedBox.square(
                                      dimension: space.maxHeight.clamp(
                                        0.0,
                                        space.maxWidth,
                                      ),
                                      child: board,
                                    ),
                                  ),
                            ),
                          ),
                          own,
                          arsenal,
                          hand,
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * .18,
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey('battle-controls-scroll'),
                              primary: false,
                              child: controls,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final tight = BattleTokens.shortPortrait(context);
              final useBoardDock =
                  compactBoardDock &&
                  !(width <= 430 && !BattleTokens.compactText(context));
              if (BattleTokens.sideDock(context) &&
                  useBoardDock &&
                  width >= 320 &&
                  box.maxHeight >= 500) {
                final boardWidth = (width - 16).clamp(
                  0.0,
                  width <= 360 ? 224.0 : 256.0,
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                            child: Column(
                              children: [
                                opponent,
                                const SizedBox(height: 0),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (_, space) {
                                      final dimension = space.maxHeight.clamp(
                                        0.0,
                                        boardWidth,
                                      );
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox.square(
                                            dimension: dimension,
                                            child: board,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: SingleChildScrollView(
                                              key: const ValueKey(
                                                'battle-side-scroll',
                                              ),
                                              primary: false,
                                              child: Column(
                                                children: [own, status],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(children: [arsenal, hand]),
                        ),
                        if (!controlsDockedAside)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: box.maxHeight * .45,
                              ),
                              child: SingleChildScrollView(
                                key: const ValueKey('battle-controls-scroll'),
                                primary: false,
                                child: controls,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
              if (useBoardDock &&
                  width >= 370 &&
                  BattleTokens.compactText(context) &&
                  box.maxHeight >= 700) {
                final boardWidth = (box.maxHeight * .39).clamp(
                  280.0,
                  (width - 16).clamp(280.0, 420.0),
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        children: [
                          opponent,
                          SizedBox.square(dimension: boardWidth, child: board),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * .13,
                            ),
                            child: SingleChildScrollView(
                              primary: false,
                              child: status,
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey('battle-scroll'),
                              child: Column(children: [own, arsenal, hand]),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * .24,
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey('battle-controls-scroll'),
                              primary: false,
                              child: controls,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (useBoardDock &&
                  !BattleTokens.compactText(context) &&
                  box.maxHeight >= 500) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        children: [
                          opponent,
                          Expanded(
                            child: LayoutBuilder(
                              builder:
                                  (_, space) => Center(
                                    child: SizedBox.square(
                                      dimension: space.maxHeight.clamp(
                                        0.0,
                                        space.maxWidth,
                                      ),
                                      child: board,
                                    ),
                                  ),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * .13,
                            ),
                            child: SingleChildScrollView(
                              primary: false,
                              child: status,
                            ),
                          ),
                          own,
                          arsenal,
                          hand,
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: box.maxHeight * .3,
                            ),
                            child: SingleChildScrollView(
                              key: const ValueKey('battle-controls-scroll'),
                              primary: false,
                              child: controls,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('battle-scroll'),
                          padding: EdgeInsets.fromLTRB(
                            8,
                            tight ? 2 : 4,
                            8,
                            tight ? 4 : 8,
                          ),
                          child: Column(
                            children: [
                              opponent,
                              SizedBox(height: tight ? 2 : 4),
                              Center(
                                child: SizedBox(
                                  width:
                                      MediaQuery.textScalerOf(
                                                context,
                                              ).scale(14) <=
                                              17
                                          ? (box.maxHeight -
                                                  (width >= 450 ? 490 : 478))
                                              .clamp(
                                                (width - 16).clamp(0.0, 224.0),
                                                width - 16,
                                              )
                                          : width - 16,
                                  child: board,
                                ),
                              ),
                              SizedBox(height: tight ? 2 : 4),
                              status,
                              own,
                              arsenal,
                              hand,
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: box.maxHeight * .45,
                          ),
                          child: SingleChildScrollView(
                            key: const ValueKey('battle-controls-scroll'),
                            primary: false,
                            child: controls,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class BattleDeckAccess extends StatelessWidget {
  final bool own;
  final bool compact;
  final int cardCount;
  final VoidCallback onPressed;
  const BattleDeckAccess({
    super.key,
    required this.cardCount,
    required this.onPressed,
    this.own = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final title =
        own
            ? (l.locale.languageCode == 'en' ? 'My Cards' : 'Kartlarım')
            : l.battle(BattleCopy.arsenal);
    final count = l.battleCardCount(cardCount);
    if (compact) {
      return Tooltip(
        message: '$title · $count',
        child: Semantics(
          label: '$title, $count',
          button: true,
          onTap: onPressed,
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: BattleTokens.touch,
              child: IconButton(
                onPressed: onPressed,
                tooltip: null,
                iconSize: 40,
                padding: EdgeInsets.zero,
                icon: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BattleArt('arsenal', size: 20),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        own
                            ? (l.isEnglish ? 'My Cards' : 'Kartlarım')
                            : '${l.isEnglish ? 'Cards' : 'Kartlar'} · $cardCount',
                        style: BattleTokens.caption.copyWith(fontSize: 10),
                        maxLines: 1,
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '$title, $count',
      enabled: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: BattleSkin(
          name: 'command-panel',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(BattleTokens.radius),
              onTap: onPressed,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const BattleArt('arsenal', size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: BattleTokens.card.copyWith(fontSize: 12),
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$cardCount', style: BattleTokens.caption),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BattleLoadingStage extends StatelessWidget {
  final String message;
  final Widget? action;
  const BattleLoadingStage({super.key, required this.message, this.action});
  @override
  Widget build(BuildContext context) {
    if (action != null) {
      return Scaffold(
        backgroundColor: BattleTokens.background,
        body: Stack(
          children: [
            const Positioned.fill(
              child: BattleArt('background', fit: BoxFit.cover),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder:
                    (_, box) => SingleChildScrollView(
                      key: const ValueKey('battle-unavailable-scroll'),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const BattleArt('sync', size: 48),
                                  const SizedBox(height: 16),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      message,
                                      textAlign: TextAlign.center,
                                      style: BattleTokens.body,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  action!,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      label: message,
      child: BattleV1Scaffold(
        opponent: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const BattleArt('sync', size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: BattleTokens.body)),
              const SizedBox(width: 8),
              const SizedBox(
                width: 84,
                height: 48,
                child: BattleSkin(name: 'clock-panel', child: SizedBox()),
              ),
            ],
          ),
        ),
        arsenal: const SizedBox(
          height: 48,
          width: double.infinity,
          child: BattleSkin(name: 'command-panel', child: SizedBox()),
        ),
        board: ExcludeSemantics(
          child: AspectRatio(
            aspectRatio: 1,
            child: BattleSkin(
              name: 'board-frame',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Opacity(
                  opacity: .3,
                  child: GridView.builder(
                    itemCount: 64,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                        ),
                    itemBuilder:
                        (_, i) => ColoredBox(
                          color:
                              (i ~/ 8 + i % 8).isEven
                                  ? BattleTokens.lightSquare
                                  : BattleTokens.darkSquare,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
        status: const SizedBox(height: 16),
        own: const SizedBox(
          height: 48,
          child: BattleSkin(name: 'clock-panel', child: SizedBox(width: 96)),
        ),
        hand: ExcludeSemantics(
          child: SizedBox(
            height: 145,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  const Expanded(
                    child: BattleSkin(
                      name: 'card-frame',
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        controls: action ?? const SizedBox(height: 48),
      ),
    );
  }
}
