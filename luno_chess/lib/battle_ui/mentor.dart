import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/luno_mentor_portrait.dart';
import 'tokens.dart';

class LunoLessonSpeech extends StatelessWidget {
  final String text;
  final Object cue;
  final bool portrait;
  const LunoLessonSpeech({
    super.key,
    required this.text,
    required this.cue,
    this.portrait = true,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (portrait) ...[
        BattleMentor(cue: cue, width: 68, height: 86),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xF01B4144),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF6EB5A6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LUNO',
                  style: BattleTokens.caption.copyWith(
                    color: BattleTokens.gold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: BattleTokens.body.copyWith(
                    fontSize: 16,
                    height: 1.3,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class BattleMentor extends StatefulWidget {
  final Object cue;
  final double width, height;
  final Widget? child;
  final bool idle;
  const BattleMentor({
    super.key,
    required this.cue,
    this.width = 54,
    this.height = 76,
    this.child,
    this.idle = false,
  });
  @override
  State<BattleMentor> createState() => _BattleMentorState();
}

class _BattleMentorState extends State<BattleMentor>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  Timer? _idle;
  bool _started = false, _foreground = true;
  bool get _enabled =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addStatusListener(_onMotionStatus);
  }

  void _onMotionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _scheduleIdle();
  }

  void _scheduleIdle() {
    if (!mounted || !widget.idle || !_enabled || _motion.isAnimating) {
      _idle?.cancel();
      _idle = null;
      return;
    }
    // Unrelated parent/theme rebuilds must not postpone a sleeping gesture.
    if (_idle?.isActive ?? false) return;
    // Sleep between short gestures: no continuous ticker, shader or video.
    _idle = Timer(const Duration(milliseconds: 4700), () {
      _idle = null;
      if (mounted && widget.idle && _enabled) _motion.forward(from: 0);
    });
  }

  void _settle() {
    _idle?.cancel();
    _idle = null;
    _motion.stop();
    if (_motion.value != 1) _motion.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled) {
      _started = true;
      _settle();
    } else if (!_started) {
      _started = true;
      _motion.forward();
    } else if (!_motion.isAnimating) {
      _scheduleIdle();
    }
  }

  @override
  void didUpdateWidget(BattleMentor old) {
    super.didUpdateWidget(old);
    if (!_enabled) {
      _settle();
    } else if (old.cue != widget.cue) {
      _idle?.cancel();
      _motion.forward(from: 0);
    } else if (!_motion.isAnimating) {
      _scheduleIdle();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _settle();
    } else {
      _scheduleIdle();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    _motion.removeStatusListener(_onMotionStatus);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          child: widget.child,
          builder: (_, child) {
            final t = _motion.value, nod = math.sin(t * math.pi) * (1 - t);
            return Transform(
              alignment: Alignment.bottomCenter,
              transform:
                  Matrix4.identity()
                    ..setEntry(3, 2, .001)
                    ..translateByDouble(0, -5 * nod, 0, 1)
                    ..rotateY(.2 * nod)
                    ..rotateZ(.09 * math.sin(t * math.pi * 2) * (1 - t)),
              child:
                  child ??
                  Center(
                    child: LunoMentorPortrait(
                      progress: _motion.value,
                      size: math.min(widget.width, widget.height),
                    ),
                  ),
            );
          },
        ),
      ),
    ),
  );
}
