import 'package:flutter/material.dart';
import '../i18n/luno_localizations.dart';
import '../services/battle_v1_deck_result.dart';
import '../theme/luno_theme.dart';

/// Presentation of validated public progress; never evaluates ownership itself.
class BattleUnlockProgress extends StatelessWidget {
  final BattleUnlockMilestone milestone;
  final bool compact;
  const BattleUnlockProgress({
    super.key,
    required this.milestone,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    final requirements = milestone.requirements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < requirements.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                english ? 'OR' : 'VEYA',
                textAlign: TextAlign.center,
                style: LunoType.bodyMuted.copyWith(fontSize: 11),
              ),
            ),
          Builder(
            builder: (context) {
              final requirement = requirements[i];
              final current = requirement.current.clamp(0, requirement.target);
              final label = switch (requirement.kind) {
                BattleUnlockKind.rankedMatches =>
                  english ? 'Ranked matches' : 'Sıralı maç',
                BattleUnlockKind.welcomeClaim =>
                  english ? 'Welcome reward' : 'Karşılama ödülü',
                BattleUnlockKind.dailyClaimDays =>
                  english ? 'Daily reward days' : 'Günlük ödül günü',
              };
              return Semantics(
                label: '$label: $current / ${requirement.target}',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '$label  $current/${requirement.target}',
                        textAlign: compact ? TextAlign.center : TextAlign.start,
                        style: LunoType.bodyMuted.copyWith(
                          fontSize: compact ? 12 : 14,
                          color: LunoColors.ivory,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: current / requirement.target,
                          minHeight: compact ? 3 : 5,
                          color: LunoColors.cyan,
                          backgroundColor: LunoColors.bgRaised,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
