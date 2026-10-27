// Frozen V216 arena-only baseline for new V216.1 before renders.
// Do not update this fixture to mirror the repaired production widgets.
import 'package:flutter/material.dart' hide Text;
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/i18n/luno_text.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/currency_bar.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/luno_polish.dart';
import 'package:luno_chess/navigation/luno_route.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';

class V216ArenaBeforeScreen extends StatelessWidget {
  const V216ArenaBeforeScreen({super.key});

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
                      label:
                          LunoLocalizations.of(context).isEnglish
                              ? 'CARD PROGRESS'
                              : 'KART İLERLEMESİ',
                      icon: Icons.style_rounded,
                      onPressed: () {
                        if (ModalRoute.of(context)?.isCurrent != true) return;
                        Navigator.of(context).push(
                          lunoRoute(const BattleDeckScreen(catalogOnly: true)),
                        );
                      },
                    ),
                  ],
                ),
              ),
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
    final next =
        current + 1 < kArenaCatalog.length ? kArenaCatalog[current + 1] : null;
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
    final title = Text(titleLabel, localize: false, style: titleStyle);
    final score = Row(
      children: [
        const LunoArt(LunoAssets.trophy, width: 28, height: 28),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            l.isEnglish
                ? '${formatTrophies(trophies)} trophies'
                : '${formatTrophies(trophies)} kupa',
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
                duration: LunoMotion.adaptive(
                  context,
                  const Duration(milliseconds: 420),
                ),
                curve: Curves.easeOutCubic,
                builder:
                    (_, value, _) => LinearProgressIndicator(
                      value: value,
                      color: LunoColors.gold,
                      backgroundColor: LunoColors.bgRaised,
                      semanticsLabel:
                          l.isEnglish ? 'Arena progress' : 'Arena ilerlemesi',
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                next == null
                    ? (l.isEnglish
                        ? 'Highest arena reached'
                        : 'En yüksek arenadasın')
                    : (l.isEnglish
                        ? '${formatTrophies((next.minTrophies - trophies).clamp(0, next.minTrophies))} trophies to ${l.translate(next.name)}'
                        : '${l.translate(next.name)} için ${formatTrophies((next.minTrophies - trophies).clamp(0, next.minTrophies))} kupa kaldı'),
                key: const ValueKey('arena-next-threshold'),
                localize: false,
                style: LunoType.bodyMuted.copyWith(
                  fontSize: 13,
                  color: LunoColors.ivory,
                ),
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
    final english = LunoLocalizations.of(context).isEnglish;
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
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 96,
            child: Opacity(
              opacity: unlocked ? 1 : .7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LunoArt(
                  'assets/native_art/${item.asset}',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.rangeLabel,
                  style: const TextStyle(
                    color: LunoColors.textDim,
                    fontSize: 13,
                  ),
                ),
                if (active) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'ŞU AN BURADASIN',
                    style: TextStyle(
                      color: LunoColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label:
                active
                    ? (english ? 'Current arena' : 'Şu an buradasın')
                    : unlocked
                    ? (english ? 'Unlocked' : 'Açık')
                    : (english ? 'Locked' : 'Kilitli'),
            image: true,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 44,
                height: 44,
                child: AnimatedSwitcher(
                  duration: LunoMotion.adaptive(
                    context,
                    const Duration(milliseconds: 180),
                  ),
                  child: ClipRRect(
                    key: ValueKey(unlocked),
                    borderRadius: BorderRadius.circular(8),
                    child: LunoArt(
                      unlocked
                          ? 'assets/native_art/arena-unlocked-v41.png'
                          : 'assets/native_art/arena-lock-v41.png',
                      width: 44,
                      height: 44,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class V216ArenaPromotionBeforeScreen extends StatelessWidget {
  final String arenaName;
  final String arenaArt;
  final List<String> unlockedCards;

  const V216ArenaPromotionBeforeScreen({
    super.key,
    required this.arenaName,
    required this.arenaArt,
    this.unlockedCards = const [],
  });

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    arenaName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cinzel',
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: 270, height: 172, child: LunoArt(arenaArt)),
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
