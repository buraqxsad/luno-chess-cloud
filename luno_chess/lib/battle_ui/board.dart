import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../engine/move_gen.dart';
import '../engine/square.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import 'art.dart';
import 'tokens.dart';
import 'effects.dart';
import 'feedback.dart';
import 'target_motion.dart';
import '../data/board_finishes.dart';
import 'accepted_frames.dart';

class BattleBoard extends StatefulWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final int? selected;
  final Set<int> targets, preview;
  final bool enabled;
  final bool externalCastAnimation;
  final int synchronizationEpoch;
  final String pieceSet;
  final String finish;
  final void Function(int) onTap;
  const BattleBoard({
    super.key,
    required this.view,
    this.acceptedFrames,
    this.selected,
    this.targets = const {},
    this.preview = const {},
    this.enabled = true,
    this.externalCastAnimation = false,
    this.synchronizationEpoch = 0,
    this.pieceSet = 'luno',
    this.finish = 'classic',
    required this.onTap,
  });
  @override
  State<BattleBoard> createState() => _BattleBoardState();
}

class _MovingPiece {
  final String id;
  final Piece piece;
  final int from, to;
  const _MovingPiece(this.id, this.piece, this.from, this.to);
}

class _BattleBoardState extends State<BattleBoard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  List<_MovingPiece> _moving = const [];
  bool _foreground = true;
  PlayerView get view => widget.view;
  int? get selected => widget.selected;
  Set<int> get targets => widget.targets;
  Set<int> get preview => widget.preview;
  bool get enabled => widget.enabled;
  void Function(int) get onTap => widget.onTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _moving = const []);
      }
    });
  }

  void _clearMotion() {
    _motion.stop();
    _moving = const [];
  }

  @override
  void didUpdateWidget(BattleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.synchronizationEpoch != widget.synchronizationEpoch ||
        !_foreground ||
        oldWidget.view.viewer != view.viewer ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        view.rules.terminal != null ||
        view.rules.ply < oldWidget.view.rules.ply ||
        view.rules.effectSequence < oldWidget.view.rules.effectSequence) {
      _clearMotion();
      return;
    }
    final moved = <_MovingPiece>[];
    for (var to = 0; to < 64; to++) {
      final id = view.rules.pieceIds[to], piece = view.rules.board.pieceAt(to);
      if (id == null || piece == null) continue;
      final from = oldWidget.view.rules.pieceIds.indexOf(id);
      if (from >= 0 && from != to) moved.add(_MovingPiece(id, piece, from, to));
    }
    if (moved.isNotEmpty) {
      _moving = moved;
      _motion.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _clearMotion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_clearMotion);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.finish != 'classic')
            IgnorePointer(
              child: DecoratedBox(
                key: ValueKey('board-finish-${widget.finish}'),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: boardFinish(widget.finish).color,
                    width: 4,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
              ),
              itemCount: 64,
              itemBuilder: (context, i) {
                final row = i ~/ 8,
                    col = i % 8,
                    flipped = view.viewer == PieceColor.black;
                final square = Square.of(
                  flipped ? 7 - col : col,
                  flipped ? row : 7 - row,
                );
                final piece = view.rules.board.pieceAt(square);
                final l = LunoLocalizations.of(context);
                final name =
                    piece == null
                        ? l.battle(BattleCopy.empty)
                        : '${l.battle(piece.color.isWhite ? BattleCopy.white : BattleCopy.black)} ${l.battlePiece(piece.type)}';
                final effects = [
                  ...view.rules.boardEffects
                      .where((e) => e.squares.contains(square))
                      .map((e) => l.battleCardName(boardEffectCard(e.type))),
                  ...view.rules.pieceEffects
                      .where((e) => e.pieceId == view.rules.pieceIds[square])
                      .map((e) => l.battleCardName(pieceEffectCard(e.type))),
                  ...view.rules.vows
                      .where(
                        (v) =>
                            v.square == square ||
                            v.pieceId != null &&
                                v.pieceId == view.rules.pieceIds[square],
                      )
                      .map(
                        (v) => l.battleCardName(
                          v.type == VowType.hunt
                              ? CardId.huntVow
                              : CardId.watchVow,
                        ),
                      ),
                ];
                return Semantics(
                  label:
                      '${Square.algebraic(square)}, $name${effects.isEmpty ? '' : ', ${effects.join(', ')}'}',
                  button: true,
                  selected: selected == square || preview.contains(square),
                  value:
                      targets.contains(square)
                          ? l.battle(BattleCopy.legalTarget)
                          : null,
                  enabled: enabled,
                  child: ExcludeSemantics(
                    child: Material(
                      color:
                          (row + col).isEven
                              ? BattleTokens.lightSquare
                              : BattleTokens.darkSquare,
                      child: InkWell(
                        key: ValueKey('square-$square'),
                        onTap: enabled ? () => onTap(square) : null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            BattleFloorEffects(
                              rules: view.rules,
                              viewer: view.viewer,
                              square: square,
                            ),
                            if (preview.contains(square))
                              DecoratedBox(
                                key: ValueKey('card-preview-$square'),
                                decoration: BoxDecoration(
                                  color: BattleTokens.gold.withValues(
                                    alpha: .2,
                                  ),
                                  border: Border.all(
                                    color: BattleTokens.gold,
                                    width: 3,
                                  ),
                                ),
                              ),
                            if (!_moving.any(
                              (move) => move.id == view.rules.pieceIds[square],
                            ))
                              BattlePieceEffects(
                                rules: view.rules,
                                square: square,
                                aurasOnly: true,
                              ),
                            if (piece != null &&
                                !_moving.any(
                                  (m) => m.id == view.rules.pieceIds[square],
                                ))
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: Image.asset(
                                  BattleArt.piecePath(
                                    piece.color,
                                    piece.type,
                                    set: widget.pieceSet,
                                  ),
                                  fit: BoxFit.contain,
                                  cacheWidth: 128,
                                ),
                              ),
                            if (selected == square)
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: BattleTokens.mana,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            if (!_moving.any(
                              (move) => move.id == view.rules.pieceIds[square],
                            ))
                              BattlePieceEffects(
                                rules: view.rules,
                                square: square,
                              ),
                            if (piece?.type == PieceType.king &&
                                MoveGen.inCheck(view.rules.board, piece!.color))
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: BattleTokens.danger,
                                    width: 3,
                                  ),
                                ),
                              ),
                            if (targets.contains(square) &&
                                !preview.contains(square))
                              Center(
                                child:
                                    piece == null
                                        ? Container(
                                          width: 14,
                                          height: 14,
                                          decoration: const BoxDecoration(
                                            color: BattleTokens.mana,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                        : FractionallySizedBox(
                                          widthFactor: .88,
                                          heightFactor: .88,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: BattleTokens.mana,
                                                width: 2,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                              ),
                            if (preview.contains(square))
                              const Positioned(
                                top: 1,
                                right: 1,
                                child: Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: BattleTokens.gold,
                                ),
                              ),
                            if (col == 0)
                              Positioned(
                                top: 1,
                                left: 2,
                                child: Text(
                                  '${(square >> 3) + 1}',
                                  textScaler: TextScaler.noScaling,
                                  style: BattleTokens.card.copyWith(
                                    fontSize: 9,
                                    color:
                                        (row + col).isEven
                                            ? BattleTokens.darkSquare
                                            : BattleTokens.ivory,
                                  ),
                                ),
                              ),
                            if (row == 7)
                              Positioned(
                                bottom: 0,
                                right: 2,
                                child: Text(
                                  String.fromCharCode(97 + (square & 7)),
                                  textScaler: TextScaler.noScaling,
                                  style: BattleTokens.card.copyWith(
                                    fontSize: 9,
                                    color:
                                        (row + col).isEven
                                            ? BattleTokens.darkSquare
                                            : BattleTokens.ivory,
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
          if (enabled && targets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(6),
              child: BattleTargetArrival(
                key: ValueKey(
                  'targets-${view.viewer.name}-${(targets.toList()..sort()).join(',')}',
                ),
                viewer: view.viewer,
                squares: targets,
              ),
            ),
          if (_moving.isNotEmpty)
            IgnorePointer(
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: RepaintBoundary(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final cell = box.maxWidth / 8;
                        Offset position(int square) => Offset(
                          (view.viewer.isWhite
                                  ? Square.fileOf(square)
                                  : 7 - Square.fileOf(square)) *
                              cell,
                          (view.viewer.isWhite
                                  ? 7 - Square.rankOf(square)
                                  : Square.rankOf(square)) *
                              cell,
                        );
                        return AnimatedBuilder(
                          animation: _motion,
                          builder:
                              (context, _) => Stack(
                                children: [
                                  for (final move in _moving)
                                    Positioned.fromRect(
                                      key: ValueKey('moving-piece-${move.id}'),
                                      rect:
                                          (Offset.lerp(
                                                position(move.from),
                                                position(move.to),
                                                Curves.easeInOutCubic.transform(
                                                  _motion.value,
                                                ),
                                              )! &
                                              Size.square(cell)),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          BattlePieceEffects(
                                            rules: view.rules,
                                            square: move.to,
                                            aurasOnly: true,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Image.asset(
                                              BattleArt.piecePath(
                                                move.piece.color,
                                                move.piece.type,
                                                set: widget.pieceSet,
                                              ),
                                              cacheWidth: 128,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                          BattlePieceEffects(
                                            rules: view.rules,
                                            square: move.to,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          BattleAcceptedFeedback(
            acceptedFrames: widget.acceptedFrames,
            view: view,
            synchronizationEpoch: widget.synchronizationEpoch,
            showAnnouncements: false,
            showProjectiles: !widget.externalCastAnimation,
          ),
          IgnorePointer(
            child: ClipPath(
              clipper: const _FrameEdgeClipper(),
              child: const BattleArt('board-frame', fit: BoxFit.fill),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FrameEdgeClipper extends CustomClipper<Path> {
  const _FrameEdgeClipper();
  @override
  Path getClip(Size size) =>
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(Rect.fromLTWH(6, 6, size.width - 12, size.height - 12));
  @override
  bool shouldReclip(_FrameEdgeClipper oldClipper) => false;
}
