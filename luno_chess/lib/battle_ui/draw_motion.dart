import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tokens.dart';

/// A short wind-up, bounded arc, then a small landing compression.
Offset battleOpponentDrawPoint(Offset from, Offset to, double progress) {
  final p = progress.clamp(0.0, 1.0);
  if (p == 0) return from;
  if (p == 1) return to;
  final distance = (to - from).distance;
  if (p < .12) {
    final direction = distance > 0 ? (to - from) / distance : Offset.zero;
    return from - direction * (math.sin(p / .12 * math.pi) * 3);
  }
  final travel = Curves.easeInOutCubic.transform(
    ((p - .12) / .70).clamp(0.0, 1.0),
  );
  final settle = ((p - .82) / .18).clamp(0.0, 1.0);
  final lift = math.min(52.0, distance * .16);
  return Offset.lerp(from, to, travel)! -
      Offset(
        0,
        math.sin(travel * math.pi) * lift + math.sin(settle * math.pi) * 3,
      );
}

class BattleClosedCard extends StatelessWidget {
  const BattleClosedCard({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: BattleTokens.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BattleTokens.gold, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          'assets/native_art/battle-draw-pile-v208.webp',
          fit: BoxFit.contain,
          cacheWidth: 144,
        ),
      ),
    ),
  );
}

/// Closed-card-only feedback: this component has no card identity input.
class BattleOpponentDraw extends StatefulWidget {
  final int? trigger;
  final GlobalKey source, target;
  final Widget child;
  const BattleOpponentDraw({
    super.key,
    this.trigger,
    required this.source,
    required this.target,
    required this.child,
  });
  @override
  State<BattleOpponentDraw> createState() => _BattleOpponentDrawState();
}

class _BattleOpponentDrawState extends State<BattleOpponentDraw>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _from = _to = null);
    }
  });
  final _stage = GlobalKey();
  Offset? _from, _to;
  bool _foreground = true;
  int _generation = 0;
  bool get _enabled =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  void _clear() {
    _generation++;
    _animation.stop();
    _from = _to = null;
  }

  @override
  void didUpdateWidget(BattleOpponentDraw old) {
    super.didUpdateWidget(old);
    if (widget.trigger == null || !_enabled) {
      _clear();
      return;
    }
    if (widget.trigger == old.trigger) return;
    _clear();
    final trigger = widget.trigger;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          widget.trigger != trigger ||
          !_enabled) {
        return;
      }
      final stage = _stage.currentContext?.findRenderObject();
      final source = widget.source.currentContext?.findRenderObject();
      final target = widget.target.currentContext?.findRenderObject();
      if (stage is! RenderBox ||
          source is! RenderBox ||
          target is! RenderBox ||
          !stage.attached ||
          !source.attached ||
          !target.attached ||
          !stage.hasSize ||
          !source.hasSize ||
          !target.hasSize ||
          stage.size.isEmpty ||
          source.size.isEmpty ||
          target.size.isEmpty) {
        return;
      }
      final from = stage.globalToLocal(
        source.localToGlobal(source.size.center(Offset.zero)),
      );
      final to = stage.globalToLocal(
        target.localToGlobal(target.size.center(Offset.zero)),
      );
      if (!from.dx.isFinite ||
          !from.dy.isFinite ||
          !to.dx.isFinite ||
          !to.dy.isFinite) {
        return;
      }
      setState(() {
        _from = from;
        _to = to;
      });
      _animation.forward(from: 0);
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
    if (!_foreground && mounted) {
      setState(_clear);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: _stage,
    children: [
      widget.child,
      AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          if (!_enabled ||
              _from == null ||
              _to == null ||
              _animation.value >= 1) {
            return const SizedBox.shrink();
          }
          final p = _animation.value;
          final travel = ((p - .12) / .70).clamp(0.0, 1.0);
          final settle = ((p - .82) / .18).clamp(0.0, 1.0);
          final airborne = math.sin(travel * math.pi);
          final position =
              battleOpponentDrawPoint(_from!, _to!, p) - const Offset(14, 20);
          final direction = _to!.dx >= _from!.dx ? 1.0 : -1.0;
          final scale = 1 + airborne * .12 - math.sin(settle * math.pi) * .045;
          return Positioned(
            left: position.dx,
            top: position.dy,
            width: 28,
            height: 40,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: (1 - Curves.easeInCubic.transform(settle)).clamp(
                    0,
                    1,
                  ),
                  child: Transform(
                    key: const ValueKey('opponent-draw-pose'),
                    alignment: Alignment.center,
                    transformHitTests: false,
                    transform:
                        Matrix4.identity()
                          ..setEntry(3, 2, .0015)
                          ..rotateY(direction * airborne * .34)
                          ..rotateZ(
                            direction * (-.08 * (1 - travel) + airborne * .22),
                          )
                          ..scaleByDouble(scale, scale, scale, 1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .30),
                            blurRadius: 4 + airborne * 9,
                            offset: Offset(0, 2 + airborne * 6),
                          ),
                          BoxShadow(
                            color: BattleTokens.gold.withValues(
                              alpha: airborne * .24,
                            ),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const BattleClosedCard(
                        key: ValueKey('opponent-closed-draw'),
                      ),
                    ),
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
