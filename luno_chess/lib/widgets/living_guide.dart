import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../battle_ui/art.dart';
import '../engine/piece.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../theme/luno_theme.dart';
import 'luno_arcane_halo.dart';
import 'luno_surface.dart';

/// A presentation-only example after the first turn. It never owns a match,
/// account, or reward, and cannot change a player's learning checkpoint.
class GuideTurnDemo extends StatefulWidget {
  const GuideTurnDemo({super.key, this.onCue});

  final VoidCallback? onCue;

  @override
  State<GuideTurnDemo> createState() => _GuideTurnDemoState();
}

class _GuideTurnDemoState extends State<GuideTurnDemo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _impact;
  int _step = 0;
  bool _foreground = true;

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
    _impact = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motion) _settle();
  }

  void _settle() {
    _impact.stop();
    _impact.value = 1;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() => _foreground = foreground);
    if (!foreground) _settle();
  }

  void _advance() {
    if (!_foreground || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() => _step = (_step + 1) % 3);
    if (_motion) {
      _impact.forward(from: 0);
    } else {
      _settle();
    }
    widget.onCue?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _impact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final mana = _step == 0 ? 2 : 0;
    final hand = _step == 1 ? 2 : 3;
    final status = switch (_step) {
      0 => l.learning(
        'Siper için 2 mana hazır. Kendi filini korumayı dene.',
        'You have the 2 mana for Shelter. Try protecting your bishop.',
      ),
      1 => l.learning(
        'Siper oynandı: 2 mana harcandı, fil korundu. Şimdi taş hamlen var.',
        'Shelter is played: 2 mana spent, bishop protected. Your chess move is next.',
      ),
      _ => l.learning(
        'e2-e4. Hamle tamamlandı; elde yer olduğu için 1 kart çekildi. Mana hâlâ 0.',
        'e2-e4. Move completed; room in hand lets you draw 1 card. Mana is still 0.',
      ),
    };
    return Container(
      key: const ValueKey('guide-turn-demo'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LunoColors.bgDeep.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LunoColors.gold.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.learning('BİR TURU BİRLİKTE DENE', 'TRY ONE TURN TOGETHER'),
            style: LunoType.sectionTitle,
          ),
          const SizedBox(height: 6),
          Text(
            l.learning(
              'İlk turdan sonraki küçük bir örnek',
              'A small example after the first turn',
            ),
            style: LunoType.bodyMuted,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, label)
                  in [
                    l.learning('Kart', 'Card'),
                    l.learning('Hamle', 'Move'),
                    l.learning('Kart çek', 'Draw'),
                  ].indexed)
                Semantics(
                  selected: _step == i,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _step == i
                              ? LunoColors.gold.withValues(alpha: .16)
                              : LunoColors.bgPanel,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: _step == i ? LunoColors.gold : LunoColors.line,
                      ),
                    ),
                    child: Text(
                      '${i + 1} · $label',
                      style: LunoType.body.copyWith(
                        color:
                            _step == i ? LunoColors.gold : LunoColors.textDim,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cell = constraints.maxWidth / 8;
                    Widget piece(
                      int row,
                      int col,
                      PieceColor side,
                      PieceType type,
                    ) => Positioned(
                      left: col * cell,
                      top: row * cell,
                      width: cell,
                      height: cell,
                      child: Padding(
                        padding: EdgeInsets.all(cell * .08),
                        child: Image.asset(
                          BattleArt.piecePath(side, type),
                          cacheWidth: 112,
                        ),
                      ),
                    );
                    final pawn = Padding(
                      padding: EdgeInsets.all(cell * .08),
                      child: Image.asset(
                        BattleArt.piecePath(PieceColor.white, PieceType.pawn),
                        cacheWidth: 112,
                      ),
                    );
                    return Semantics(
                      label: l.learning(
                        'Örnek tahta: c3 filine Siper, ardından e2-e4 piyon hamlesi.',
                        'Example board: Shelter on the c3 bishop, then the e2-e4 pawn move.',
                      ),
                      image: true,
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _GuideBoardPainter(
                                      step: _step,
                                      impact: _impact,
                                    ),
                                  ),
                                ),
                                if (_step > 0)
                                  Positioned(
                                    left:
                                        (_step == 1 ? 2.5 : 4.5) * cell -
                                        cell * 1.3,
                                    top:
                                        (_step == 1 ? 5.5 : 4.5) * cell -
                                        cell * 1.3,
                                    width: cell * 2.6,
                                    height: cell * 2.6,
                                    child: AnimatedBuilder(
                                      animation: _impact,
                                      builder:
                                          (_, _) => LunoArcaneHalo(
                                            progress: _impact.value,
                                            size: cell * 2.6,
                                            color:
                                                _step == 1
                                                    ? LunoColors.cyan
                                                    : LunoColors.gold,
                                            opacity: .85,
                                          ),
                                    ),
                                  ),
                                piece(0, 6, PieceColor.black, PieceType.king),
                                piece(2, 2, PieceColor.black, PieceType.rook),
                                piece(5, 2, PieceColor.white, PieceType.bishop),
                                piece(7, 6, PieceColor.white, PieceType.king),
                                if (_motion)
                                  AnimatedPositioned(
                                    key: const ValueKey('guide-demo-pawn'),
                                    duration: const Duration(milliseconds: 480),
                                    curve: Curves.easeInOutCubic,
                                    left: 4 * cell,
                                    top: (_step == 2 ? 4 : 6) * cell,
                                    width: cell,
                                    height: cell,
                                    child: pawn,
                                  )
                                else
                                  // Remove the implicit controller as well as
                                  // the impact clock when motion is disabled.
                                  Positioned(
                                    key: const ValueKey('guide-demo-pawn'),
                                    left: 4 * cell,
                                    top: (_step == 2 ? 4 : 6) * cell,
                                    width: cell,
                                    height: cell,
                                    child: pawn,
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
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _GuideResource(
                art: 'mana',
                text: '$mana / 6 ${l.learning('mana', 'mana')}',
                semanticKey: 'guide-demo-mana',
              ),
              _GuideResource(
                art: 'phase-card',
                text: '${l.learning('El', 'Hand')} $hand / 4',
                semanticKey: 'guide-demo-hand',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              status,
              key: ValueKey('guide-demo-status-$_step'),
              style: LunoType.body.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 14),
          // LunoButton already supplies visible press feedback and makes its
          // ink transparent. Avoid starting an invisible Material3 sparkle
          // shader/ticker that could outlive this demo's lifecycle settlement.
          Theme(
            data: Theme.of(
              context,
            ).copyWith(splashFactory: NoSplash.splashFactory),
            child: LunoButton(
              key: const ValueKey('guide-demo-next'),
              label: switch (_step) {
                0 => l.learning(
                  'SİPER’İ OYNA · 2 MANA',
                  'PLAY SHELTER · 2 MANA',
                ),
                1 => l.learning('PİYONU OYNA · e2-e4', 'MOVE THE PAWN · e2-e4'),
                _ => l.learning('ÖRNEĞİ YENİDEN OYNAT', 'REPLAY THE EXAMPLE'),
              },
              icon:
                  _step == 2 ? Icons.replay_rounded : Icons.play_arrow_rounded,
              onPressed: _advance,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideResource extends StatelessWidget {
  const _GuideResource({
    required this.art,
    required this.text,
    required this.semanticKey,
  });
  final String art, text, semanticKey;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      BattleArt(art, size: 24),
      const SizedBox(width: 6),
      Text(
        text,
        key: ValueKey(semanticKey),
        style: LunoType.body.copyWith(
          color: LunoColors.cyan,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _GuideBoardPainter extends CustomPainter {
  _GuideBoardPainter({required this.step, required this.impact})
    : super(repaint: impact);
  final int step;
  final Animation<double> impact;
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final paint = Paint();
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        paint.color =
            (row + col).isEven
                ? const Color(0xFFD7D7C9)
                : const Color(0xFF263D4D);
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell, cell),
          paint,
        );
      }
    }
    if (step > 0) {
      final center = Offset(cell * 2.5, cell * 5.5);
      final t = impact.value;
      paint
        ..color = LunoColors.cyan.withValues(alpha: .22)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(cell * 2, cell * 5, cell, cell), paint);
      paint
        ..color = LunoColors.cyan.withValues(alpha: .75)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, cell * .45, paint);
      if (t < 1) {
        paint.color = LunoColors.cyan.withValues(alpha: (1 - t) * .8);
        canvas.drawCircle(
          center,
          cell * (.45 + Curves.easeOut.transform(t) * .9),
          paint,
        );
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4 + t * .4;
          final p =
              center +
              Offset(math.cos(angle), math.sin(angle)) * cell * (.4 + t * .8);
          canvas.drawLine(
            p,
            p + Offset(math.cos(angle), math.sin(angle)) * 3,
            paint,
          );
        }
      }
    }
    if (step == 1) {
      paint
        ..color = LunoColors.gold
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final from = Offset(cell * 4.5, cell * 6.2),
          to = Offset(cell * 4.5, cell * 4.5);
      canvas.drawLine(from, to, paint);
      canvas.drawLine(to, to + Offset(-cell * .16, cell * .23), paint);
      canvas.drawLine(to, to + Offset(cell * .16, cell * .23), paint);
    }
    if (step == 2) {
      paint
        ..color = LunoColors.gold.withValues(alpha: .3)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(cell * 4, cell * 4, cell, cell), paint);
    }
  }

  @override
  bool shouldRepaint(_GuideBoardPainter oldDelegate) =>
      oldDelegate.step != step || oldDelegate.impact != impact;
}
