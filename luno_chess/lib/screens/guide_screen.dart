import 'package:flutter/material.dart';
import '../battle_ui/art.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../navigation/luno_route.dart';
import '../theme/luno_theme.dart';
import '../widgets/luno_surface.dart';
import 'battle_deck_screen.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final lessons = l.battleLessons;
    return Scaffold(
      appBar: AppBar(title: Text(l.learning('REHBER', 'GUIDE'))),
      body: LunoBackdrop(
        art: 'assets/native_art/guide-scene-v36.png',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
          children: [
            Text(
              l.learning('Tahta. Kart. Karar.', 'Board. Card. Decision.'),
              style: LunoType.screenTitle,
            ),
            const SizedBox(height: 8),
            Text(
              l.learning(
                'Luno savaşının güncel kuralları',
                'The current rules of a Luno battle',
              ),
              style: LunoType.bodyMuted,
            ),
            const SizedBox(height: 18),
            for (final i in [0, 1, 2, 3, 4, 5, 6, 7, 8])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        BattleArt(
                          i == 3
                              ? 'mana'
                              : i == 1
                              ? 'phase-move'
                              : 'phase-card',
                          size: 34,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            lessons[i].title,
                            style: LunoType.sectionTitle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lessons[i].body,
                      style: LunoType.bodyMuted.copyWith(
                        color: LunoColors.ivory,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lessons[i].hint,
                      style: LunoType.bodyMuted.copyWith(height: 1.4),
                    ),
                    if (i == 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        l.learning(
                          'Rok, geçerken alma ve piyon terfisi geçerlidir. Kart etkileri izin verilen hamleleri değiştirebilir; hiçbir hamle kendi şahını tehditte bırakamaz.',
                          'Castling, en passant and pawn promotion apply. Card effects can change available moves; no move may leave your own king in check.',
                        ),
                        style: LunoType.bodyMuted.copyWith(height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                  ],
                ),
              ),
            LunoButton(
              label: l.learning('SAVAŞ KARTLARI', 'BATTLE CARDS'),
              icon: Icons.style_rounded,
              onPressed: () {
                if (ModalRoute.of(context)?.isCurrent == true) {
                  Navigator.of(
                    context,
                  ).push(lunoRoute(const BattleDeckScreen(catalogOnly: true)));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
