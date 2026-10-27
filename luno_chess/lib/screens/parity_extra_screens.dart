import 'package:flutter/material.dart' hide Text;

import '../data/rank_catalog.dart';
import '../data/arena_progression_preview.dart';
import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../models/profile_match_stats.dart';
import '../data/username.dart';
import '../services/ugc_text_safety.dart';
import '../navigation/luno_account_scope.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/currency_bar.dart';
import '../widgets/luno_surface.dart';
import '../widgets/resource_amount.dart';
import '../navigation/luno_route.dart';
import '../widgets/luno_polish.dart';
import '../widgets/arena_progression_benefits.dart';
import 'battle_deck_screen.dart';

/// HTML sürümünde overlay olarak çalışan, Flutter'a ayrı bir ekran gibi
/// taşınan içerikler. Ortak metin/asset sözleşmesi burada tutulur.
class ArenasScreen extends StatelessWidget {
  const ArenasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameStore.instance,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final store = GameStore.instance;
    final current = arenaIndexForPlayer(store.rankTrophies, store.rankArenaIdx);
    return Scaffold(
      appBar: AppBar(title: const Text('ARENALAR')),
      body: LunoBackdrop(
        art: LunoAssets.arenaRoad,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, -.08),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: CurrencyBar(),
              ),
              const SizedBox(height: 12),
              _ArenaHero(current: current, trophies: store.rankTrophies),
              const SizedBox(height: 12),
              LunoEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      LunoLocalizations.of(context).isEnglish
                          ? 'Cards unlock separately in every arena.'
                          : 'Kartlar her arenada, ayrı koşullarla açılır.',
                      localize: false,
                      style: LunoType.bodyMuted,
                    ),
                    const SizedBox(height: 10),
                    LunoButton(
                      key: const ValueKey('arena-card-library'),
                      label: LunoLocalizations.of(context).isEnglish ? 'CARD PROGRESS' : 'KART İLERLEMESİ',
                      icon: Icons.style_rounded,
                      onPressed: () {
                        if (ModalRoute.of(context)?.isCurrent != true) return;
                        Navigator.of(context).push(lunoRoute(const BattleDeckScreen(catalogOnly: true)));
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 28),
              ArenaProgressionBenefits(arenaIndex: current),
              const SizedBox(height: 16),
              const Text(
                'ARENA YOLU',
                style: TextStyle(
                  color: LunoColors.gold,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 9),
              for (var i = 0; i < kArenaCatalog.length; i++)
                _ArenaRow(item: kArenaCatalog[i], index: i, current: current),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArenaHero extends StatelessWidget {
  final int current;
  final int trophies;
  const _ArenaHero({required this.current, required this.trophies});

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final next = current + 1 < kArenaCatalog.length ? kArenaCatalog[current + 1] : null;
    final art = SizedBox(
      width: 64,
      height: 72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LunoArt(LunoAssets.arena(current), fit: BoxFit.cover),
      ),
    );
    final heading = Text(
      l.isEnglish ? 'CURRENT ARENA' : 'MEVCUT ARENA',
      localize: false,
      style: const TextStyle(
        color: LunoColors.textDim,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
    final titleLabel =
        '${l.translate(arenaForIndex(current).displayName)} · ARENA ${current + 1}';
    const titleStyle = TextStyle(
      color: LunoColors.gold,
      fontWeight: FontWeight.w700,
      fontSize: 18,
    );
    final title = Text(
      titleLabel,
      localize: false,
      style: titleStyle,
    );
    final score = Row(
      children: [
        const LunoArt(LunoAssets.trophy, width: 28, height: 28),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            l.isEnglish ? '${formatTrophies(trophies)} trophies' : '${formatTrophies(trophies)} kupa',
            localize: false,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final titlePainter = TextPainter(
          text: TextSpan(
            text: titleLabel,
            style: DefaultTextStyle.of(context).style.merge(titleStyle),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        const surfaceInset = 14.0 + 1.0;
        final sideTextWidth = box.maxWidth - surfaceInset * 2 - 64 - 12;
        final stacked = titlePainter.width > sideTextWidth;
        titlePainter.dispose();
        return LunoSurface(
          padding: const EdgeInsets.all(14),
          color: LunoColors.bgPanel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              stacked
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          art,
                          const SizedBox(width: 12),
                          Expanded(child: heading),
                        ],
                      ),
                      const SizedBox(height: 8),
                      title,
                      const SizedBox(height: 5),
                      score,
                    ],
                  )
                  : Row(
                    children: [
                      art,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading,
                            const SizedBox(height: 4),
                            title,
                            const SizedBox(height: 5),
                            score,
                          ],
                        ),
                      ),
                    ],
                  ),
              const SizedBox(height: 14),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: arenaProgress(trophies, current)),
                duration: LunoMotion.adaptive(context, const Duration(milliseconds: 420)),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  color: LunoColors.gold,
                  backgroundColor: LunoColors.bgRaised,
                  semanticsLabel: l.isEnglish ? 'Arena progress' : 'Arena ilerlemesi',
                  semanticsValue: '${(value * 100).round()}%',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                next == null
                    ? 'Arena 9 / 9'
                    : '${arenaProgressLabel(trophies, current)} · ${(arenaProgress(trophies, current) * 100).round()}%',
                key: const ValueKey('arena-progress-value'),
                localize: false,
                style: LunoType.bodyMuted,
              ),
              if (next != null) ...[
                const SizedBox(height: 6),
                Text(
                  l.isEnglish
                      ? 'NEXT TARGET · ${formatTrophies(next.minTrophies)} trophies'
                      : 'SONRAKİ HEDEF · ${formatTrophies(next.minTrophies)} kupa',
                  localize: false,
                  style: const TextStyle(color: LunoColors.gold, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                next == null
                    ? (l.isEnglish ? 'Highest arena reached' : 'En yüksek arenadasın')
                    : (l.isEnglish
                        ? '${formatTrophies((next.minTrophies - trophies).clamp(0, next.minTrophies))} trophies to ${l.translate(next.name)}'
                        : '${l.translate(next.name)} için ${formatTrophies((next.minTrophies - trophies).clamp(0, next.minTrophies))} kupa kaldı'),
                key: const ValueKey('arena-next-threshold'),
                localize: false,
                style: LunoType.bodyMuted.copyWith(fontSize: 13, color: LunoColors.ivory),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArenaRow extends StatelessWidget {
  final ArenaDefinition item;
  final int index;
  final int current;
  const _ArenaRow({
    required this.item,
    required this.index,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = index <= current;
    final active = index == current;
    final l = LunoLocalizations.of(context);
    final english = l.isEnglish;
    final path = arenaPathPreview(index);
    final achievement = arenaAchievementPreview(index);
    final art = SizedBox(
      width: 72,
      height: 96,
      child: Opacity(
        opacity: unlocked ? 1 : .7,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LunoArt('assets/native_art/${item.asset}', fit: BoxFit.cover),
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          english && item.name == 'Luno Kraliyeti' ? 'Luno Royalty' : l.translate(item.name),
          localize: false,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(item.rangeLabel, style: const TextStyle(color: LunoColors.textDim, fontSize: 13)),
        const SizedBox(height: 6),
        Text(
          english ? 'ARENA ${index + 1} · Season path' : 'ARENA ${index + 1} · Sezon yolu',
          localize: false,
          style: const TextStyle(color: LunoColors.gold, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          [
            if (path.gold > 0) '${formatTrophies(path.gold)} ${english ? 'gold' : 'altın'}',
            if (path.gems > 0) '${path.gems} ${english ? 'gems' : 'elmas'}',
          ].join(' + '),
          localize: false,
          style: const TextStyle(fontSize: 13),
        ),
        if (achievement != null) ...[
          const SizedBox(height: 4),
          Text(
            english ? 'Achievement milestone' : 'Başarım hedefi',
            localize: false,
            style: const TextStyle(color: LunoColors.textDim, fontSize: 12),
          ),
        ],
        if (active) ...[
          const SizedBox(height: 6),
          const Text('ŞU AN BURADASIN', style: TextStyle(color: LunoColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0)),
        ],
      ],
    );
    final status = Semantics(
      label: active
          ? (english ? 'Current arena' : 'Şu an buradasın')
          : unlocked ? (english ? 'Unlocked' : 'Açık') : (english ? 'Locked' : 'Kilitli'),
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 44,
          height: 44,
          child: AnimatedSwitcher(
            duration: LunoMotion.adaptive(context, const Duration(milliseconds: 180)),
            child: ClipRRect(
              key: ValueKey(unlocked),
              borderRadius: BorderRadius.circular(8),
              child: LunoArt(
                unlocked ? 'assets/native_art/arena-unlocked-v41.png' : 'assets/native_art/arena-lock-v41.png',
                width: 44,
                height: 44,
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      key: ValueKey('arena-row-$index'),
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: active ? LunoColors.bgRaised : LunoColors.bgPanel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? LunoColors.gold : LunoColors.bgPanel2,
          width: active ? 2 : 1,
        ),
        boxShadow:
            active
                ? const [BoxShadow(color: Color(0x44FFD860), blurRadius: 12)]
                : null,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final stacked = box.maxWidth < 340 || MediaQuery.textScalerOf(context).scale(15) > 22.5;
          return stacked
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [art, const Spacer(), status]),
                  const SizedBox(height: 9),
                  details,
                ],
              )
              : Row(children: [art, const SizedBox(width: 11), Expanded(child: details), const SizedBox(width: 6), status]);
        },
      ),
    );
  }
}

class LevelRewardsScreen extends StatelessWidget
    implements LunoAccountScopedPage {
  const LevelRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: GameStore.instance,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final data = GameStore.instance.data;
    final level = data.lvl < 1 ? 1 : data.lvl;
    return Scaffold(
      appBar: AppBar(title: const Text('SEVİYE ÖDÜLLERİ')),
      body: LunoBackdrop(
        art: 'assets/native_art/level-gallery-v47.png',
        overlay: const Color(0x3313262C),
        focalPoint: const Alignment(0, -.12),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Column(
                children: [
                  SizedBox(
                    width: 112,
                    height: 92,
                    child: LunoArt(
                      level > 50 ? LunoAssets.trophy : LunoAssets.level(level),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Şu an Seviye $level',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF4F0E3),
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LunoSurface(
                color: LunoColors.bgRaised,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BİR SONRAKİ SEVİYE',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 66,
                          height: 62,
                          child: LunoArt(
                            level >= 50
                                ? LunoAssets.trophy
                                : LunoAssets.level(level + 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Seviye ${level + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const LunoArt(
                                    LunoAssets.coin,
                                    width: 42,
                                    height: 42,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '+${100 + (level + 1) * 20} altın',
                                      maxLines: 3,
                                      style: const TextStyle(
                                        color: LunoColors.gold,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LunoSurface(
                color: LunoColors.bgPanel2,
                borderRadius: BorderRadius.circular(8),
                child: const Text(
                  'Maç oynadıkça XP kazanırsın. Seviye 10 ve 25 gibi dönüm noktalarında başarımlardan ek ödüller açılır.',
                  style: TextStyle(
                    color: Color(0xFFE3EAE5),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LunoButton(
                backgroundArt: LunoAssets.actionSurfaceV27,
                onPressed: () {
                  if (!context.mounted ||
                      ModalRoute.of(context)?.isCurrent != true) {
                    return;
                  }
                  Navigator.of(context).maybePop();
                },
                leading: const SizedBox(
                  width: 28,
                  height: 28,
                  child: LunoArt('assets/native_art/arena-unlocked-v41.png'),
                ),
                label: 'ANLADIM',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ArenaPromotionScreen extends StatelessWidget {
  final String arenaName;
  final String arenaArt;
  final List<String> unlockedCards;

  const ArenaPromotionScreen({
    super.key,
    required this.arenaName,
    required this.arenaArt,
    this.unlockedCards = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    ArenaDefinition? promotedArena;
    for (final arena in kArenaCatalog) {
      if (arena.name.toLowerCase() == arenaName.toLowerCase() ||
          arena.displayName.toLowerCase() == arenaName.toLowerCase() ||
          arenaArt.endsWith('/${arena.asset}')) {
        promotedArena = arena;
        break;
      }
    }
    final promoted = promotedArena;
    final next = promoted != null && promoted.index + 1 < kArenaCatalog.length
        ? kArenaCatalog[promoted.index + 1]
        : null;
    return Scaffold(
      body: LunoBackdrop(
        art: LunoAssets.arenaRoad,
        overlay: const Color(0xD9100A24),
        focalPoint: const Alignment(0, -.18),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Text(
                    'YENİ ARENA',
                    style: TextStyle(
                      color: LunoColors.gold,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ArenaPromotionHeading(
                    label: l.translate(promoted?.displayName ?? arenaName).toUpperCase(),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: AspectRatio(aspectRatio: 270 / 172, child: LunoArt(arenaArt)),
                  ),
                  if (promoted != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'ARENA ${promoted.index + 1} / ${kArenaCatalog.length} · ${formatTrophies(promoted.minTrophies)} ${l.isEnglish ? 'trophies' : 'kupa'}',
                      localize: false,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: LunoColors.gold, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      next == null
                          ? (l.isEnglish ? 'Highest arena reached' : 'En yüksek arenadasın')
                          : (l.isEnglish
                              ? 'Next arena: ${l.translate(next.name)} · ${formatTrophies(next.minTrophies)} trophies'
                              : 'Sonraki arena: ${l.translate(next.name)} · ${formatTrophies(next.minTrophies)} kupa'),
                      localize: false,
                      textAlign: TextAlign.center,
                      style: LunoType.bodyMuted,
                    ),
                    const Divider(height: 28),
                    ArenaProgressionBenefits(arenaIndex: promoted.index),
                  ],
                  const SizedBox(height: 16),
                  if (unlockedCards.isNotEmpty)
                    LunoSurface(
                      child: Column(
                        children: [
                          const Text(
                            'YENİ KARTLAR AÇILDI',
                            style: TextStyle(
                              color: LunoColors.success,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final card in unlockedCards)
                                SizedBox(
                                  width: 58,
                                  height: 72,
                                  child: LunoArt(LunoAssets.card(card, 1)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('DEVAM ET'),
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
}

class SeasonEndRewardScreen extends StatelessWidget {
  final String tier;
  final int gold;
  final int gems;
  const SeasonEndRewardScreen({
    super.key,
    required this.tier,
    required this.gold,
    required this.gems,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LunoBackdrop(
        art: LunoAssets.phase2ResultVictory,
        overlay: const Color(0xD9100A24),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Center(
              child: LunoSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LunoArt(
                      LunoAssets.resultVictory,
                      width: 190,
                      height: 150,
                    ),
                    const Text(
                      'SEZON SONU ÖDÜLÜ',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tier,
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ResourceAmount.coin(gold),
                        const SizedBox(width: 14),
                        ResourceAmount.gem(gems),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Yeni sezonda kupalarını yeniden yükseltmeye hazırsın.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: LunoColors.textDim, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('ÖDÜLÜ AL'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerDetailsScreen extends StatelessWidget
    implements LunoAccountScopedPage {
  final String name;
  final int trophies;
  final int wins;
  final int games;
  final String country;
  final String bio;
  final String avatarArt;
  final bool premium;
  final VoidCallback? onRefresh;
  final Widget? safetyAction;

  const PlayerDetailsScreen({
    super.key,
    required this.name,
    required this.trophies,
    required this.wins,
    required this.games,
    required this.country,
    this.bio = '',
    this.avatarArt = LunoAssets.profileCrest,
    this.premium = false,
    this.onRefresh,
    this.safetyAction,
  });

  factory PlayerDetailsScreen.fromPlayer(
    Map<String, dynamic> player, {
    VoidCallback? onRefresh,
    Widget? safetyAction,
  }) {
    int number(Object? value) {
      if (value is num && !value.isFinite) return 0;
      final result = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      return result < 0 ? 0 : result;
    }

    final rawCountry = player['country'];
    final country = rawCountry is String ? rawCountry.trim().toUpperCase() : '';
    return PlayerDetailsScreen(
      name: usernameFromMap(player),
      trophies: number(player['trophies']),
      wins: number(player['wins']),
      games: number(player['gamesPlayed']),
      country: RegExp(r'^[A-Z]{2}$').hasMatch(country) ? country : 'TR',
      bio: safePublicBio(player['bio']),
      avatarArt: LunoAssets.avatar(
        player['avatarEmoji']?.toString() ?? 'av_pawn',
      ),
      premium: player['isPremium'] == true || player['premium'] == true,
      onRefresh: onRefresh,
      safetyAction: safetyAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = ProfileMatchStats(wins: wins, games: games);
    final safeWins = stats.wins;
    final rate = stats.winRate;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OYUNCU PROFİLİ'),
        actions: [
          if (safetyAction != null) safetyAction!,
          if (onRefresh != null)
            IconButton(
              tooltip: LunoLocalizations.of(context).translate('Yenile'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.profileSceneV29,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, -.2),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LunoSurface(
                color: LunoColors.bgPanel,
                child: Column(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: LunoColors.bgRaised,
                        border: Border.all(
                          color: LunoColors.goldDeep,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(child: LunoArt(avatarArt)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      localize: false,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF183A48),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0x6685DCD0)),
                          ),
                          child: Text(
                            country.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF9DE8DD),
                              fontFamily: 'Nunito',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${LunoAssets.countryName(country)}  ·  ${premium ? 'LUNO PREMIUM' : 'LUNO CLUB'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: LunoColors.textDim,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth < 350 ||
                              MediaQuery.textScalerOf(context).scale(14) > 19
                          ? 2
                          : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final stat in [
                        _PublicStat(
                          LunoAssets.profileTrophy,
                          '${trophies < 0 ? 0 : trophies}',
                          'KUPA',
                        ),
                        _PublicStat(
                          LunoAssets.profileWins,
                          '$safeWins',
                          'GALİBİYET',
                        ),
                        _PublicStat(LunoAssets.profileRate, '$rate%', 'ORAN'),
                      ])
                        SizedBox(width: width, child: stat),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              LunoSurface(
                color: LunoColors.bgPanel2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HAKKINDA',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bio.trim().isNotEmpty
                          ? bio.trim()
                          : '$name Luno Chess arenasında mücadele ediyor.',
                      localize: bio.trim().isEmpty,
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicStat extends StatelessWidget {
  final String art;
  final String value;
  final String label;
  const _PublicStat(this.art, this.value, this.label);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 3),
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: LunoColors.bgPanel,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: LunoColors.bgPanel2),
    ),
    child: Column(
      children: [
        LunoArt(art, width: 44, height: 44),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LunoColors.gold,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: LunoColors.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class MatchInviteDialog {
  const MatchInviteDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required String fromName,
    String fromAvatar = LunoAssets.profileCrest,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: LunoColors.bgPanel,
            title: const Text('MAÇ TEKLİFİ'),
            content: Row(
              children: [
                SizedBox(width: 54, height: 54, child: LunoArt(fromAvatar)),
                const SizedBox(width: 12),
                Expanded(child: Text('$fromName seninle oynamak istiyor.')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('REDDET'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('KABUL ET'),
              ),
            ],
          ),
    );
  }
}

class PurchaseConfirmationDialog {
  const PurchaseConfirmationDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String price,
    required String description,
    String art = LunoAssets.shop,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: LunoColors.bgPanel,
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 120, height: 92, child: LunoArt(art)),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LunoColors.textDim),
                ),
                const SizedBox(height: 10),
                Text(
                  price,
                  style: const TextStyle(
                    color: LunoColors.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('VAZGEÇ'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ONAYLA'),
              ),
            ],
          ),
    );
  }
}
