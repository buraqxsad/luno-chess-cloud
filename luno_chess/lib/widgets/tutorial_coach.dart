import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_ui/mentor.dart';
import '../battle_ui/tokens.dart';

/// A single current action, kept beside its lesson object rather than a checklist.
class TutorialCoach extends StatelessWidget {
  final String text;
  final Object cue;
  final bool portrait, feedback;
  final String? heading;
  const TutorialCoach({
    super.key,
    required this.text,
    required this.cue,
    this.portrait = true,
    this.feedback = false,
    this.heading,
  });

  static final textStyle = BattleTokens.body.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: const Color(0xFF20333E),
  );

  static double heightFor(BuildContext context, String text, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1, width - 90));
    final height = math.max(
      64.0,
      painter.height + 29 + MediaQuery.textScalerOf(context).scale(11) * 1.2,
    );
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (portrait) ...[
        BattleMentor(cue: cue, width: 56, height: 76),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: AnimatedContainer(
            duration: BattleTokens.duration(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: feedback ? BattleTokens.gold : const Color(0xFF86B7AA),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x20000000),
                  offset: Offset(0, 3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        heading ?? 'LUNO',
                        style: BattleTokens.caption.copyWith(
                          fontSize: 11,
                          height: 1.2,
                          color: const Color(0xFF2E6E61),
                        ),
                      ),
                    ),
                    if (feedback) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.touch_app_rounded,
                        size: 14,
                        color: BattleTokens.gold,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(text, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
