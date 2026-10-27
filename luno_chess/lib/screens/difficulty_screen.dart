import 'package:flutter/material.dart' hide Text;
import '../i18n/luno_text.dart';
import '../engine/ai.dart';
import '../theme/luno_theme.dart';
import '../theme/luno_assets.dart';
import '../navigation/luno_route.dart';
import '../widgets/luno_surface.dart';
import '../services/luno_feedback.dart';
import '../widgets/game_time_control_picker.dart';
import 'battle_v1_screen.dart';

/// Luno eğitmeni (zorluk) seçimi.
class DifficultyScreen extends StatefulWidget {
  const DifficultyScreen({super.key});

  @override
  State<DifficultyScreen> createState() => _DifficultyScreenState();
}

class _DifficultyScreenState extends State<DifficultyScreen> {
  bool _selecting = false;

  Future<void> _choose(AiLevel level) async {
    if (!mounted || _selecting || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => _selecting = true);
    LunoFeedback.tap();
    try {
      final minutes = await showGameTimeControlPicker(context);
      if (!mounted ||
          minutes == null ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await Navigator.of(context).push(
        lunoRoute(BattleV1Screen(level: level, timeControlMinutes: minutes)),
      );
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LunoColors.bgPanel,
        title: const Text('LUNO EĞİTMENİ SEÇ'),
      ),
      body: LunoBackdrop(
        art: LunoAssets.phase2GameplayAtmosphere,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, -.15),
        child: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: aiLevels.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final lvl = aiLevels[i];
              final portrait = LunoAssets.aiPortrait(lvl.id);
              return Material(
                color: LunoColors.bgPanel,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _selecting ? null : () => _choose(lvl),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: LunoColors.bgDeep,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: LunoColors.gold.withValues(alpha: .42),
                            ),
                          ),
                          child: LunoArt(portrait),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lvl.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: LunoColors.gold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lvl.desc,
                                style: const TextStyle(
                                  color: LunoColors.textDim,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const LunoArt(
                                    LunoAssets.statusTrophy,
                                    width: 28,
                                    height: 28,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '≈${lvl.power}',
                                      style: const TextStyle(
                                        color: Color(0xFFC5DED5),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF8DB9AD),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
