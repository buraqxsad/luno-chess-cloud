import 'package:flutter/material.dart' hide Text;

import '../data/arena_progression_preview.dart';
import '../data/rank_catalog.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/luno_text.dart';
import '../navigation/luno_route.dart';
import '../screens/legacy_parity_screens.dart';
import '../screens/native_hubs_screen.dart';
import '../theme/luno_theme.dart';

/// This is a catalog preview, never an earned/claimable balance or a grant.
class ArenaProgressionBenefits extends StatelessWidget {
  final int arenaIndex;
  const ArenaProgressionBenefits({super.key, required this.arenaIndex});

  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    final path = arenaPathPreview(arenaIndex);
    final achievement = nextArenaAchievementPreview(arenaIndex);
    final nextPath = kArenaPathPreviews[arenaForIndex(arenaIndex).index + 1];
    return Column(
      key: const ValueKey('arena-real-benefits'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          english ? 'REWARDS ON YOUR PATH' : 'YOLUNDAKİ ÖDÜLLER',
          localize: false,
          style: const TextStyle(
            color: LunoColors.gold,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        _BenefitLine(
          icon: Icons.route_rounded,
          label:
              english
                  ? 'Season path · ${formatTrophies(path.trophies)} peak trophies'
                  : 'Sezon yolu · ${formatTrophies(path.trophies)} kupa zirvesi',
          gold: path.gold,
          gems: path.gems,
        ),
        const SizedBox(height: 10),
        _BenefitLine(
          icon: Icons.emoji_events_outlined,
          label:
              english
                  ? 'Achievement · Arena ${achievement.arenaNumber}'
                  : 'Başarım · Arena ${achievement.arenaNumber}',
          gold: achievement.gold,
          gems: achievement.gems,
        ),
        const SizedBox(height: 10),
        Text(
          arenaIndex >= kArenaCatalog.length - 1
              ? (english
                  ? 'Beyond Arena 9 · Season milestone at ${formatTrophies(nextPath.trophies)} peak trophies'
                  : 'Arena 9 sonrası · ${formatTrophies(nextPath.trophies)} kupa zirvesinde sezon hedefi')
              : (english
                  ? 'Season path target: ${formatTrophies(nextPath.trophies)} peak trophies'
                  : 'Sezon yolu hedefi: ${formatTrophies(nextPath.trophies)} kupa zirvesi'),
          key: const ValueKey('arena-season-next'),
          localize: false,
          style: LunoType.bodyMuted,
        ),
        const SizedBox(height: 8),
        Text(
          english
              ? 'Reward preview. Season peak and achievement progress are separate server tracks. Check claim status on their pages; promotion grants no automatic reward.'
              : 'Ödül önizlemesi. Sezon zirvesi ve başarımlar sunucuda ayrı ilerler. Alınma durumunu ilgili ekranda gör; arena yükselişi otomatik ödül vermez.',
          localize: false,
          style: LunoType.bodyMuted.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('arena-season-rewards'),
              icon: const Icon(Icons.route_rounded),
              label: Text(
                english ? 'Season rewards' : 'Sezon ödülleri',
                localize: false,
              ),
              onPressed: () => _open(context, const SeasonScreen()),
            ),
            TextButton.icon(
              key: const ValueKey('arena-achievements'),
              icon: const Icon(Icons.emoji_events_outlined),
              label: Text(
                english ? 'Achievements' : 'Başarımlar',
                localize: false,
              ),
              onPressed: () => _open(context, const AchievementsScreen()),
            ),
          ],
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).push(lunoRoute(page));
  }
}

class ArenaPromotionHeading extends StatelessWidget {
  final String label;
  const ArenaPromotionHeading({super.key, required this.label});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const style = TextStyle(
        color: Colors.white,
        fontFamily: 'Cinzel',
        fontSize: 25,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      );
      final inheritedStyle = DefaultTextStyle.of(context).style.merge(style);
      final words = label.split(RegExp(r'\s+'));
      double longestWord(double fontSize) {
        var longest = 0.0;
        for (final word in words) {
          final painter = TextPainter(
            text: TextSpan(
              text: word,
              style: inheritedStyle.copyWith(fontSize: fontSize),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout();
          if (painter.width > longest) longest = painter.width;
          painter.dispose();
        }
        return longest;
      }
      // Wrap first; resize only a word that cannot fit even on its own line.
      var fontSize = 25.0;
      final available = (box.maxWidth - 6).clamp(0.0, double.infinity);
      if (longestWord(fontSize) > available) {
        var lower = 0.0;
        var upper = fontSize;
        // Measure each candidate so nonlinear accessibility scaling also fits.
        for (var i = 0; i < 16; i++) {
          final candidate = (lower + upper) / 2;
          if (longestWord(candidate) <= available) {
            lower = candidate;
          } else {
            upper = candidate;
          }
        }
        fontSize = lower;
      }
      return Text(
        label,
        localize: false,
        textAlign: TextAlign.center,
        style: inheritedStyle.copyWith(fontSize: fontSize),
      );
    },
  );
}

class _BenefitLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final int gold;
  final int gems;

  const _BenefitLine({
    required this.icon,
    required this.label,
    required this.gold,
    required this.gems,
  });

  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    final rewards = [
      if (gold > 0) '${formatTrophies(gold)} ${english ? 'gold' : 'altın'}',
      if (gems > 0) '$gems ${english ? 'gems' : 'elmas'}',
    ].join(' + ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: LunoColors.gold),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, localize: false, style: LunoType.bodyMuted),
              const SizedBox(height: 3),
              Text(
                rewards,
                localize: false,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: LunoColors.ivory,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
