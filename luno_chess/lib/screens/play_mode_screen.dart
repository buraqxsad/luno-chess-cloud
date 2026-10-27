import 'dart:async';
import 'package:flutter/material.dart' hide Text;

import '../battle_v1/model.dart';
import '../battle_ui/cards.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../data/rank_catalog.dart';
import '../engine/ai.dart';
import '../i18n/luno_text.dart';
import '../models/game_store.dart';
import '../navigation/luno_route.dart';
import '../navigation/luno_account_scope.dart';
import '../services/luno_feedback.dart';
import '../services/luno_online_service.dart';
import '../services/account_operation_guard.dart';
import '../services/first_session_telemetry.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../theme/luno_visual_assets.dart';
import '../widgets/luno_polish.dart';
import '../widgets/battle_deck_mana.dart';
import 'battle_deck_screen.dart';
import 'difficulty_screen.dart';
import 'friendly_online_screen.dart';
import '../widgets/game_time_control_picker.dart';
import 'battle_v1_screen.dart';
import 'online_hub_screen.dart';
import 'parity_extra_screens.dart';

/// Build 12 savas secim ekrani: arena, aktif deste ve dort oyun modu ayni
/// dikey akista tutulur; arka plan da ekranin kendi arena sanatidir.
class PlayModeScreen extends StatelessWidget implements LunoAccountScopedPage {
  final LunoOnlineService? online;
  final GameStore? playerStore;
  const PlayModeScreen({super.key, this.online, this.playerStore});

  static void _open(BuildContext context, Widget page) {
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final store = GameStore.instance;
    if (store.firstSessionMatchesStarted == 0 &&
        (page is DifficultyScreen || page is OnlineHubScreen)) {
      FirstSessionTelemetry.forStore(store).record(
        FirstSessionEvent.firstMatchCtaPressed,
        store.accountBindingRevision,
        mode:
            page is DifficultyScreen
                ? SessionMatchMode.ai
                : SessionMatchMode.online,
      );
    }
    Navigator.of(context).push(lunoRoute(page));
  }

  @override
  Widget build(BuildContext context) {
    final store = playerStore ?? GameStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final arena = arenaForIndex(
          arenaIndexForPlayer(store.rankTrophies, store.rankArenaIdx),
        );
        return Scaffold(
          backgroundColor: LunoColors.bgDeep,
          body: Stack(
            fit: StackFit.expand,
            children: [
              LunoArt(
                LunoAssets.lobbySceneV29,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              const ColoredBox(color: Color(0x450B081C)),
              SafeArea(
                bottom: true,
                child: Column(
                  children: [
                    _Header(
                      onBack: () {
                        if (context.mounted &&
                            ModalRoute.of(context)?.isCurrent == true) {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                        children: [
                          _ArenaCard(
                            trophies: store.rankTrophies,
                            arenaIdx: store.rankArenaIdx,
                            onTap: () => _open(context, const ArenasScreen()),
                          ),
                          const SizedBox(height: 8),
                          _DeckCard(
                            online: online ?? LunoOnlineService.instance,
                            store: store,
                          ),
                          const SizedBox(height: 12),
                          const _ModeHeading(),
                          const SizedBox(height: 6),
                          _ModeTile(
                            art: LunoAssets.modeRanked,
                            title: 'SIRALI MAÇ',
                            subtitle:
                                'Kupa kazan, arenalarda yüksel ve sıralamada yerini al.',
                            badge:
                                '+${arena.winTrophies} / -${arena.lossTrophies} · 5+2',
                            color: const Color(0xFFB98377),
                            onTap:
                                () => _open(context, const OnlineHubScreen()),
                          ),
                          _ModeTile(
                            art: LunoAssets.modeAi,
                            title: 'YAPAY ZEKÂYA KARŞI',
                            subtitle:
                                'Altı Luno eğitmeninden birini seç, risksiz antrenman yap.',
                            badge: 'ANTRENMAN · KUPASIZ',
                            color: const Color(0xFF657C9F),
                            onTap:
                                () => _open(context, const DifficultyScreen()),
                          ),
                          _ModeTile(
                            art: LunoAssets.modeFriend,
                            title: 'ARKADAŞINLA OYNA',
                            subtitle:
                                'Arkadaşını davet et ya da oda koduyla maça katıl.',
                            badge: 'ONLINE · DAVET',
                            color: const Color(0xFF4B876E),
                            onTap:
                                () => _open(
                                  context,
                                  const FriendlyOnlineScreen(),
                                ),
                          ),
                          _ModeTile(
                            art: 'assets/native_art/mode-local-v39.png',
                            title: 'YÜZ YÜZE OYNA',
                            subtitle: LunoLocalizations.of(context).learning(
                              'Aynı cihazda sırayla oyna. İki taraf da başlangıç destesini kullanır.',
                              'Take turns on the same device. Both players use the starter deck.',
                            ),
                            badge: 'YEREL · KUPASIZ',
                            color: const Color(0xFF9A704F),
                            onTap: () async {
                              final revision = store.accountBindingRevision;
                              final minutes = await showGameTimeControlPicker(
                                context,
                              );
                              if (!context.mounted ||
                                  minutes == null ||
                                  revision != store.accountBindingRevision ||
                                  ModalRoute.of(context)?.isCurrent != true) {
                                return;
                              }
                              if (store.firstSessionMatchesStarted == 0) {
                                FirstSessionTelemetry.forStore(store).record(
                                  FirstSessionEvent.firstMatchCtaPressed,
                                  revision,
                                  mode: SessionMatchMode.local,
                                );
                              }
                              Navigator.of(context).push(
                                lunoRoute(
                                  BattleV1Screen(
                                    level: aiLevels.first,
                                    local: true,
                                    timeControlMinutes: minutes,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          IconButton(
            tooltip: LunoLocalizations.of(context).translate('Geri'),
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 32),
            color: Colors.white,
          ),
          const Expanded(
            child: Center(
              child: Text(
                'SAVAŞ',
                style: TextStyle(
                  color: LunoColors.gold,
                  fontFamily: 'Cinzel',
                  fontFamilyFallback: ['CinzelTurkish'],
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ArenaCard extends StatelessWidget {
  final int trophies;
  final int arenaIdx;
  final VoidCallback? onTap;
  const _ArenaCard({
    required this.trophies,
    required this.arenaIdx,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final current = trophies;
    final arena = arenaIndexForPlayer(current, arenaIdx);
    final definition = arenaForIndex(arena);
    final ratio = arenaProgress(current, arena);
    final largeNarrow =
        MediaQuery.sizeOf(context).width <= 360 &&
        MediaQuery.textScalerOf(context).scale(16) > 19.2;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 108),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xDD3B2B30), Color(0xE6253443)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x997F9A84)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 9,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: largeNarrow ? 60 : 82,
                height: largeNarrow ? 64 : 86,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LunoArt(LunoAssets.arena(arena), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'MEVCUT ARENA',
                      style: TextStyle(
                        color: Color(0xFF7FE0D1),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      definition.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 7,
                            value: ratio,
                            backgroundColor: const Color(0xFF111626),
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF52D2BF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          arenaProgressLabel(current, arena),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: LunoColors.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: LunoColors.gold,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckCard extends StatefulWidget {
  final LunoOnlineService online;
  final GameStore store;
  const _DeckCard({required this.online, required this.store});

  @override
  State<_DeckCard> createState() => _DeckCardState();
}

class _DeckCardState extends State<_DeckCard> {
  bool loading = false, failed = false;
  int generation = 0;
  late final int ownerRevision;
  final closed = Completer<void>();
  bool get ownsAccount => ownerRevision == widget.store.accountBindingRevision;

  @override
  void initState() {
    super.initState();
    ownerRevision = widget.store.accountBindingRevision;
    widget.online.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _changed() {
    if (mounted && ownsAccount) setState(() {});
  }

  @override
  void dispose() {
    generation++;
    widget.online.removeListener(_changed);
    closed.complete();
    super.dispose();
  }

  Future<T> _deadline<T>(Future<T> operation) async {
    final expiry = Completer<T>();
    final timer = Timer(const Duration(seconds: 15), () {
      expiry.completeError(TimeoutException('Active deck unavailable'));
    });
    try {
      return await Future.any([
        operation,
        expiry.future,
        closed.future.then<T>((_) => throw StateError('Deck preview closed')),
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _load() async {
    if (!mounted ||
        !ownsAccount ||
        loading ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final request = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await _deadline(widget.online.start());
      if (!mounted || !ownsAccount || request != generation) return;
      if (!widget.online.ready || widget.online.user == null) {
        throw const LunoApiException('auth-required', 401);
      }
      final guard = AccountOperationGuard(widget.store, widget.online);
      await _deadline(widget.online.getBattleV1Deck());
      guard.check();
    } catch (_) {
      if (mounted && ownsAccount && request == generation) {
        setState(() => failed = true);
      }
    } finally {
      if (mounted && ownsAccount && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ownsAccount) return const SizedBox.shrink();
    final account = widget.online.cachedBattleDeck;
    final deck = account?.deck ?? starterDeck;
    final l = LunoLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
      decoration: BoxDecoration(
        color: LunoColors.bgPanel,
        image: lunoFace(LunoVisualAssets.collection, opacity: .7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x6677A8B2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.collections_bookmark_rounded,
                color: LunoColors.gold,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.learning(
                        account == null ? 'BAŞLANGIÇ DESTESİ' : 'AKTİF DESTEN',
                        account == null ? 'STARTER DECK' : 'ACTIVE DECK',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      l.learning(
                        '${deck.length} farklı kart',
                        '${deck.length} different cards',
                      ),
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (failed)
                IconButton(
                  key: const ValueKey('battle-deck-retry'),
                  tooltip: l.learning('Yeniden dene', 'Retry'),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: l.learning('Desteyi incele', 'View deck'),
                onPressed:
                    () => PlayModeScreen._open(
                      context,
                      LunoAccountScope(
                        service: widget.online,
                        page: BattleDeckScreen(online: widget.online),
                      ),
                    ),
                icon: const Icon(Icons.style_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              loading
                  ? l.learning('Desten yükleniyor...', 'Loading your deck...')
                  : failed
                  ? l.learning(
                    account == null
                        ? 'Deste yüklenemedi: Başlangıç destesi önizlemesi.'
                        : 'Deste yenilenemedi: Son doğrulanan desten kullanılır.',
                    account == null
                        ? 'Deck unavailable: Starter deck preview.'
                        : 'Refresh unavailable: Your last confirmed deck is used.',
                  )
                  : account?.available == false
                  ? l.learning(
                    'Çevrimiçi savaş kapalı; yapay zekâda bu deste kullanılabilir.',
                    'Online battle is unavailable; AI can use this deck.',
                  )
                  : l.learning(
                    account == null
                        ? 'Başlangıç destesi önizlemesi.'
                        : 'Yapay zekâ ve çevrimiçi maçlar için kayıtlı desten.',
                    account == null
                        ? 'Starter deck preview.'
                        : 'Your saved deck for AI and online matches.',
                  ),
              style: const TextStyle(fontSize: 12, color: LunoColors.textDim),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 84 + MediaQuery.textScalerOf(context).scale(12) * 3,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: deck.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder:
                  (context, index) => SizedBox(
                    width:
                        100 +
                        (MediaQuery.textScalerOf(context).scale(12) - 12) * 4,
                    child: _DeckSlot(
                      key: ValueKey('active-deck-${deck[index].wire}'),
                      card: deck[index],
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 12),
          BattleDeckMana(cards: deck),
        ],
      ),
    );
  }
}

class _DeckSlot extends StatelessWidget {
  final CardId card;
  const _DeckSlot({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xCC111827),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0x996F8D93)),
      ),
      child: Column(
        children: [
          Expanded(child: Center(child: BattleCardArt(card: card))),
          const SizedBox(height: 4),
          Text(
            l.battleCardName(card),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ModeHeading extends StatelessWidget {
  const _ModeHeading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'SAVAŞ MODLARI',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Cinzel',
              fontFamilyFallback: ['CinzelTurkish'],
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Flexible(
          child: Text(
            'Oyun tarzını seç',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: LunoColors.textDim.withValues(alpha: .9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatefulWidget {
  final String art;
  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final VoidCallback onTap;

  const _ModeTile({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ModeTile> createState() => _ModeTileState();
}

class _ModeTileState extends State<_ModeTile> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: LunoMotion.adaptive(context, LunoMotion.press),
      curve: Curves.easeOutCubic,
      transformAlignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        pressed ? .985 : 1,
        pressed ? .985 : 1,
        1,
      ),
      constraints: const BoxConstraints(minHeight: 132),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xF01E2634),
            Color.alphaBlend(
              widget.color.withValues(alpha: .2),
              const Color(0xFF17242D),
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color.withValues(alpha: .72)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
            LunoFeedback.tap();
            widget.onTap();
          },
          onHighlightChanged: (value) {
            if (mounted && pressed != value) setState(() => pressed = value);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  height: 92,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LunoArt(widget.art, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          color: Color(0xFFD6D0DF),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xAA142D38),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xAA51C9B8)),
                        ),
                        child: Text(
                          widget.badge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF75E4D2),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: LunoColors.gold,
                  size: 27,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
