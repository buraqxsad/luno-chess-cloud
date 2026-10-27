import 'package:flutter/material.dart' hide Text;
import '../theme/luno_visual_assets.dart';
import '../widgets/luno_polish.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../data/card_pool.dart';
import '../data/rank_catalog.dart';
import '../data/season_clock.dart';
import '../data/username.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/luno_text.dart';
import '../models/app_settings.dart';
import '../models/game_store.dart';
import '../navigation/luno_route.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_account_modal.dart';
import '../services/luno_online_service.dart';
import '../services/initial_stream_timeout.dart';
import '../services/screen_request_timeouts.dart';
import '../services/account_operation_guard.dart';
import '../services/collection_selection_result.dart';
import '../services/leaderboard_result.dart';
import '../services/player_search_result.dart';
import 'public_player_profile_screen.dart';
import '../services/direct_message_read_key.dart';
import '../services/reward_claim_result.dart';
import '../services/profile_update_result.dart';
import '../services/ugc_consent.dart';
import '../services/ugc_text_safety.dart';
import '../services/luno_feedback.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/currency_bar.dart';
import '../widgets/luno_surface.dart';
import '../widgets/card_info.dart';
import '../widgets/resource_amount.dart';
import '../widgets/social_safety_actions.dart';
import '../widgets/google_account_restore.dart';
import 'blocked_players_screen.dart';
import '../services/product_privacy_settings.dart';
import '../services/legal_link_service.dart';
import 'legacy_parity_screens.dart';
import 'collection_screens.dart';
import 'battle_deck_screen.dart';
import 'battle_v1_screen.dart';

/// HTML'deki koleksiyon hub'ının native karşılığı. Her içerik kendi ekranına
/// açılır; böylece deste, kart, taş ve emoji akışları birbirine karışmaz.
class CollectionScreen extends StatelessWidget {
  @visibleForTesting
  final Future<Map<String, dynamic>> Function()? deckLoadOverride;

  const CollectionScreen({super.key, this.deckLoadOverride});

  @override
  Widget build(BuildContext context) {
    final compactHeader =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KOLEKSİYON'),
        actions: [
          if (!compactHeader)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Center(child: CurrencyBar()),
            ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.collectionSceneV28,
        overlay: const Color(0x3510141B),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (compactHeader)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: CurrencyBar(),
                ),
              ),
            LunoEntrance(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LUNO KOLEKSİYONU',
                    style: TextStyle(
                      color: LunoColors.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LunoLocalizations.of(context).isEnglish
                        ? '24 battle abilities'
                        : '24 savaş yeteneği',
                    localize: false,
                    style: LunoType.bodyMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CollectionEntry(
              art: LunoAssets.uiCollectionDeck,
              icon: Icons.style_rounded,
              title: 'DESTE',
              subtitle:
                  LunoLocalizations.of(context).isEnglish
                      ? 'View and edit your online battle deck.'
                      : 'Çevrimiçi savaş desteni gör ve düzenle.',
              color: const Color(0xFF5FE0C0),
              prominent: true,
              onTap:
                  () => Navigator.of(context).push(
                    lunoRoute(
                      LunoAccountScope(
                        page: BattleDeckScreen(loadOverride: deckLoadOverride),
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: 10),
            _CollectionEntry(
              art: LunoAssets.uiCollectionCards,
              icon: Icons.auto_awesome_rounded,
              title: 'KARTLAR',
              subtitle:
                  LunoLocalizations.of(context).isEnglish
                      ? 'Explore mana costs, targets and effects.'
                      : 'Mana maliyetlerini, hedefleri ve etkileri incele.',
              color: const Color(0xFFFFD860),
              onTap:
                  () => Navigator.of(context).push(
                    lunoRoute(
                      BattleDeckScreen(
                        catalogOnly: true,
                        loadOverride: deckLoadOverride,
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: 10),
            _CollectionEntry(
              art: LunoAssets.uiCollectionSkins,
              icon: Icons.grid_view_rounded,
              title: 'TAŞ KOSTÜMLERİ',
              subtitle: 'Tahtadaki taş setini seç ve önizle.',
              color: const Color(0xFFF0BB8F),
              onTap:
                  () => Navigator.of(
                    context,
                  ).push(lunoRoute(const PieceCostumeScreen())),
            ),
            const SizedBox(height: 10),
            _CollectionEntry(
              art: LunoAssets.uiCollectionEmoji,
              icon: Icons.chat_bubble_rounded,
              title: 'EMOJİLER',
              subtitle: 'Maç sohbetinde kullanacağın ifadeleri görüntüle.',
              color: const Color(0xFF7FD0FF),
              onTap:
                  () => Navigator.of(
                    context,
                  ).push(lunoRoute(const EmojiCollectionScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionEntry extends StatefulWidget {
  final String art;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool prominent;

  const _CollectionEntry({
    required this.art,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.prominent = false,
  });

  @override
  State<_CollectionEntry> createState() => _CollectionEntryState();
}

class _CollectionEntryState extends State<_CollectionEntry> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    final icon = widget.icon;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final color = widget.color;
    final compact =
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(15) > 18;
    return AnimatedScale(
      scale: _pressed && !MediaQuery.disableAnimationsOf(context) ? .985 : 1,
      duration: LunoMotion.adaptive(context, LunoMotion.press),
      curve: Curves.easeOutCubic,
      child: Material(
        color: widget.prominent ? LunoColors.bgRaised : LunoColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
            LunoFeedback.tap();
            widget.onTap();
          },
          onHighlightChanged: (value) {
            if (mounted) setState(() => _pressed = value);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                Container(
                  width:
                      compact
                          ? 52
                          : widget.prominent
                          ? 92
                          : 64,
                  height:
                      compact
                          ? 64
                          : widget.prominent
                          ? 86
                          : 64,
                  padding: const EdgeInsets.all(2),
                  child: LunoArt(art),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: LunoColors.textDim,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollectionBrowserScreen extends StatefulWidget {
  const CollectionBrowserScreen({super.key});

  @override
  State<CollectionBrowserScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionBrowserScreen> {
  int tab = 0;
  bool _savingPieceSet = false;

  Future<void> _selectPieceSet(String pieceSet) async {
    if (!mounted ||
        _savingPieceSet ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final store = GameStore.instance;
    if (!store.data.ownedPieceSets.contains(pieceSet)) return;
    final previous = store.data.pieceSet;
    final online = LunoOnlineService.instance;
    final guard = AccountOperationGuard(store, online);
    store.setPieceSet(pieceSet);
    if (!mounted) return;
    setState(() => _savingPieceSet = true);
    try {
      await online.start().timeout(const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.setPieceSet(pieceSet);
      final state = validatePieceSetResult(result, pieceSet);
      guard.check();
      if (store.data.pieceSet == pieceSet) {
        store.applyServerState(state);
      }
    } catch (_) {
      if (guard.isCurrent && store.data.pieceSet == pieceSet) {
        store.setPieceSet(previous);
      }
      if (guard.isCurrent &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taş seti sunucuya kaydedilemedi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPieceSet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = GameStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('KOLEKSİYON'),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 10),
                child: Center(child: CurrencyBar()),
              ),
            ],
          ),
          body: LunoBackdrop(
            art: LunoAssets.collection,
            overlay: const Color(0xE0100A24),
            child: Column(
              children: [
                _CollectionHeader(
                  score: store.collectionScore(),
                  owned: ownedPhysicalCardCount(
                    store.data.ownedCards,
                    store.data.cardLevel,
                  ),
                ),
                _Tabs(
                  labels: const ['KARTLAR', 'TAŞ KOSTÜMLERİ', 'EMOJİLER'],
                  selected: tab,
                  onChanged: (value) => setState(() => tab = value),
                ),
                Expanded(child: [_cards(), _sets(), _emojis()][tab]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cards() {
    final store = GameStore.instance;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: .72,
      ),
      itemCount: kAllOwnable.length,
      itemBuilder: (context, index) {
        final key = kAllOwnable[index];
        final owned = store.data.ownedCards.contains(key);
        final level = store.data.cardLevel[key] ?? 1;
        final def = cardForOwned(key, level);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap:
              owned
                  ? () => showCardInfo(context, resolvedKey(key, level))
                  : null,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: owned ? LunoColors.bgPanel : LunoColors.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    owned
                        ? LunoColors.gold.withValues(alpha: .65)
                        : LunoColors.bgPanel2,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: owned ? 1 : .22,
                    child: LunoArt(LunoAssets.card(key, level)),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  owned ? 'Sv$level · ${def.mana} mana' : 'KİLİTLİ',
                  style: TextStyle(
                    fontSize: 10,
                    color: owned ? LunoColors.gold : LunoColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sets() {
    const sets = <(String, String)>[
      ('ottoman', 'OTTOMAN SETİ'),
      ('roma', 'ROMA SETİ'),
      ('brit', 'BRİTANYA SETİ'),
      ('viking', 'VİKİNG SETİ'),
      ('tasdevri', 'TAŞ DEVRİ SETİ'),
      ('samuray', 'SAMURAY SETİ'),
      ('ice', 'BUZ KRALLIĞI'),
      ('dragon', 'EJDERHA SETİ'),
      ('neon', 'NEON KRALLIK'),
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: sets.length,
      itemBuilder: (context, index) {
        final item = sets[index];
        final selected = GameStore.instance.data.pieceSet == item.$1;
        final owned = GameStore.instance.data.ownedPieceSets.contains(item.$1);
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap:
              owned && !_savingPieceSet
                  ? () => unawaited(_selectPieceSet(item.$1))
                  : null,
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: selected ? LunoColors.goldDeep : LunoColors.bgPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? LunoColors.gold : LunoColors.bgPanel2,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(child: LunoArt(LunoAssets.setPreview(item.$1))),
                const SizedBox(height: 6),
                Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      !owned
                          ? Icons.lock_rounded
                          : selected
                          ? Icons.check_circle_rounded
                          : Icons.touch_app_rounded,
                      size: 13,
                      color: selected ? LunoColors.success : LunoColors.textDim,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      !owned
                          ? 'KİLİTLİ'
                          : selected
                          ? 'AKTİF'
                          : 'TAŞLARI GÖR',
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emojis() {
    return GridView.builder(
      padding: const EdgeInsets.all(18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: LunoAssets.emojiAssets.length,
      itemBuilder:
          (_, index) => Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: LunoColors.bgPanel,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: LunoColors.bgPanel2),
            ),
            child: LunoArt(LunoAssets.emojiAssets[index]),
          ),
    );
  }
}

class SeasonScreen extends StatefulWidget implements LunoAccountScopedPage {
  const SeasonScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  Map<String, dynamic> season = const {};
  bool loading = true;
  bool claiming = false;
  bool claimingEnd = false;
  String? error;
  Timer? _seasonTimer;
  final Stopwatch _seasonAge = Stopwatch();
  bool _loadingRequest = false;
  AccountOperationGuard? _loadedOwner;
  final _requestTimeouts = ScreenRequestTimeouts();
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (_loadingRequest || !mounted) return;
    if (claiming || claimingEnd) {
      _seasonTimer?.cancel();
      _seasonTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) unawaited(_load());
      });
      return;
    }
    final guard = AccountOperationGuard(store, online);
    _loadingRequest = true;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await _requestTimeouts.run(
        online.getPlayerState(),
        const Duration(seconds: 12),
      );
      guard.check();
      final rawState = result['state'];
      if (result['ok'] != true || rawState is! Map) {
        throw const LunoApiException('season-state-missing', 0);
      }
      final nextState = Map<String, dynamic>.from(rawState);
      final rawSeason = nextState['season'];
      if (rawSeason is! Map || rawSeason['path'] is! List) {
        throw const LunoApiException('season-state-missing', 0);
      }
      store.applyServerState(nextState);
      guard.check();
      if (!mounted) return;
      setState(() {
        season = Map<String, dynamic>.from(rawSeason);
        _loadedOwner = guard;
        _seasonAge
          ..reset()
          ..start();
        loading = false;
      });
      _scheduleSeasonRefresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        _loadedOwner = null;
        season = const {};
        error =
            guard.isCurrent
                ? 'Sezon bilgileri sunucudan yüklenemedi.'
                : 'Hesabın değişti. Sezon ekranını yeniden aç.';
      });
    } finally {
      _loadingRequest = false;
    }
  }

  int _number(Object? value) =>
      value is num ? value.toInt().clamp(0, 1000000000).toInt() : 0;

  String _remainingLabel() {
    final remaining = seasonRemainingMillis(
      season,
      elapsedMilliseconds: _seasonAge.elapsedMilliseconds,
    );
    if (remaining <= 0) return 'Sezon geçişi bekliyor';
    final days = remaining ~/ 86400000;
    final hours = (remaining % 86400000) ~/ 3600000;
    return days > 0 ? '$days gün $hours saat kaldı' : '$hours saat kaldı';
  }

  void _scheduleSeasonRefresh() {
    _seasonTimer?.cancel();
    if (season['status'] != 'active') return;
    final remaining = seasonRemainingMillis(
      season,
      elapsedMilliseconds: _seasonAge.elapsedMilliseconds,
    );
    final delay =
        remaining == 0
            ? 30000
            : (remaining + 1000).clamp(1000, 3600000).toInt();
    _seasonTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      if (seasonRemainingMillis(
            season,
            elapsedMilliseconds: _seasonAge.elapsedMilliseconds,
          ) ==
          0) {
        unawaited(_load());
      } else {
        setState(() {});
        _scheduleSeasonRefresh();
      }
    });
  }

  void _applyResult(Map<String, dynamic> result, AccountOperationGuard guard) {
    final rawState = result['state'];
    if (rawState is! Map) return;
    final nextState = Map<String, dynamic>.from(rawState);
    store.applyServerState(nextState);
    guard.check();
    final rawSeason = nextState['season'];
    if (mounted && rawSeason is Map) {
      setState(() {
        season = Map<String, dynamic>.from(rawSeason);
        _seasonAge
          ..reset()
          ..start();
      });
      _scheduleSeasonRefresh();
    }
  }

  String _actionError(Object error) {
    if (error is LunoApiException) {
      switch (error.code) {
        case 'season-tier-locked':
          return 'Bu ödül için daha fazla kupa kazanmalısın.';
        case 'season-reward-not-ready':
          return 'Sezon değişiminde önce sezon sonu ödülünü almalısın.';
        case 'app-check-required':
        case 'invalid-app-check':
          return 'Güvenli bağlantı doğrulanamadı.';
        case 'online-unavailable':
          return 'Sezon servisi şu an kullanılamıyor.';
      }
    }
    return 'İşlem doğrulanamadı. Bağlantı yenilendiğinde durumunu kontrol et.';
  }

  Future<void> _claimTier(String tierId) async {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        claiming ||
        claimingEnd ||
        loading ||
        _loadingRequest ||
        _loadedOwner?.isCurrent != true ||
        tierId.trim().isEmpty) {
      return;
    }
    final currentPath = season['path'];
    if (season['status'] != 'active' ||
        currentPath is! List ||
        !currentPath.any(
          (row) =>
              row is Map &&
              row['id'] == tierId &&
              row['canClaim'] == true &&
              row['state'] != 'claimed',
        )) {
      return;
    }
    setState(() => claiming = true);
    final guard = _loadedOwner!;
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      guard.check();
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.claimSeasonPathReward(tierId);
      guard.check();
      final granted = validateRewardClaimResult(result);
      _applyResult(result, guard);
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          granted
              ? 'Sezon yolu ödülü hesabına eklendi.'
              : 'Bu ödül daha önce alındı.',
        );
      }
    } catch (error) {
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_actionError(error))));
      }
    } finally {
      if (mounted) setState(() => claiming = false);
    }
  }

  Future<void> _claimEndReward() async {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        claiming ||
        claimingEnd ||
        loading ||
        _loadingRequest ||
        _loadedOwner?.isCurrent != true) {
      return;
    }
    if (season['status'] != 'ended' || season['endReward'] is! Map) return;
    setState(() => claimingEnd = true);
    final guard = _loadedOwner!;
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      guard.check();
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.claimSeasonReward();
      guard.check();
      final granted = validateRewardClaimResult(result);
      _applyResult(result, guard);
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          granted
              ? 'Sezon sonu ödülün hesabına eklendi.'
              : 'Bu ödül daha önce alındı.',
        );
      }
    } catch (error) {
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_actionError(error))));
      }
    } finally {
      if (mounted) setState(() => claimingEnd = false);
    }
  }

  @override
  void dispose() {
    _seasonTimer?.cancel();
    _requestTimeouts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compactHeader =
        MediaQuery.sizeOf(context).width < 560 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SEZON YOLU'),
        actions: [
          IconButton(
            onPressed: loading ? null : () => unawaited(_load()),
            tooltip: LunoLocalizations.of(context).translate('Yenile'),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (!compactHeader)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Center(child: CurrencyBar()),
            ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.seasonSceneV29,
        overlay: const Color(0x45100A24),
        focalPoint: const Alignment(0, -.12),
        child:
            loading
                ? const Center(
                  child: CircularProgressIndicator(color: LunoColors.gold),
                )
                : error != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Sezon yolu hazır değil.',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: LunoColors.textDim),
                        ),
                        const SizedBox(height: 16),
                        LunoButton(
                          label: 'YENİDEN DENE',
                          icon: Icons.refresh_rounded,
                          onPressed: () => unawaited(_load()),
                        ),
                      ],
                    ),
                  ),
                )
                : _seasonContent(compactHeader: compactHeader),
      ),
    );
  }

  Widget _seasonContent({required bool compactHeader}) {
    final path =
        season['path'] is List
            ? (season['path'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : const <Map<String, dynamic>>[];
    final score = _number(season['score']);
    final progress =
        season['progress'] is num
            ? (season['progress'] as num).toDouble().clamp(0, 1).toDouble()
            : 0.0;
    final ended = season['status'] == 'ended';
    final syncing = season['status'] == 'syncing';
    final endReward = season['endReward'];
    final endTier = endReward is Map ? endReward['tier']?.toString() ?? '' : '';
    final endValues =
        endReward is Map && endReward['reward'] is Map
            ? Map<String, dynamic>.from(endReward['reward'] as Map)
            : const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        if (compactHeader) ...[
          const Align(alignment: Alignment.centerRight, child: CurrencyBar()),
          const SizedBox(height: 12),
        ],
        _seasonHeader(score, progress, ended, syncing),
        const SizedBox(height: 14),
        if (ended) ...[
          LunoSurface(
            color: LunoColors.bgPanel,
            border: Border.all(color: LunoColors.gold, width: 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEZON SONU',
                  style: TextStyle(
                    color: LunoColors.gold,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$endTier ödülünü al ve yeni sezona geç.',
                  style: const TextStyle(color: LunoColors.textDim),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (_number(endValues['gold']) > 0)
                      ResourceAmount.coin(_number(endValues['gold'])),
                    if (_number(endValues['gems']) > 0)
                      ResourceAmount.gem(_number(endValues['gems'])),
                  ],
                ),
                const SizedBox(height: 12),
                LunoButton(
                  label: 'SEZON SONU ÖDÜLÜNÜ AL',
                  icon: Icons.redeem_rounded,
                  loading: claimingEnd,
                  onPressed: () => unawaited(_claimEndReward()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            const Expanded(
              child: Text(
                'SEZON YOLU',
                style: TextStyle(
                  color: LunoColors.gold,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            Text(
              '${_number(season['claimableCount'])} alınabilir',
              style: const TextStyle(
                color: LunoColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final row in path) _seasonTier(row),
      ],
    );
  }

  Widget _seasonHeader(int score, double progress, bool ended, bool syncing) {
    final copy = LunoLocalizations.of(context);
    final nextTrophies = _number(season['nextTrophies']);
    final nextLabel =
        nextTrophies > 0
            ? 'Sonraki kademe için ${formatTrophies(nextTrophies)} kupa'
            : 'Sezon yolu tamamlandı';
    return LunoSurface(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(8),
      color: ended ? const Color(0xE13B243A) : LunoColors.bgPanel,
      child: Row(
        children: [
          const SizedBox(
            width: 74,
            height: 74,
            child: LunoArt(LunoAssets.passSeason),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEZON ${_number(season['seasonNumber'])} · LUNO YÜKSELİŞİ',
                  style: const TextStyle(
                    color: LunoColors.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatTrophies(score)} kupa',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: LunoMotion.adaptive(context, LunoMotion.reward),
                  curve: Curves.easeOutCubic,
                  builder:
                      (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  ended
                      ? copy.translate('Sezon sona erdi')
                      : syncing
                      ? copy.translate('Sezon durumu senkronize ediliyor')
                      : '${copy.translate(nextLabel)} · ${copy.translate(_remainingLabel())}',
                  localize: false,
                  style: const TextStyle(
                    color: LunoColors.textDim,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seasonTier(Map<String, dynamic> row) {
    final state = row['state']?.toString() ?? 'locked';
    final claimed = state == 'claimed';
    final claimable = row['canClaim'] == true;
    final current = row['isCurrent'] == true;
    final reward = row['reward'];
    final rewardMap =
        reward is Map
            ? Map<String, dynamic>.from(reward)
            : const <String, dynamic>{};
    final color =
        current
            ? LunoColors.gold
            : claimable
            ? LunoColors.success
            : LunoColors.line;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: LunoSurface(
        padding: const EdgeInsets.all(10),
        borderRadius: BorderRadius.circular(8),
        color:
            claimed
                ? LunoColors.bgRaised
                : current
                ? LunoColors.bgRaised
                : state == 'locked'
                ? LunoColors.bgPanel
                : LunoColors.bgPanel2,
        border: Border.all(color: color, width: current ? 1.7 : 1),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Opacity(
                opacity: state == 'locked' ? .65 : 1,
                child: LunoArt(
                  claimed ? LunoAssets.resultVictory : LunoAssets.trophy,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['title']?.toString() ?? 'Sezon kademesi',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatTrophies(_number(row['minTrophies']))} kupa',
                    style: const TextStyle(
                      color: LunoColors.textDim,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: [
                      if (_number(rewardMap['gold']) > 0)
                        ResourceAmount.coin(
                          _number(rewardMap['gold']),
                          iconSize: 32,
                          fontSize: 14,
                        ),
                      if (_number(rewardMap['gems']) > 0)
                        ResourceAmount.gem(
                          _number(rewardMap['gems']),
                          iconSize: 32,
                          fontSize: 14,
                        ),
                    ],
                  ),
                  if (current && !claimable && !claimed)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'SIRADAKİ HEDEF',
                        style: TextStyle(
                          color: LunoColors.gold,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (claimed)
              Tooltip(
                message: LunoLocalizations.of(context).translate('Alındı'),
                child: ClipOval(
                  child: LunoArt(
                    'assets/native_art/arena-unlocked-v41.png',
                    width: 28,
                    height: 28,
                  ),
                ),
              )
            else if (claimable)
              IconButton(
                onPressed:
                    claiming ||
                            claimingEnd ||
                            (row['id']?.toString().trim().isEmpty ?? true)
                        ? null
                        : () =>
                            unawaited(_claimTier(row['id']?.toString() ?? '')),
                tooltip: LunoLocalizations.of(context).translate('Ödülü al'),
                icon: const Icon(Icons.redeem_rounded, color: LunoColors.gold),
              )
            else if (current)
              const Icon(Icons.flag_rounded, color: LunoColors.gold)
            else
              Tooltip(
                message: LunoLocalizations.of(context).translate('Kilitli'),
                child: ClipOval(
                  child: LunoArt(
                    'assets/native_art/arena-lock-v41.png',
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MissionsScreen extends StatefulWidget implements LunoAccountScopedPage {
  const MissionsScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  int tab = 0;
  bool loading = true;
  bool claiming = false;
  String? error;
  Timer? _periodTimer;
  bool _loadingRequest = false;
  AccountOperationGuard? _loadedOwner;
  final _requestTimeouts = ScreenRequestTimeouts();
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  Map<String, dynamic> periods = const {};
  Map<String, List<Map<String, dynamic>>> missions = const {
    'daily': <Map<String, dynamic>>[],
    'weekly': <Map<String, dynamic>>[],
    'special': <Map<String, dynamic>>[],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load({bool afterClaim = false}) async {
    if (!mounted || _loadingRequest) return;
    if (claiming && !afterClaim) {
      _periodTimer?.cancel();
      _periodTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) unawaited(_load());
      });
      return;
    }
    _loadingRequest = true;
    final guard = AccountOperationGuard(store, online);
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await _requestTimeouts.run(
        online.getPlayerState(),
        const Duration(seconds: 12),
      );
      guard.check();
      final state = result['state'];
      final rawRewards = state is Map ? state['rewards'] : null;
      final rawMissions = rawRewards is Map ? rawRewards['missions'] : null;
      final rawPeriods = rawRewards is Map ? rawRewards['periods'] : null;
      if (result['ok'] != true ||
          state is! Map ||
          rawMissions is! Map ||
          ![
            'daily',
            'weekly',
            'special',
          ].every((key) => rawMissions[key] is List)) {
        throw const FormatException('Missing authoritative missions');
      }
      final next = <String, List<Map<String, dynamic>>>{
        'daily': _missionRows(rawMissions, 'daily'),
        'weekly': _missionRows(rawMissions, 'weekly'),
        'special': _missionRows(rawMissions, 'special'),
      };
      if (!mounted) return;
      setState(() {
        missions = next;
        _loadedOwner = guard;
        periods =
            rawPeriods is Map
                ? Map<String, dynamic>.from(rawPeriods)
                : const {};
        loading = false;
      });
      _schedulePeriodRefresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          _loadedOwner = null;
          missions = const {'daily': [], 'weekly': [], 'special': []};
          error =
              guard.isCurrent
                  ? 'Görevler sunucudan yüklenemedi.'
                  : 'Hesabın değişti. Görev ekranını yeniden aç.';
        });
      }
    } finally {
      _loadingRequest = false;
    }
  }

  List<Map<String, dynamic>> _missionRows(Object? raw, String category) {
    if (raw is! Map || raw[category] is! List) return const [];
    return (raw[category] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _title(String id, [Map<String, dynamic>? mission]) =>
      mission?['title'] is String &&
              (mission!['title'] as String).trim().isNotEmpty
          ? mission['title'] as String
          : <String, String>{
                'd1': 'Tahtaya çık',
                'd2': 'Zafer zamanı',
                'd3': 'Kart ustası',
                'd4': 'Seriyi koru',
                'w1': 'Haftalık hedef',
                's1': 'Arena yolcusu',
              }[id] ??
              'Gizli hedef';

  String _description(Map<String, dynamic> mission) {
    final serverDescription = mission['description'];
    if (serverDescription is String && serverDescription.trim().isNotEmpty) {
      return serverDescription;
    }
    final target = _number(mission['target']);
    return '${_title(mission['id']?.toString() ?? '', mission)} · hedef $target';
  }

  String _art(String id) {
    if (id.contains('win')) return 'assets/native_art/pass-mission-win-v8.png';
    if (id.contains('card')) {
      return 'assets/native_art/pass-mission-card-v8.png';
    }
    if (id.contains('streak')) {
      return 'assets/native_art/pass-mission-streak-v8.png';
    }
    if (id.startsWith('w')) {
      return 'assets/native_art/pass-mission-weekly-v8.png';
    }
    return 'assets/native_art/pass-mission-play-v8.png';
  }

  int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  String _rewardLabel(Map<String, dynamic> mission) {
    final reward = mission['reward'];
    if (reward is! Map) return 'Ödül';
    final gold = _number(reward['gold']);
    final gems = _number(reward['gems']);
    final passXp = _number(mission['passXp']);
    return [
      if (gold > 0) '$gold altın',
      if (gems > 0) '$gems elmas',
      if (passXp > 0) '$passXp Pass XP',
    ].join(' + ');
  }

  String _periodLabel(String category) {
    final key = periods[category == 'daily' ? 'dayKey' : 'weekKey'];
    if (key is! String || key.isEmpty) return '';
    return category == 'daily'
        ? 'Bugünün görevleri · $key'
        : 'Bu haftanın görevleri · $key';
  }

  void _schedulePeriodRefresh() {
    _periodTimer?.cancel();
    final serverTime = periods['serverTime'];
    if (serverTime is! num) return;
    const dayMs = 86400000;
    final nextUtcDay = ((serverTime.toInt() ~/ dayMs) + 1) * dayMs + 1000;
    final delayMs =
        (nextUtcDay - serverTime.toInt()).clamp(1000, 8 * dayMs).toInt();
    _periodTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _periodTimer?.cancel();
    _requestTimeouts.dispose();
    super.dispose();
  }

  Future<void> _claim(String category, String missionId) async {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        claiming ||
        loading ||
        _loadingRequest ||
        _loadedOwner?.isCurrent != true) {
      return;
    }
    final rows = missions[category];
    if (rows == null ||
        !rows.any(
          (row) =>
              row['id'] == missionId &&
              row['claimed'] != true &&
              _number(row['target']) > 0 &&
              _number(row['progress']) >= _number(row['target']),
        )) {
      return;
    }
    setState(() => claiming = true);
    final guard = _loadedOwner!;
    try {
      final result = await online.claimMissionReward(category, missionId);
      guard.check();
      validateRewardClaimResult(result);
      final state = result['state'];
      if (state is Map) {
        store.applyServerState(Map<String, dynamic>.from(state));
      }
      guard.check();
      await _load(afterClaim: true);
    } catch (_) {
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'İşlem doğrulanamadı. Bağlantı yenilendiğinde durumunu kontrol et.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GÖREVLER')),
      body: LunoBackdrop(
        art: LunoAssets.missionsSceneV27,
        overlay: const Color(0x661A1020),
        focalPoint: const Alignment(0, -.15),
        child: Column(
          children: [
            LunoSurface(
              padding: const EdgeInsets.all(16),
              color: LunoColors.bgPanel,
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: LunoArt(LunoAssets.passMissions),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GÖREVLERİ TAMAMLA',
                          style: TextStyle(
                            color: LunoColors.gold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Hedeflerini tamamla; altın, elmas ve Pass XP kazan.',
                          style: TextStyle(
                            color: LunoColors.textDim,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Tabs(
              labels: const ['GÜNLÜK', 'HAFTALIK', 'ÖZEL'],
              selected: tab,
              onChanged: (value) => setState(() => tab = value),
            ),
            if (tab < 2 && _periodLabel(['daily', 'weekly'][tab]).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _periodLabel(['daily', 'weekly'][tab]),
                    style: const TextStyle(
                      color: LunoColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Expanded(
              child:
                  loading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: LunoColors.gold,
                        ),
                      )
                      : error != null
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: LunoColors.textDim,
                                ),
                              ),
                              const SizedBox(height: 16),
                              LunoButton(
                                label: 'TEKRAR DENE',
                                icon: Icons.refresh_rounded,
                                backgroundArt: LunoAssets.actionSurfaceV27,
                                expand: false,
                                onPressed: () => unawaited(_load()),
                              ),
                            ],
                          ),
                        ),
                      )
                      : missions[['daily', 'weekly', 'special'][tab]]!.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Bu bölümde şu an görev yok.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                        itemCount:
                            missions[['daily', 'weekly', 'special'][tab]]!
                                .length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final category = ['daily', 'weekly', 'special'][tab];
                          return _missionTile(
                            category,
                            missions[category]![index],
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _missionTile(String category, Map<String, dynamic> mission) {
    final id = mission['id']?.toString() ?? '';
    final progress = _number(mission['progress']);
    final target = _number(mission['target']);
    final claimed = mission['claimed'] == true;
    final complete = target > 0 && progress >= target && !claimed;
    return LunoSurface(
      padding: const EdgeInsets.all(10),
      color: claimed ? LunoColors.bgRaised : LunoColors.bgPanel,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          SizedBox(width: 54, height: 54, child: LunoArt(_art(id))),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(id, mission),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _description(mission),
                  style: const TextStyle(
                    color: LunoColors.textDim,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                TweenAnimationBuilder<double>(
                  key: ValueKey('$category:$id'),
                  tween: Tween(
                    begin: 0,
                    end:
                        target <= 0
                            ? 0
                            : (progress / target).clamp(0, 1).toDouble(),
                  ),
                  duration: LunoMotion.adaptive(context, LunoMotion.reward),
                  curve: Curves.easeOutCubic,
                  builder:
                      (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(6),
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$progress/$target',
                  style: const TextStyle(
                    color: LunoColors.textDim,
                    fontSize: 12,
                  ),
                ),
                if (_rewardLabel(mission).isNotEmpty)
                  Text(
                    _rewardLabel(mission),
                    style: const TextStyle(
                      color: LunoColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (claimed)
            Tooltip(
              message: LunoLocalizations.of(context).translate('Alındı'),
              child: ClipOval(
                child: LunoArt(
                  'assets/native_art/arena-unlocked-v41.png',
                  width: 28,
                  height: 28,
                ),
              ),
            )
          else if (complete)
            IconButton(
              onPressed: claiming ? null : () => _claim(category, id),
              tooltip: LunoLocalizations.of(context).translate('Ödülü al'),
              icon: const Icon(Icons.redeem_rounded, color: LunoColors.gold),
            ),
        ],
      ),
    );
  }
}

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, this.online});

  final LunoOnlineService? online;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  String mode = 'trophies';
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = const [];
  int _loadSerial = 0;
  late int _accountRevision;
  String? _accountUid;
  late bool _wasReady;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;

  void _onOnlineChanged() {
    if (!mounted) return;
    final online = _online;
    final accountChanged =
        _accountRevision != online.accountRevision ||
        _accountUid != online.user?.uid;
    final ready = online.ready && !online.authTransitioning;
    final becameReady = ready && !_wasReady;
    _accountRevision = online.accountRevision;
    _accountUid = online.user?.uid;
    _wasReady = ready;
    if (accountChanged) {
      ++_loadSerial;
      setState(() {
        rows = const [];
        loading = false;
        error = 'Sıralama bağlantısı hazırlanıyor.';
      });
    }
    if ((accountChanged || becameReady) &&
        online.ready &&
        !online.authTransitioning &&
        !loading &&
        ModalRoute.of(context)?.isCurrent != false) {
      unawaited(_load());
    }
  }

  @override
  void initState() {
    super.initState();
    _accountRevision = _online.accountRevision;
    _accountUid = _online.user?.uid;
    _wasReady = _online.ready && !_online.authTransitioning;
    _online.addListener(_onOnlineChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _online.removeListener(_onOnlineChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final requestMode = mode;
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final serial = ++_loadSerial;
    final online = _online;
    final revision = online.accountRevision;
    final uid = online.user?.uid;
    bool currentRequest() =>
        mounted &&
        serial == _loadSerial &&
        revision == online.accountRevision &&
        uid == online.user?.uid;
    // A screen can be opened directly before the deferred Firebase bootstrap
    // finishes. Do not start an uncancellable network timeout from a widget
    // that may be disposed immediately; the service listener retries once the
    // shared session is ready, while the user still gets a clear offline state.
    if (!online.ready || online.authTransitioning) {
      if (mounted) {
        setState(() {
          rows = const [];
          loading = false;
          error =
              online.lastError == null
                  ? 'Sıralama bağlantısı hazırlanıyor.'
                  : 'Sıralama servisine şu anda ulaşılamıyor.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        rows = const [];
      });
    }
    try {
      final result = await online.api('/getLeaderboard', {
        'mode': requestMode,
        if (requestMode == 'trophies') 'protocolVersion': 'LUNO_BATTLE_V1',
        'limit': 25,
      });
      if (!currentRequest()) return;
      final parsed = parseLeaderboardResult(result, requestMode);
      setState(() {
        rows = parsed;
        loading = false;
      });
    } catch (_) {
      if (!currentRequest()) return;
      setState(() {
        rows = const [];
        error = 'Sıralama servisine şu anda ulaşılamıyor.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIRALAMA'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            tooltip: LunoLocalizations.of(context).translate('Yenile'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.phase2RankingPodium,
        overlay: const Color(0xC9100A24),
        child: Column(
          children: [
            _Tabs(
              labels: const ['KUPA', 'SEZON'],
              selected: ['trophies', 'season'].indexOf(mode),
              onChanged: (value) {
                final next = ['trophies', 'season'][value];
                if (next == mode) return;
                setState(() => mode = next);
                _load();
              },
            ),
            Expanded(
              child:
                  loading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: LunoColors.gold,
                        ),
                      )
                      : error != null
                      ? _error()
                      : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                        children: [
                          _podium(),
                          const SizedBox(height: 12),
                          if (rows.isEmpty)
                            const LunoSurface(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                'Sıralama verileri hazır olduğunda burada görünecek.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: LunoColors.textDim),
                              ),
                            )
                          else
                            for (int i = 0; i < rows.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _row(rows[i], i),
                              ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _podium() {
    final labels = <String>['2', '1', '3'];
    final stars = <String>[
      LunoAssets.rankingStarSilver,
      LunoAssets.rankingStarGold,
      LunoAssets.rankingStarBronze,
    ];
    final indexes = <int>[1, 0, 2];

    return Container(
      height:
          270 +
          (MediaQuery.textScalerOf(context).scale(100) - 100).clamp(0, 200),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LunoColors.bgRaised, LunoColors.bgPanel],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LunoColors.bgPanel2),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LunoArt(LunoAssets.rankingCrown, width: 25, height: 25),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    mode == 'trophies' ? 'EN İYİLER' : 'SEZON SIRALAMASI',
                    style: const TextStyle(
                      color: LunoColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              LunoArt(LunoAssets.rankingCrown, width: 25, height: 25),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < 3; i++)
                  Expanded(
                    child: _podiumPlace(
                      place: int.parse(labels[i]),
                      star: stars[i],
                      row: indexes[i] < rows.length ? rows[indexes[i]] : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _podiumPlace({
    required int place,
    required String star,
    required Map<String, dynamic>? row,
  }) {
    final name = usernameFromMap(row, fallback: 'Yakında');
    final score = row == null ? null : _score(row);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: row == null ? null : () => _openPlayer(row),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              LunoArt(
                star,
                width: place == 1 ? 28 : 23,
                height: place == 1 ? 28 : 23,
              ),
              const SizedBox(height: 2),
              LunoArt(
                LunoAssets.avatar(row?['avatarEmoji']?.toString() ?? 'av_pawn'),
                width: 42,
                height: 42,
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (score != null)
                Text(
                  '$score',
                  style: const TextStyle(
                    color: LunoColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Container(
                height: place == 1 ? 98 : 78,
                margin: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors:
                        place == 1
                            ? const [Color(0xFF977C39), Color(0xFF4C4937)]
                            : place == 2
                            ? const [Color(0xFF728D91), Color(0xFF334C53)]
                            : const [Color(0xFF93664F), Color(0xFF4C3C38)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  border: Border.all(color: const Color(0x66FFE5A6)),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: LunoColors.bgPanel,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color:
                            place == 1
                                ? LunoColors.gold
                                : LunoColors.goldDeep.withValues(alpha: .7),
                      ),
                    ),
                    child: Text(
                      '$place',
                      style: TextStyle(
                        color: place == 1 ? LunoColors.gold : LunoColors.ivory,
                        fontFamily: 'Cinzel',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlayer(Map<String, dynamic> row) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (_accountRevision != _online.accountRevision ||
        _accountUid != _online.user?.uid ||
        _online.accountFailure != null ||
        _online.authTransitioning ||
        !rows.contains(row)) {
      return;
    }
    final uid = row['uid'];
    if (uid is! String || uid.trim().isEmpty) return;
    Navigator.of(context).push(
      lunoRoute(
        LunoAccountScope(
          service: _online,
          page: PublicPlayerProfileScreen(
            targetUid: uid.trim(),
            online: _online,
          ),
        ),
      ),
    );
  }

  int _score(Map<String, dynamic> row, [String? rankingMode]) {
    final activeMode = rankingMode ?? mode;
    final value = row[activeMode == 'trophies' ? 'trophies' : 'seasonScore'];
    final score = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return score < 0 ? 0 : score;
  }

  Widget _error() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LunoArt(LunoAssets.profileCrest, width: 100, height: 100),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LunoColors.textDim),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('TEKRAR DENE'),
          ),
        ],
      ),
    ),
  );

  Widget _row(Map<String, dynamic> row, int index) {
    final name = usernameFromMap(row);
    final score = _score(row);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPlayer(row),
        child: LunoSurface(
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? LunoColors.gold : LunoColors.textDim,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              LunoArt(
                LunoAssets.avatar(row['avatarEmoji']?.toString() ?? 'av_pawn'),
                width: 38,
                height: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatTrophies(score),
                        style: const TextStyle(
                          color: LunoColors.gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: LunoColors.textDim,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FriendsScreen extends StatefulWidget implements LunoAccountScopedPage {
  static const socialLoadTimeout = Duration(seconds: 12);
  const FriendsScreen({super.key, this.online});

  final LunoOnlineService? online;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final controller = TextEditingController();
  final _requestTimeouts = ScreenRequestTimeouts();
  int tab = 0;
  bool loading = false;
  bool socialLoading = true;
  String? socialError;
  int _socialLoadSerial = 0;
  int _searchSerial = 0;
  String? _activeSearchQuery;
  bool searchActive = false;
  String? searchError;
  List<Map<String, dynamic>> results = const [];
  List<Map<String, dynamic>> friendRows = const [];
  List<Map<String, dynamic>> requestRows = const [];
  final Set<String> friendBusy = <String>{};
  final Set<String> inviteBusy = <String>{};
  StreamSubscription<List<Map<String, dynamic>>>? _friendRequestSubscription;
  bool _friendRequestSnapshotReady = false;
  int _friendRequestVersion = 0;
  Stream<List<Map<String, dynamic>>>? _matchInviteStream;
  late final String? _entryUid;
  late final int _entryRevision;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsSession =>
      mounted &&
      _online.user?.uid == _entryUid &&
      _online.accountRevision == _entryRevision &&
      _online.accountFailure == null;
  bool get _canAct =>
      _ownsSession && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSocial());
    });
  }

  @override
  void dispose() {
    _requestTimeouts.dispose();
    _friendRequestSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    if (!_canAct) return;
    final loadSerial = ++_socialLoadSerial;
    if (mounted) {
      setState(() {
        socialLoading = true;
        socialError = null;
      });
    }
    try {
      final online = _online;
      await _requestTimeouts.run(
        online.start(),
        FriendsScreen.socialLoadTimeout,
      );
      if (!_ownsSession || loadSerial != _socialLoadSerial) return;
      final requestVersion = _friendRequestVersion;
      _matchInviteStream ??= online.matchInvitesStream();
      _friendRequestSubscription ??= online.friendRequestsStream().listen(
        _onFriendRequestsChanged,
        onError: (Object error, StackTrace stack) {
          if (_ownsSession) _toast('Arkadaşlık istekleri şu an yenilenemedi.');
        },
      );
      final values = await _requestTimeouts.run(
        Future.wait([online.friends(), online.friendRequests()]),
        FriendsScreen.socialLoadTimeout,
      );
      if (!_ownsSession || loadSerial != _socialLoadSerial) return;
      setState(() {
        friendRows = values[0];
        if (requestVersion == _friendRequestVersion) requestRows = values[1];
        _friendRequestSnapshotReady = true;
      });
    } catch (_) {
      if (_ownsSession && loadSerial == _socialLoadSerial) {
        setState(() {
          socialError =
              LunoLocalizations.of(context).isEnglish
                  ? 'Social information could not be loaded.'
                  : 'Sosyal bilgiler yüklenemedi.';
          friendRows = const [];
          if (!_friendRequestSnapshotReady) requestRows = const [];
        });
        _toast('Sosyal bilgiler şu an yenilenemedi.');
      }
    } finally {
      if (_ownsSession && loadSerial == _socialLoadSerial) {
        setState(() => socialLoading = false);
      }
    }
  }

  void _onFriendRequestsChanged(List<Map<String, dynamic>> requests) {
    if (!_ownsSession) return;
    final known =
        requestRows
            .map((request) => request['fromUid']?.toString() ?? '')
            .where((uid) => uid.isNotEmpty)
            .toSet();
    final hasNewRequest =
        _friendRequestSnapshotReady &&
        requests.any(
          (request) => !known.contains(request['fromUid']?.toString() ?? ''),
        );
    setState(() {
      ++_friendRequestVersion;
      _friendRequestSnapshotReady = true;
      requestRows = requests;
    });
    if (hasNewRequest && tab != 1) {
      _toast('Yeni bir arkadaşlık isteğin var.');
    }
  }

  Future<void> _search() async {
    if (!_canAct) return;
    final query = controller.text.trim().toLowerCase();
    if (query.length < 3) {
      _toast('En az 3 karakter yaz.');
      return;
    }
    if (!RegExp(r'^(?:[a-z0-9_]{3,16}|luno-[a-f0-9]{3,8})$').hasMatch(query)) {
      _toast('Geçerli bir kullanıcı adı veya oyuncu kodu yaz.');
      return;
    }
    if (loading && _activeSearchQuery == query) return;
    final searchSerial = ++_searchSerial;
    _activeSearchQuery = query;
    setState(() {
      loading = true;
      searchActive = true;
      searchError = null;
      results = const [];
      tab = 0;
    });
    try {
      final value = await _online.api('/searchPlayers', {
        'query': query,
        'protocolVersion': 'LUNO_BATTLE_V1',
      });
      final nextResults = parsePlayerSearchResult(value, ownUid: _entryUid);
      if (_ownsSession && searchSerial == _searchSerial) {
        setState(() => results = nextResults);
      }
    } catch (_) {
      if (_ownsSession && searchSerial == _searchSerial) {
        setState(() => searchError = 'Oyuncu araması şu an kullanılamıyor.');
        _toast('Oyuncu araması şu an kullanılamıyor.');
      }
    }
    if (_ownsSession && searchSerial == _searchSerial) {
      setState(() => loading = false);
    }
  }

  void _changeTab(int value) {
    if (!_canAct) return;
    setState(() {
      _searchSerial++;
      loading = false;
      searchActive = false;
      searchError = null;
      tab = value;
      results = const [];
    });
    if (value < 2) _loadSocial();
  }

  Future<void> _addFriend(Map<String, dynamic> player) async {
    if (!_canAct || loading || !searchActive) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty ||
        friendBusy.contains(targetUid) ||
        !results.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    setState(() => friendBusy.add(targetUid));
    try {
      final status = await _online.sendFriendRequest(targetUid);
      if (!_ownsSession) return;
      _toast(
        status == 'accepted'
            ? 'Arkadaşlık isteği kabul edildi.'
            : status == 'friends'
            ? 'Bu oyuncu zaten arkadaşın.'
            : status == 'pending'
            ? 'Arkadaşlık isteği zaten bekliyor.'
            : 'Arkadaşlık isteği gönderildi.',
      );
      if (_ownsSession) {
        setState(() {
          final index = results.indexWhere(
            (row) => row['uid']?.toString() == targetUid,
          );
          if (index >= 0) {
            results[index] = Map<String, dynamic>.from(results[index])
              ..['relationship'] = switch (status) {
                'sent' => 'outgoing',
                'accepted' => 'friends',
                'pending' => 'outgoing',
                _ => status,
              };
          }
        });
      }
      await _loadSocial();
    } catch (error) {
      _toast(
        error is LunoApiException && error.code == 'user-blocked'
            ? 'Bu oyuncuyla etkileşim kuramazsın.'
            : 'Arkadaşlık isteği gönderilemedi.',
      );
    } finally {
      if (_ownsSession) setState(() => friendBusy.remove(targetUid));
    }
  }

  Future<void> _respond(
    Map<String, dynamic> request, {
    required bool accept,
  }) async {
    if (!_canAct) return;
    final fromUid = request['fromUid']?.toString() ?? '';
    if (fromUid.isEmpty ||
        friendBusy.contains(fromUid) ||
        !requestRows.any((row) => row['fromUid']?.toString() == fromUid)) {
      return;
    }
    setState(() => friendBusy.add(fromUid));
    try {
      await _online.respondFriendRequest(fromUid, accept: accept);
      if (!_ownsSession) return;
      _toast(accept ? 'Arkadaşlık isteği kabul edildi.' : 'İstek reddedildi.');
      await _loadSocial();
    } catch (error) {
      _toast(
        error is LunoApiException && error.code == 'request-not-found'
            ? 'Bu istek artık beklemiyor.'
            : 'İstek güncellenemedi.',
      );
    } finally {
      if (_ownsSession) setState(() => friendBusy.remove(fromUid));
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> player) async {
    if (!_canAct) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty ||
        friendBusy.contains(targetUid) ||
        !friendRows.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    final confirmed = await showLunoAccountDialog<bool>(
      context: context,
      service: _online,
      builder:
          (dialogContext) => AlertDialog(
            scrollable: true,
            backgroundColor: LunoColors.bgPanel,
            titleTextStyle: LunoType.sectionTitle,
            title: const Text('Arkadaşlıktan çıkarılsın mı?'),
            content: Text(
              '${usernameFromMap(player)} artık arkadaş listende olmayacak.',
            ),
            actions: [
              LunoButton(
                expand: false,
                kind: LunoButtonKind.secondary,
                onPressed: () => dismissLunoAccountModal(dialogContext, false),
                label: 'VAZGEÇ',
              ),
              LunoButton(
                expand: false,
                kind: LunoButtonKind.danger,
                leading: const SizedBox(
                  width: 28,
                  height: 28,
                  child: LunoArt(
                    LunoAssets.friendsActionRemove,
                    width: 28,
                    height: 28,
                  ),
                ),
                onPressed: () => dismissLunoAccountModal(dialogContext, true),
                label: 'ÇIKAR',
              ),
            ],
          ),
    );
    if (confirmed != true ||
        !mounted ||
        !_ownsSession ||
        ModalRoute.of(context)?.isCurrent == false ||
        friendBusy.contains(targetUid) ||
        !friendRows.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    setState(() => friendBusy.add(targetUid));
    try {
      await _online.removeFriend(targetUid);
      if (!_ownsSession) return;
      _toast('Arkadaşlıktan çıkarıldı.');
      await _loadSocial();
    } catch (_) {
      _toast('Arkadaşlık kaldırılamadı.');
    } finally {
      if (_ownsSession) setState(() => friendBusy.remove(targetUid));
    }
  }

  Future<void> _openMessage(Map<String, dynamic> player) async {
    if (!_canAct) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty) return;
    Navigator.of(context).push(
      lunoRoute(
        DirectMessageScreen(
          targetUid: targetUid,
          targetName: usernameFromMap(player),
          online: _online,
        ),
      ),
    );
  }

  Future<void> _inviteFriend(Map<String, dynamic> player) async {
    if (!_canAct) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty ||
        inviteBusy.contains(targetUid) ||
        !friendRows.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    setState(() => inviteBusy.add(targetUid));
    try {
      final status = await _online.sendBattleV1Invite(targetUid);
      if (!_ownsSession) return;
      _toast(
        status == 'pending'
            ? 'Bu oyuncuya zaten bekleyen bir davet var.'
            : 'Dostluk maçı daveti gönderildi.',
      );
    } catch (error) {
      final message =
          error is LunoApiException && error.code == 'friend-required'
              ? 'Önce bu oyuncuyla arkadaş olmalısın.'
              : error is LunoApiException &&
                  (error.code == 'match-already-active' ||
                      error.code == 'opponent-busy')
              ? 'Oyunculardan biri şu anda maçta.'
              : 'Dostluk maçı daveti gönderilemedi.';
      _toast(message);
    } finally {
      if (_ownsSession) setState(() => inviteBusy.remove(targetUid));
    }
  }

  Future<void> _respondMatchInvite(
    Map<String, dynamic> invite, {
    required bool accept,
  }) async {
    if (!_canAct) return;
    final fromUid = invite['fromUid']?.toString() ?? '';
    if (fromUid.isEmpty || inviteBusy.contains(fromUid)) return;
    setState(() => inviteBusy.add(fromUid));
    try {
      final result = await _online.respondBattleV1Invite(
        fromUid,
        accept: accept,
      );
      final view = result['view'];
      final matchId =
          result['matchId']?.toString() ??
          (view is Map ? view['matchId']?.toString() ?? '' : '');
      if (!mounted || !_canAct) return;
      if (accept && view is Map && matchId.isNotEmpty) {
        Navigator.of(context).push(
          lunoRoute(
            BattleV1Screen(
              matchId: matchId,
              initialView: Map<String, dynamic>.from(view),
            ),
          ),
        );
      } else {
        _toast(accept ? 'Davet kabul edildi.' : 'Davet reddedildi.');
      }
    } catch (error) {
      _toast(
        error is LunoApiException && error.code == 'invite-expired'
            ? 'Bu davetin süresi dolmuş.'
            : 'Maç daveti güncellenemedi.',
      );
    } finally {
      if (_ownsSession) setState(() => inviteBusy.remove(fromUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('ARKADAŞLAR', style: LunoType.screenTitle),
        actions: [
          IconButton(
            onPressed: socialLoading ? null : _loadSocial,
            tooltip: LunoLocalizations.of(context).translate('Yenile'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.lobbySceneV29,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, -.12),
        child: _SocialViewport(
          child: NestedScrollView(
            headerSliverBuilder:
                (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                          child: TextField(
                            controller: controller,
                            onChanged: (_) {
                              setState(() {
                                _searchSerial++;
                                loading = false;
                                searchActive = false;
                                searchError = null;
                                results = const [];
                              });
                            },
                            onSubmitted: (_) => _search(),
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            decoration: InputDecoration(
                              hintText: LunoLocalizations.of(
                                context,
                              ).translate('Kullanıcı adı veya Luno kodu'),
                              filled: true,
                              fillColor: LunoColors.bgPanel2,
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(10),
                                child: LunoArt(
                                  LunoAssets.friendsSearch,
                                  width: 26,
                                  height: 26,
                                ),
                              ),
                              suffixIcon: IconButton(
                                onPressed: loading ? null : _search,
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Ara'),
                                icon: const Icon(Icons.arrow_forward_rounded),
                              ),
                            ),
                          ),
                        ),
                        _FriendsVisualTabs(
                          selected: tab,
                          onChanged: _changeTab,
                        ),
                      ],
                    ),
                  ),
                ],
            body: _content(),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (tab == 0 && searchActive) {
      if (loading) {
        return const Center(
          child: CircularProgressIndicator(color: LunoColors.gold),
        );
      }
      if (searchError != null) return _empty(searchError!);
      if (results.isEmpty) {
        return _empty(
          LunoLocalizations.of(context).isEnglish
              ? 'No players found.'
              : 'Oyuncu bulunamadı.',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: results.length,
        itemBuilder: (_, index) => _player(results[index], searchResult: true),
      );
    }
    if (socialError != null &&
        !socialLoading &&
        (tab != 1 || !_friendRequestSnapshotReady)) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(socialError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadSocial,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  LunoLocalizations.of(context).isEnglish
                      ? 'TRY AGAIN'
                      : 'TEKRAR DENE',
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (tab == 2) {
      if (socialLoading && friendRows.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(color: LunoColors.gold),
        );
      }
      if (friendRows.isEmpty) return _empty('Sıralanacak arkadaşın yok.');
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: friendRows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, index) => _friendRankRow(friendRows[index], index),
      );
    }
    if (socialLoading && results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: LunoColors.gold),
      );
    }
    if (tab == 1) {
      if (requestRows.isEmpty) {
        return _empty('Bekleyen istek yok', requests: true);
      }
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: requestRows.length,
        itemBuilder: (_, index) => _request(requestRows[index]),
      );
    }
    final rows = results.isNotEmpty ? results : friendRows;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _matchInviteStream,
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty && invites.isEmpty) {
          return _empty('Henüz arkadaşın yok. Kullanıcı adıyla ara.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: invites.length + rows.length,
          itemBuilder:
              (_, index) =>
                  index < invites.length
                      ? _inviteTile(invites[index])
                      : _player(
                        rows[index - invites.length],
                        searchResult: results.isNotEmpty,
                      ),
        );
      },
    );
  }

  Widget _inviteTile(Map<String, dynamic> invite) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: LunoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          LunoArt(
            LunoAssets.avatar(invite['fromAvatar']?.toString() ?? 'av_pawn'),
            width: 38,
            height: 38,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${usernameFromMap(invite, fallback: 'Oyuncu')} seni maça çağırıyor',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed:
                inviteBusy.contains(invite['fromUid'])
                    ? null
                    : () => _respondMatchInvite(invite, accept: false),
            tooltip: LunoLocalizations.of(context).translate('Reddet'),
            icon: const LunoArt(
              LunoAssets.friendsActionReject,
              width: 30,
              height: 30,
            ),
          ),
          IconButton(
            onPressed:
                inviteBusy.contains(invite['fromUid'])
                    ? null
                    : () => _respondMatchInvite(invite, accept: true),
            tooltip: LunoLocalizations.of(context).translate('Kabul et'),
            icon: const LunoArt(
              LunoAssets.friendsActionAccept,
              width: 30,
              height: 30,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _empty(String message, {bool requests = false}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LunoArt(
              requests
                  ? LunoAssets.friendsRequestsEmpty
                  : 'assets/native_art/friends-welcome-v35.png',
              width: 140,
              height: 140,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: LunoType.body.copyWith(color: LunoColors.ivory),
          ),
        ],
      ),
    ),
  );

  Widget _player(Map<String, dynamic> player, {required bool searchResult}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openFriendProfile(player),
          child: LunoSurface(
            padding: const EdgeInsets.all(11),
            color: LunoColors.bgPanel,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    LunoArt(
                      LunoAssets.avatar(
                        player['avatarEmoji']?.toString() ?? 'av_pawn',
                      ),
                      width: 44,
                      height: 44,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usernameFromMap(player),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Row(
                            children: [
                              const LunoArt(
                                LunoAssets.profileTrophy,
                                width: 28,
                                height: 28,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  formatTrophies(
                                    _number(
                                      player['trophies'],
                                    ).clamp(0, 1000000000),
                                  ),
                                  style: const TextStyle(
                                    color: LunoColors.gold,
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
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child:
                      !searchResult
                          ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF315E69),
                                ),
                                onPressed: () {
                                  LunoFeedback.tap();
                                  _openMessage(player);
                                },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Mesaj gönder'),
                                icon: const LunoArt(
                                  LunoAssets.friendsActionMessage,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF365C42),
                                ),
                                onPressed:
                                    inviteBusy.contains(player['uid'])
                                        ? null
                                        : () {
                                          LunoFeedback.tap();
                                          _inviteFriend(player);
                                        },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Maça davet et'),
                                icon: const LunoArt(
                                  LunoAssets.friendsActionBattle,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF613D42),
                                ),
                                onPressed:
                                    friendBusy.contains(player['uid'])
                                        ? null
                                        : () {
                                          LunoFeedback.tap();
                                          _removeFriend(player);
                                        },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Arkadaşlıktan çıkar'),
                                icon: const LunoArt(
                                  LunoAssets.friendsActionRemove,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                            ],
                          )
                          : _searchAction(player),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _searchAction(Map<String, dynamic> player) {
    final targetUid = player['uid']?.toString() ?? '';
    final relationship = player['relationship']?.toString() ?? 'none';
    if (relationship == 'friends') {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'ARKADAŞ',
          style: TextStyle(color: LunoColors.teal, fontWeight: FontWeight.w900),
        ),
      );
    }
    final pending = relationship == 'outgoing';
    return FilledButton.icon(
      onPressed:
          targetUid.isEmpty || pending || friendBusy.contains(targetUid)
              ? null
              : () => _addFriend(player),
      icon: LunoArt(
        pending ? LunoAssets.friendsActionAccept : LunoAssets.friendsActionAdd,
        width: 21,
        height: 21,
      ),
      label: Text(
        relationship == 'incoming'
            ? 'KABUL ET'
            : pending
            ? 'GÖNDERİLDİ'
            : 'EKLE',
      ),
    );
  }

  Widget _friendRankRow(Map<String, dynamic> player, int index) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openFriendProfile(player),
        child: LunoSurface(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? LunoColors.gold : LunoColors.textDim,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              LunoArt(
                LunoAssets.avatar(
                  player['avatarEmoji']?.toString() ?? 'av_pawn',
                ),
                width: 42,
                height: 42,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usernameFromMap(player),
                      localize: false,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${_number(player['trophies'])} ${LunoLocalizations.of(context).isEnglish ? 'trophies' : 'kupa'}',
                      style: const TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: LunoColors.textDim,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _openFriendProfile(Map<String, dynamic> player) {
    if (!_canAct || loading || socialLoading || tab == 1) return;
    final visibleRows = tab == 0 && searchActive ? results : friendRows;
    final uid = player['uid'];
    if (!visibleRows.contains(player) || uid is! String || uid.trim().isEmpty) {
      return;
    }
    Navigator.of(context).push(
      lunoRoute(
        LunoAccountScope(
          service: _online,
          page: PublicPlayerProfileScreen(targetUid: uid, online: _online),
        ),
      ),
    );
  }

  int _number(dynamic value) {
    if (value is num && !value.isFinite) return 0;
    final result = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return result < 0 ? 0 : result;
  }

  Widget _request(Map<String, dynamic> request) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: LunoSurface(
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          LunoArt(
            LunoAssets.avatar(request['avatarEmoji']?.toString() ?? 'av_pawn'),
            width: 44,
            height: 44,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              usernameFromMap({
                'username': request['fromUsername'],
                'name': request['fromName'],
              }),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            onPressed:
                friendBusy.contains(request['fromUid'])
                    ? null
                    : () => _respond(request, accept: false),
            tooltip: LunoLocalizations.of(context).translate('Reddet'),
            color: LunoColors.danger,
            icon: const LunoArt(
              LunoAssets.friendsActionReject,
              width: 30,
              height: 30,
            ),
          ),
          IconButton(
            onPressed:
                friendBusy.contains(request['fromUid'])
                    ? null
                    : () => _respond(request, accept: true),
            tooltip: LunoLocalizations.of(context).translate('Kabul et'),
            color: LunoColors.success,
            icon: const LunoArt(
              LunoAssets.friendsActionAccept,
              width: 30,
              height: 30,
            ),
          ),
        ],
      ),
    ),
  );

  void _toast(String message) {
    if (!_canAct) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SocialViewport extends StatelessWidget {
  const _SocialViewport({required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox.expand(child: child),
    ),
  );
}

class _FriendsVisualTabs extends StatelessWidget {
  const _FriendsVisualTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    final labels =
        english
            ? const ['FRIENDS', 'REQUESTS', 'LEADERBOARD']
            : const ['ARKADAŞLAR', 'İSTEKLER', 'SIRALAMA'];
    const icons = [
      Icons.people_alt_outlined,
      Icons.person_add_alt_1_rounded,
      Icons.emoji_events_outlined,
    ];
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w800);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          var labelWidth = 0.0;
          for (final label in labels) {
            final painter = TextPainter(
              text: TextSpan(
                text: label,
                style: DefaultTextStyle.of(context).style.merge(style),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            if (painter.width > labelWidth) labelWidth = painter.width;
            painter.dispose();
          }
          final horizontal = (constraints.maxWidth - 16) / 3 >= labelWidth + 54;
          final tabs = [
            for (var index = 0; index < labels.length; index++)
              Semantics(
                selected: index == selected,
                button: true,
                child: Material(
                  color:
                      index == selected
                          ? const Color(0xFF24545A)
                          : LunoColors.bgPanel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color:
                          index == selected ? LunoColors.gold : LunoColors.line,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('friends-visual-tab-$index'),
                    onTap:
                        selected == index
                            ? null
                            : () {
                              LunoFeedback.tap();
                              onChanged(index);
                            },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[index],
                            size: 22,
                            color:
                                index == selected
                                    ? LunoColors.gold
                                    : LunoColors.textDim,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              labels[index],
                              softWrap: false,
                              style: style,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ];
          return horizontal
              ? Row(
                children: [
                  for (var index = 0; index < tabs.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: tabs[index]),
                  ],
                ],
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < tabs.length; index++) ...[
                    if (index > 0) const SizedBox(height: 6),
                    tabs[index],
                  ],
                ],
              );
        },
      ),
    );
  }
}

class InboxScreen extends StatefulWidget implements LunoAccountScopedPage {
  const InboxScreen({super.key, this.online});

  static const connectionTimeout = Duration(seconds: 12);
  final LunoOnlineService? online;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  Stream<List<Map<String, dynamic>>>? inboxStream;
  Stream<List<Map<String, dynamic>>>? notificationStream;
  final Set<String> _readOverrides = <String>{};
  int tab = 0;
  bool markingAll = false;
  bool connecting = false;
  bool showingDetails = false;
  String? error;

  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  late final String? _entryUid;
  late final int _entryRevision;
  bool get _ownsSession =>
      mounted &&
      _online.user?.uid == _entryUid &&
      _online.accountRevision == _entryRevision &&
      _online.accountFailure == null;
  bool get _canAct =>
      _ownsSession && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_connect());
    });
  }

  @override
  void dispose() {
    _requestTimeouts.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (connecting || !_canAct) return;
    if (mounted) {
      setState(() {
        connecting = true;
        error = null;
      });
    }
    try {
      final online = _online;
      await _requestTimeouts.run(online.start(), InboxScreen.connectionTimeout);
      if (!online.ready || online.user == null) {
        throw const LunoApiException('network-unavailable', 0);
      }
      if (!mounted) return;
      if (!_ownsSession) return;
      setState(() {
        inboxStream = withInitialStreamTimeout(
          online.directMessageInboxStream(),
          InboxScreen.connectionTimeout,
        );
        notificationStream = withInitialStreamTimeout(
          online.notificationsStream(),
          InboxScreen.connectionTimeout,
        );
      });
    } catch (_) {
      if (_ownsSession) {
        setState(() => error = 'connection-failed');
      }
    } finally {
      if (_ownsSession) setState(() => connecting = false);
    }
  }

  Future<void> _markAllNotificationsRead() async {
    final online = _online;
    if (!_canAct || markingAll || online.unreadNotificationCount == 0) return;
    setState(() => markingAll = true);
    try {
      final confirmedIds = await online.markAllNotificationsRead();
      if (_ownsSession) setState(() => _readOverrides.addAll(confirmedIds));
    } catch (_) {
      _toast('Bildirimler şu an işaretlenemedi.');
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  Future<void> _openNotification(Map<String, dynamic> row) async {
    final id = row['notificationId']?.toString().trim() ?? '';
    if (!_ownsSession || id.isEmpty || _isNotificationRead(row)) return;
    try {
      await _online.markNotificationRead(id);
      if (_ownsSession) setState(() => _readOverrides.add(id));
    } catch (_) {
      if (mounted) _toast('Bildirim okunamadı.');
    }
  }

  bool _isNotificationRead(Map<String, dynamic> row) {
    final id = row['notificationId']?.toString() ?? '';
    return row['read'] == true ||
        _readOverrides.contains(id) ||
        (_ownsSession && _online.notificationIsRead(id));
  }

  void _toast(String message) {
    if (_canAct) showLunoNotice(context, message);
  }

  Future<void> _showNotificationDetails(Map<String, dynamic> row) async {
    if (!_canAct || showingDetails) return;
    showingDetails = true;
    unawaited(_openNotification(row));
    try {
      await showLunoAccountBottomSheet<void>(
        context: context,
        service: _online,
        backgroundColor: LunoColors.bgPanel,
        builder:
            (sheetContext) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _notificationTitle(
                      row['type']?.toString() ?? 'general',
                      row,
                    ),
                    style: LunoType.screenTitle,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    row['message']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  LunoButton(
                    label: 'TAMAM',
                    backgroundArt: LunoAssets.actionSurfaceV27,
                    onPressed: () => dismissLunoAccountModal(sheetContext),
                  ),
                ],
              ),
            ),
      );
    } finally {
      showingDetails = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _online;
    final english = LunoLocalizations.of(context).isEnglish;
    final connectionError =
        english
            ? 'The inbox could not be opened.'
            : 'Mesaj kutusu şu an açılamıyor.';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tab == 0 ? 'BİLDİRİMLER' : 'MESAJ KUTUSU',
          style: LunoType.screenTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ListenableBuilder(
            listenable: online,
            builder:
                (context, _) =>
                    tab == 0 && online.unreadNotificationCount > 0
                        ? IconButton(
                          onPressed:
                              markingAll ? null : _markAllNotificationsRead,
                          tooltip: LunoLocalizations.of(
                            context,
                          ).translate('Tümünü okundu işaretle'),
                          icon: const Icon(Icons.done_all_rounded),
                        )
                        : const SizedBox.shrink(),
          ),
          IconButton(
            onPressed: connecting ? null : _connect,
            tooltip: english ? 'Refresh' : 'Yenile',
            icon:
                connecting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ColoredBox(
        color: LunoColors.bgDeep,
        child: _SocialViewport(
          child: ListenableBuilder(
            listenable: online,
            builder: (context, _) {
              if (inboxStream == null || notificationStream == null) {
                return Center(
                  child:
                      error == null
                          ? const CircularProgressIndicator(
                            color: LunoColors.gold,
                          )
                          : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  connectionError,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: LunoColors.textDim,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _connect,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(
                                    english ? 'TRY AGAIN' : 'TEKRAR DENE',
                                  ),
                                ),
                              ],
                            ),
                          ),
                );
              }
              return Column(
                children: [
                  if (error != null || online.lastError != null)
                    _offlineBanner(
                      error != null ? connectionError : online.lastError!,
                    ),
                  _inboxTabs(online),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: LunoMotion.adaptive(
                        context,
                        LunoMotion.panelEnter,
                      ),
                      switchInCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey(tab),
                        child:
                            tab == 0 ? _notificationsList() : _messagesList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _offlineBanner(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: LunoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: LunoColors.bgPanel2,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFB5A7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFFD6CC), fontSize: 12),
            ),
          ),
          TextButton(onPressed: _connect, child: const Text('DENE')),
        ],
      ),
    ),
  );

  Widget _inboxTabs(LunoOnlineService online) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final l = LunoLocalizations.of(context);
        final painter = TextPainter(
          text: TextSpan(
            text: l.translate('BİLDİRİMLER'),
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final vertical = painter.width > (constraints.maxWidth - 8) / 2 - 22;
        painter.dispose();
        final notifications = _inboxTab(
          id: 'notifications',
          label: 'BİLDİRİMLER',
          art: LunoAssets.settingsNotification,
          selected: tab == 0,
          badge: online.unreadNotificationCount,
          onTap: () => setState(() => tab = 0),
        );
        final messages = _inboxTab(
          id: 'messages',
          label: 'MESAJLAR',
          art: LunoAssets.friendsActionMessage,
          selected: tab == 1,
          badge: online.unreadDirectMessageCount,
          onTap: () => setState(() => tab = 1),
        );
        return vertical
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [notifications, const SizedBox(height: 8), messages],
            )
            : Row(
              children: [
                Expanded(child: notifications),
                const SizedBox(width: 8),
                Expanded(child: messages),
              ],
            );
      },
    ),
  );

  Widget _inboxTab({
    required String id,
    required String label,
    required String art,
    required bool selected,
    required int badge,
    required VoidCallback onTap,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey('inbox-tab-$id'),
      onTap:
          selected
              ? null
              : () {
                LunoFeedback.tap();
                onTap();
              },
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: LunoMotion.adaptive(context, LunoMotion.micro),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient:
              selected
                  ? const LinearGradient(
                    colors: [Color(0xFF397A80), Color(0xFF24515A)],
                  )
                  : const LinearGradient(
                    colors: [LunoColors.bgPanel2, LunoColors.bgPanel],
                  ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? LunoColors.gold : LunoColors.line,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 200 ||
                MediaQuery.textScalerOf(context).scale(13) > 18;
            final title = Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            );
            final symbol = LunoArt(art, width: 28, height: 28);
            return Semantics(
              selected: selected,
              button: true,
              child:
                  stacked
                      ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              symbol,
                              if (badge > 0) ...[
                                const SizedBox(width: 7),
                                _InboxBadge(value: badge),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          title,
                        ],
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          symbol,
                          const SizedBox(width: 7),
                          Flexible(child: title),
                          if (badge > 0) ...[
                            const SizedBox(width: 7),
                            _InboxBadge(value: badge),
                          ],
                        ],
                      ),
            );
          },
        ),
      ),
    ),
  );

  Widget _notificationsList() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: notificationStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _streamError(
          LunoLocalizations.of(context).isEnglish
              ? 'Notifications could not be refreshed.'
              : 'Bildirimler yenilenemedi.',
        );
      }
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return _emptyNotifications();
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, index) => _notificationTile(rows[index]),
      );
    },
  );

  Widget _messagesList() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: inboxStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _streamError(
          LunoLocalizations.of(context).isEnglish
              ? 'The inbox could not be refreshed.'
              : 'Mesaj kutusu yenilenemedi.',
        );
      }
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return _emptyInbox();
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, index) => _conversationTile(rows[index]),
      );
    },
  );

  Widget _streamError(String message) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LunoColors.textDim),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: connecting ? null : _connect,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              LunoLocalizations.of(context).isEnglish
                  ? 'TRY AGAIN'
                  : 'TEKRAR DENE',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyNotifications() => _inboxEmptyState(
    art: LunoAssets.settingsNotification,
    title: 'Henüz bildirim yok',
    description: 'Arkadaşlık ve maç hareketlerin burada görünecek.',
  );

  Widget _inboxEmptyState({
    required String art,
    required String title,
    required String description,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LunoArt(art, width: 96, height: 96),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: LunoColors.textDim, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _notificationTile(Map<String, dynamic> row) {
    final read = _isNotificationRead(row);
    final type = row['type']?.toString() ?? 'general';
    return LunoSurface(
      padding: EdgeInsets.zero,
      color: read ? LunoColors.bgPanel : LunoColors.bgRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _showNotificationDetails(row),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LunoColors.bgPanel2,
                  shape: BoxShape.circle,
                  border: Border.all(color: LunoColors.line),
                ),
                child: LunoArt(_notificationArt(type), width: 40, height: 40),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _notificationTitle(type, row),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row['message']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _notificationTime(row['ts']),
                      style: const TextStyle(
                        color: Color(0xFFB5CED0),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              read
                  ? const Icon(Icons.chevron_right_rounded)
                  : const LunoStatusDot(active: true),
            ],
          ),
        ),
      ),
    );
  }

  String _notificationArt(String type) => switch (type) {
    'friend_request' || 'friend_accepted' => LunoAssets.friendsTab,
    'match_invite' || 'match_invite_accepted' => LunoAssets.friendsActionBattle,
    _ => LunoAssets.settingsNotification,
  };

  String _notificationTitle(String type, Map<String, dynamic> row) {
    final name = row['fromName']?.toString().trim();
    final player = name == null || name.isEmpty ? 'Luno oyuncusu' : name;
    return switch (type) {
      'friend_request' => '$player arkadaşlık isteği',
      'friend_accepted' => 'Arkadaşlık isteği kabul edildi',
      'match_invite' => '$player maç daveti',
      'match_invite_accepted' => 'Maç daveti kabul edildi',
      _ => 'Luno bildirimi',
    };
  }

  String _notificationTime(Object? raw) {
    final timestamp = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (timestamp <= 0) return '';
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    if (age.inMinutes < 1) return 'Az önce';
    if (age.inHours < 1) return '${age.inMinutes} dk önce';
    if (age.inDays < 1) return '${age.inHours} sa önce';
    if (age.inDays < 7) return '${age.inDays} gün önce';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Widget _emptyInbox() => _inboxEmptyState(
    art: LunoAssets.friendsEmpty,
    title: 'Henüz mesaj yok',
    description: 'Arkadaşlarınla mesajlaştıkça gelen kutun burada dolacak.',
  );

  Widget _conversationTile(Map<String, dynamic> row) {
    final targetUid = row['targetUid']?.toString() ?? '';
    return LunoSurface(
      padding: const EdgeInsets.all(11),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const LunoArt(LunoAssets.statusProfile, width: 46, height: 46),
        title: Text(
          usernameFromMap(row),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          row['last']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: LunoColors.textDim),
        ),
        trailing:
            row['unread'] == true
                ? const LunoStatusDot(active: true)
                : const Icon(Icons.chevron_right_rounded),
        onTap:
            targetUid.isEmpty
                ? null
                : () {
                  if (!_canAct) return;
                  Navigator.of(context).push(
                    lunoRoute(
                      DirectMessageScreen(
                        targetUid: targetUid,
                        targetName: usernameFromMap(row),
                      ),
                    ),
                  );
                },
      ),
    );
  }
}

class _InboxBadge extends StatelessWidget {
  final int value;

  const _InboxBadge({required this.value});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE23A4A),
      shape: value > 9 ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: value > 9 ? BorderRadius.circular(8) : null,
      border: Border.all(color: Colors.white70, width: 1.4),
    ),
    child: Text(
      value > 99
          ? '99+'
          : value > 9
          ? '9+'
          : '$value',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    ),
  );
}

class DirectMessageScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  static const initialLoadTimeout = Duration(seconds: 12);
  final String targetUid;
  final String targetName;
  final LunoOnlineService? online;

  const DirectMessageScreen({
    super.key,
    required this.targetUid,
    required this.targetName,
    this.online,
  });

  @override
  State<DirectMessageScreen> createState() => _DirectMessageScreenState();
}

class _DirectMessageScreenState extends State<DirectMessageScreen>
    with WidgetsBindingObserver {
  final _ugcConsent = UgcConsent();
  final _requestTimeouts = ScreenRequestTimeouts();
  final input = TextEditingController();
  Stream<List<Map<String, dynamic>>>? messagesStream;
  bool sending = false;
  bool opening = false;
  bool _blocked = false;
  String? error;
  Timer? _readTimer;
  String _lastReadKey = '';
  String _scheduledReadKey = '';
  String? _scheduledReadMessageId;
  String _failedReadKey = '';
  int? _readInFlightRevision;
  int _readRetryCount = 0;
  int _conversationRevision = 0;
  bool _foreground = true;
  bool _sessionInvalidated = false;
  late final LunoOnlineService _entryOnline;
  late final String? _entryUid;
  late final int _entryRevision;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsSession =>
      mounted &&
      !_sessionInvalidated &&
      identical(_online, _entryOnline) &&
      _online.user?.uid == _entryUid &&
      _online.accountRevision == _entryRevision &&
      _online.accountFailure == null;
  bool get _canAct =>
      _ownsSession && ModalRoute.of(context)?.isCurrent != false;
  bool get _canRead => _canAct && _foreground;
  bool _ownsConversation(int revision, String uid) =>
      _ownsSession &&
      _conversationRevision == revision &&
      widget.targetUid == uid;

  @override
  void initState() {
    super.initState();
    _entryOnline = _online;
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _entryOnline.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  @override
  void didUpdateWidget(covariant DirectMessageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_online, _entryOnline)) _onSessionChanged();
    if (oldWidget.targetUid == widget.targetUid) return;
    _requestTimeouts.cancelPending();
    ++_conversationRevision;
    _readTimer?.cancel();
    _readTimer = null;
    _lastReadKey = '';
    _scheduledReadKey = '';
    _scheduledReadMessageId = null;
    _failedReadKey = '';
    _readInFlightRevision = null;
    _readRetryCount = 0;
    messagesStream = null;
    input.clear();
    sending = false;
    opening = false;
    _blocked = false;
    error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canAct) unawaited(_open());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entryOnline.removeListener(_onSessionChanged);
    _ugcConsent.dispose();
    _requestTimeouts.dispose();
    _readTimer?.cancel();
    input.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted || _sessionInvalidated || _ownsSession) return;
    _requestTimeouts.cancelPending();
    ++_conversationRevision;
    _readTimer?.cancel();
    _readTimer = null;
    _lastReadKey = '';
    _scheduledReadKey = '';
    _scheduledReadMessageId = null;
    _failedReadKey = '';
    _readInFlightRevision = null;
    _readRetryCount = 0;
    input.clear();
    setState(() {
      _sessionInvalidated = true;
      messagesStream = null;
      sending = false;
      opening = false;
      error = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _readTimer?.cancel();
      _readTimer = null;
      _scheduledReadKey = '';
      _scheduledReadMessageId = null;
      return;
    }
    // A new foreground visit gets a fresh bounded receipt retry budget.
    if (!wasForeground) _failedReadKey = '';
    // Revisit the current stream snapshot even if no message arrived on resume.
    if (mounted && _ownsSession) setState(() {});
  }

  Future<void> _open() async {
    if (!_canAct || opening || _blocked) {
      return;
    }
    opening = true;
    final revision = _conversationRevision;
    final targetUid = widget.targetUid;
    if (mounted) {
      setState(() {
        messagesStream = null;
        error = null;
      });
    }
    try {
      final online = _online;
      await _requestTimeouts.run(
        online.start(),
        DirectMessageScreen.initialLoadTimeout,
      );
      if (!_ownsConversation(revision, targetUid)) return;
      if (!online.ready || online.user == null) {
        throw const LunoApiException('network-unavailable', 0);
      }
      if (!mounted || !_ownsConversation(revision, targetUid)) return;
      final conversationId = await _ugcConsent.run(
        context: context,
        online: online,
        operation: () => online.openDirectMessage(targetUid),
        isRelevant: () => _ownsConversation(revision, targetUid) && !_blocked,
      );
      if (conversationId == null) {
        if (_ownsConversation(revision, targetUid) && _canAct) {
          setState(
            () =>
                error =
                    LunoLocalizations.of(context).isEnglish
                        ? 'Accept the community rules to start a conversation.'
                        : 'Konuşma başlatmak için topluluk kurallarını kabul et.',
          );
        }
        return;
      }
      if (conversationId.isEmpty) throw StateError('conversation-not-created');
      if (!_ownsConversation(revision, targetUid)) return;
      setState(
        () =>
            messagesStream = withInitialStreamTimeout(
              online.directMessagesStream(targetUid),
              DirectMessageScreen.initialLoadTimeout,
            ),
      );
    } catch (_) {
      if (_ownsConversation(revision, targetUid)) {
        setState(() => error = 'Konuşma açılamadı.');
      }
    } finally {
      if (_ownsConversation(revision, targetUid)) opening = false;
    }
  }

  Future<void> _send() async {
    if (!_canAct || _blocked) return;
    final revision = _conversationRevision;
    final targetUid = widget.targetUid;
    if (input.text.trim().isEmpty || sending || messagesStream == null) return;
    final text = normalizeUgcText(
      input.text,
      maxLength: directMessageMaxLength,
    );
    if (text == null) {
      _toast(
        ugcTextError(
          english: LunoLocalizations.of(context).isEnglish,
          bio: false,
        ),
      );
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final online = _online;
      final sent = await _ugcConsent.run(
        context: context,
        online: online,
        isRelevant: () => _ownsConversation(revision, targetUid) && !_blocked,
        operation: () async {
          if (!_ownsConversation(revision, targetUid) || !_canAct || _blocked) {
            return false;
          }
          await online.sendDirectMessage(targetUid, text);
          return true;
        },
      );
      if (sent != true) return;
      if (_ownsConversation(revision, targetUid) &&
          normalizeUgcText(input.text, maxLength: directMessageMaxLength) ==
              text) {
        input.clear();
      }
    } catch (_) {
      if (_ownsConversation(revision, targetUid) && _canAct) {
        setState(() => error = 'Mesaj gönderilemedi.');
      }
    } finally {
      if (_ownsConversation(revision, targetUid)) {
        setState(() => sending = false);
      }
    }
  }

  void _scheduleRead(List<Map<String, dynamic>> rows) {
    if (!_canRead) return;
    final key = directMessageReadKey(rows);
    if (key.isEmpty ||
        key == _lastReadKey ||
        key == _scheduledReadKey ||
        key == _failedReadKey) {
      return;
    }
    final messageId = rows.last['messageId'];
    if (messageId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(messageId)) {
      return;
    }
    _scheduledReadKey = key;
    _scheduledReadMessageId = messageId;
    _readRetryCount = 0;
    final revision = _conversationRevision;
    final targetUid = widget.targetUid;
    _readTimer?.cancel();
    _readTimer = null;
    if (_readInFlightRevision == revision) return;
    _readTimer = Timer(const Duration(milliseconds: 250), () {
      _readTimer = null;
      unawaited(_markConversationRead(key, messageId, revision, targetUid));
    });
  }

  Future<void> _markConversationRead(
    String key,
    String messageId,
    int revision,
    String targetUid,
  ) async {
    if (!_ownsConversation(revision, targetUid)) return;
    if (!_canRead) {
      if (_scheduledReadKey == key) {
        _scheduledReadKey = '';
        _scheduledReadMessageId = null;
      }
      return;
    }
    if (_scheduledReadKey != key) return;
    if (_readInFlightRevision == revision) return;
    _readInFlightRevision = revision;
    try {
      final marked = await _online.markDirectMessageRead(
        targetUid,
        lastMessageId: messageId,
      );
      if (!mounted ||
          !_ownsConversation(revision, targetUid) ||
          _scheduledReadKey != key) {
        return;
      }
      if (!marked) {
        if (!_canRead || _readRetryCount >= 1) {
          // A stale cursor is not a failed or acknowledged snapshot.
          _scheduledReadKey = '';
          _scheduledReadMessageId = null;
          _readRetryCount = 0;
          return;
        }
        _readRetryCount += 1;
        _readTimer?.cancel();
        _readTimer = Timer(const Duration(seconds: 2), () {
          _readTimer = null;
          unawaited(_markConversationRead(key, messageId, revision, targetUid));
        });
        return;
      }
      _lastReadKey = key;
      _scheduledReadKey = '';
      _scheduledReadMessageId = null;
      _readRetryCount = 0;
    } catch (_) {
      if (!mounted ||
          !_ownsConversation(revision, targetUid) ||
          _scheduledReadKey != key) {
        return;
      }
      if (!_canRead || _readRetryCount >= 1) {
        if (_readRetryCount >= 1) _failedReadKey = key;
        _scheduledReadKey = '';
        _scheduledReadMessageId = null;
        return;
      }
      _readRetryCount += 1;
      _readTimer?.cancel();
      _readTimer = Timer(const Duration(seconds: 2), () {
        _readTimer = null;
        unawaited(_markConversationRead(key, messageId, revision, targetUid));
      });
    } finally {
      if (_ownsConversation(revision, targetUid) &&
          _readInFlightRevision == revision) {
        _readInFlightRevision = null;
        // Only the latest snapshot remains queued while a receipt is in flight.
        final pendingKey = _scheduledReadKey;
        final pendingMessageId = _scheduledReadMessageId;
        if (pendingKey.isNotEmpty &&
            pendingKey != key &&
            pendingMessageId != null &&
            _canRead) {
          _readTimer?.cancel();
          _readTimer = Timer(const Duration(milliseconds: 250), () {
            _readTimer = null;
            unawaited(
              _markConversationRead(
                pendingKey,
                pendingMessageId,
                revision,
                targetUid,
              ),
            );
          });
        } else if (pendingKey != key && !_canRead) {
          _scheduledReadKey = '';
          _scheduledReadMessageId = null;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _online;
    if (_sessionInvalidated) {
      final english = LunoLocalizations.of(context).isEnglish;
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            english
                ? 'Your session has ended. Reopen this screen after signing in.'
                : 'Oturumun kapandı. Giriş yaptıktan sonra bu ekranı yeniden aç.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          widget.targetName,
          localize: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LunoType.screenTitle,
        ),
        actions: [
          SocialSafetyActions(
            online: online,
            targetUid: widget.targetUid,
            onBlocked: (target) {
              if (!_ownsSession || target != widget.targetUid) return;
              _requestTimeouts.cancelPending();
              ++_conversationRevision;
              _readTimer?.cancel();
              _readTimer = null;
              input.clear();
              setState(() {
                _blocked = true;
                messagesStream = null;
                opening = false;
                sending = false;
                error =
                    LunoLocalizations.of(context).isEnglish
                        ? 'Player blocked. Manage blocked players in Settings.'
                        : 'Oyuncu engellendi. Engellenen oyuncuları ayarlardan yönetebilirsin.';
              });
            },
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xFF0F2124),
        child: _SocialViewport(
          child: Column(
            children: [
              Expanded(
                child:
                    messagesStream == null
                        ? Center(
                          child:
                              error == null
                                  ? const CircularProgressIndicator(
                                    color: LunoColors.gold,
                                  )
                                  : SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            LunoLocalizations.of(
                                                      context,
                                                    ).isEnglish &&
                                                    !_blocked
                                                ? 'The conversation could not be opened.'
                                                : error!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: LunoColors.textDim,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if (!_blocked)
                                            OutlinedButton.icon(
                                              onPressed: opening ? null : _open,
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                              ),
                                              label: Text(
                                                LunoLocalizations.of(
                                                      context,
                                                    ).isEnglish
                                                    ? 'TRY AGAIN'
                                                    : 'YENİDEN DENE',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                        )
                        : StreamBuilder<List<Map<String, dynamic>>>(
                          stream: messagesStream,
                          builder: (context, snapshot) {
                            final rows = snapshot.data ?? const [];
                            if (snapshot.hasError) {
                              return Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        LunoLocalizations.of(context).isEnglish
                                            ? 'Messages could not be loaded.'
                                            : 'Mesajlar yüklenemedi.',
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: opening ? null : _open,
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: Text(
                                          LunoLocalizations.of(
                                                context,
                                              ).isEnglish
                                              ? 'TRY AGAIN'
                                              : 'YENİDEN DENE',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            if (!snapshot.hasData &&
                                snapshot.connectionState ==
                                    ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: LunoColors.gold,
                                ),
                              );
                            }
                            if (rows.isEmpty) {
                              return Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const LunoArt(
                                        LunoAssets.friendsActionMessage,
                                        width: 72,
                                        height: 72,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        LunoLocalizations.of(context).isEnglish
                                            ? 'Start the conversation.'
                                            : 'Konuşmayı başlat.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: LunoColors.textDim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            _scheduleRead(rows);
                            return ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: rows.length,
                              itemBuilder: (_, index) {
                                final row = rows[index];
                                final mine = row['from'] == online.user?.uid;
                                return Align(
                                  alignment:
                                      mine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                  child: Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          (MediaQuery.sizeOf(context).width
                                                  .clamp(0.0, 760.0)
                                                  .toDouble() -
                                              28) *
                                          .88,
                                    ),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          mine
                                              ? const Color(0xFF24545A)
                                              : LunoColors.bgPanel2,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            mine
                                                ? LunoColors.teal.withValues(
                                                  alpha: .45,
                                                )
                                                : LunoColors.line,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          row['text']?.toString() ?? '',
                                          localize: false,
                                          style: const TextStyle(
                                            color: LunoColors.ivory,
                                            fontSize: 15,
                                            height: 1.4,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (!mine && row['messageId'] is String)
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: SocialSafetyActions(
                                              key: ValueKey((
                                                widget.targetUid,
                                                row['messageId'],
                                              )),
                                              online: online,
                                              targetUid: widget.targetUid,
                                              messageId:
                                                  row['messageId'] as String,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
              ),
              if (error != null && messagesStream != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    error!,
                    style: const TextStyle(color: LunoColors.danger),
                  ),
                ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF152F33),
                  border: Border(top: BorderSide(color: LunoColors.line)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            enabled: !_blocked,
                            controller: input,
                            minLines: 1,
                            maxLines: 3,
                            scrollPadding: const EdgeInsets.only(bottom: 96),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: LunoLocalizations.of(
                                context,
                              ).translate('Mesaj yaz...'),
                              filled: true,
                              fillColor: LunoColors.bgPanel2,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: input,
                          builder:
                              (context, value, _) => IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF397C88),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed:
                                    sending ||
                                            messagesStream == null ||
                                            value.text.trim().isEmpty
                                        ? null
                                        : () {
                                          LunoFeedback.tap();
                                          _send();
                                        },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Gönder'),
                                icon:
                                    sending
                                        ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: LunoColors.gold,
                                          ),
                                        )
                                        : const Icon(Icons.send_rounded),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class SettingsScreen extends StatefulWidget implements LunoAccountScopedPage {
  const SettingsScreen({super.key, this.online, this.settings});
  final LunoOnlineService? online;
  final LunoSettings? settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  LunoSettings get settings => widget.settings ?? LunoSettings.instance;
  bool linkingGoogle = false;
  bool restoringGoogle = false;
  bool deletingAccount = false;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  late final (String?, int) _entryOwner;
  bool get _canAct =>
      mounted &&
      _entryOwner == (online.user?.uid, online.accountRevision) &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _entryOwner = (online.user?.uid, online.accountRevision);
    unawaited(settings.load());
  }

  @override
  void dispose() {
    _requestTimeouts.dispose();
    super.dispose();
  }

  Future<void> _linkGoogle() async {
    if (!_canAct || linkingGoogle || restoringGoogle || deletingAccount) {
      return;
    }
    final l10n = LunoLocalizations(Locale(settings.languageCode));
    final linkingUid = online.user?.uid;
    final linkingRevision = online.accountRevision;
    bool canNotify() =>
        mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        online.user?.uid == linkingUid &&
        online.accountRevision == linkingRevision;
    setState(() => linkingGoogle = true);
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      if (!_canAct || !canNotify()) return;
      await online.linkGoogle();
      if (mounted && canNotify()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.googleLinked)));
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted || !canNotify()) return;
      if (const {
        'credential-already-in-use',
        'email-already-in-use',
        'account-exists-with-different-credential',
      }.contains(error.code)) {
        setState(() => linkingGoogle = false);
        await showGoogleAccountRestore(
          context: context,
          online: online,
          english: settings.languageCode == 'en',
          onBusyChanged: (value) {
            if (mounted) setState(() => restoringGoogle = value);
          },
        );
        return;
      }
      final message = switch (error.code) {
        'cancelled' ||
        'popup-closed-by-user' ||
        'web-context-canceled' => l10n.googleCancelled,
        'credential-already-in-use' ||
        'email-already-in-use' ||
        'account-exists-with-different-credential' => l10n.googleAlreadyLinked,
        'operation-not-allowed' => l10n.googleNotEnabled,
        _ => l10n.googleRetry,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on LunoApiException catch (error) {
      if (!mounted || !canNotify()) return;
      final message =
          error.code == 'account-link-in-progress'
              ? l10n.linkInProgress
              : l10n.secureLinkRetry;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted && canNotify()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.googleRetry)));
      }
    } finally {
      if (mounted) setState(() => linkingGoogle = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (!_canAct || linkingGoogle || restoringGoogle || deletingAccount) {
      return;
    }
    setState(() => deletingAccount = true);
    final english = settings.languageCode == 'en';
    final uid = online.user?.uid;
    final revision = online.accountRevision;
    try {
      final accepted = await showLunoAccountDialog<bool>(
        context: context,
        service: online,
        allowAccountDeletion: true,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(english ? 'Delete account?' : 'Hesap silinsin mi?'),
              content: SingleChildScrollView(
                child: Text(
                  english
                      ? 'Your profile, progress, collection and social data will be deleted. This cannot be undone. Purchase records may be retained where required by law.\n\nDeleting your account does not cancel your Google Play subscription. Cancel it separately in Google Play to stop future renewals.'
                      : 'Profilin, ilerlemen, koleksiyonun ve sosyal verilerin silinecek. Bu işlem geri alınamaz. Satın alma kayıtları yasal zorunluluklar kapsamında saklanabilir.\n\nHesabını silmek Google Play aboneliğini iptal etmez. Gelecek yenilemeleri durdurmak için aboneliğini Google Play üzerinden ayrıca iptal et.',
                ),
              ),
              actions: [
                TextButton.icon(
                  key: const ValueKey('delete-account-manage-subscription'),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(
                    english ? 'Manage subscription' : 'Aboneliği yönet',
                  ),
                  onPressed: () async {
                    if (!dialogContext.mounted ||
                        online.user?.uid != uid ||
                        online.accountRevision != revision ||
                        ModalRoute.of(dialogContext)?.isCurrent != true) {
                      return;
                    }
                    final opened =
                        await LegalLinkService.openPlaySubscriptions();
                    if (!opened &&
                        dialogContext.mounted &&
                        mounted &&
                        online.user?.uid == uid &&
                        online.accountRevision == revision) {
                      showLunoNotice(
                        dialogContext,
                        english
                            ? 'Google Play could not open. Open Play Store > Payments and subscriptions > Subscriptions.'
                            : 'Google Play açılamadı. Play Store > Ödemeler ve abonelikler > Abonelikler bölümünü aç.',
                      );
                    }
                  },
                ),
                TextButton(
                  onPressed:
                      () => dismissLunoAccountModal(dialogContext, false),
                  child: Text(english ? 'Cancel' : 'Vazgeç'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: LunoColors.danger,
                  ),
                  icon: const Icon(Icons.delete_forever_rounded),
                  onPressed: () => dismissLunoAccountModal(dialogContext, true),
                  label: Text(
                    english ? 'Delete permanently' : 'Kalıcı olarak sil',
                  ),
                ),
              ],
            ),
      );
      if (accepted != true ||
          !mounted ||
          online.user?.uid != uid ||
          online.accountRevision != revision ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final deletedUid = await online.deleteAccount(confirmed: true);
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          (online.user != null && online.user?.uid != deletedUid)) {
        return;
      }
      showLunoNotice(
        context,
        english ? 'Account deleted.' : 'Hesabın silindi.',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          online.user?.uid != uid ||
          online.accountRevision != revision) {
        return;
      }
      final message = switch (error) {
        FirebaseAuthException(code: 'cancelled' || 'popup-closed-by-user') =>
          english
              ? 'Verification cancelled. Your account was not deleted.'
              : 'Doğrulama iptal edildi. Hesabın silinmedi.',
        LunoApiException(
          code: 'reauth-required' || 'reauth-provider-unavailable',
        ) =>
          english
              ? 'Verify your linked Google account and try again.'
              : 'Bağlı Google hesabını doğrulayıp tekrar dene.',
        LunoApiException(code: 'account-deletion-in-progress') =>
          english
              ? 'Deletion is in progress. Tap Delete account again to finish.'
              : 'Silme işlemi sürüyor. Tamamlamak için Hesabımı sil seçeneğine tekrar dokun.',
        LunoApiException(code: 'account-deletion-local-cleanup') =>
          english
              ? 'Your account was deleted. Tap Delete account again to finish device cleanup.'
              : 'Hesabın silindi. Cihazdaki temizliği tamamlamak için Hesabımı sil seçeneğine tekrar dokun.',
        LunoApiException(code: 'account-deletion-signout-pending') =>
          english
              ? 'Your account was deleted. Tap Delete account again to finish signing out.'
              : 'Hesabın silindi. Oturumu kapatmak için Hesabımı sil seçeneğine tekrar dokun.',
        _ =>
          english
              ? 'Deletion could not be confirmed. Try again.'
              : 'Hesap silme işlemi doğrulanamadı. Tekrar dene.',
      };
      showLunoNotice(context, message);
    } finally {
      if (mounted) setState(() => deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final l10n = LunoLocalizations(Locale(settings.languageCode));
        return Scaffold(
          appBar: AppBar(title: Text(l10n.settingsTitle)),
          body: LunoBackdrop(
            art: LunoAssets.settingsSceneV27,
            overlay: const Color(0x50101616),
            focalPoint: const Alignment(0, .15),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _SettingsLabel(l10n.soundAndDisplay),
                LunoSurface(
                  color: LunoColors.bgPanel,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      _levelControl(
                        title: l10n.effectsVolume,
                        art: LunoAssets.settingsSound,
                        value: settings.effectsLevel,
                        onChanged: (value) {
                          unawaited(settings.setEffectsLevel(value));
                        },
                      ),
                      const Divider(height: 18),
                      _levelControl(
                        title: l10n.musicVolume,
                        art: LunoAssets.settingsMusic,
                        value: settings.musicLevel,
                        onChanged: (value) {
                          unawaited(settings.setMusicLevel(value));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsLabel(l10n.preferences),
                LunoSurface(
                  color: LunoColors.bgPanel,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final stacked =
                              box.maxWidth < 360 ||
                              MediaQuery.textScalerOf(context).scale(16) > 19.2;
                          final picker = DropdownButton<String>(
                            value: settings.language,
                            isExpanded: stacked,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: LunoSettings.languageTurkish,
                                child: Text(LunoSettings.languageTurkish),
                              ),
                              DropdownMenuItem(
                                value: LunoSettings.languageEnglish,
                                child: Text(LunoSettings.languageEnglish),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                unawaited(settings.setLanguage(value));
                              }
                            },
                          );
                          return ListTile(
                            leading: LunoArt(
                              settings.language == LunoSettings.languageEnglish
                                  ? LunoAssets.settingsLanguageEn
                                  : LunoAssets.settingsLanguageTr,
                              width: 34,
                              height: 34,
                            ),
                            title: Text(l10n.language),
                            trailing: stacked ? null : picker,
                            subtitle:
                                stacked
                                    ? Align(
                                      alignment: Alignment.centerLeft,
                                      child: picker,
                                    )
                                    : null,
                          );
                        },
                      ),
                      _switch(
                        l10n.vibration,
                        LunoAssets.settingsVibration,
                        settings.vibrationEnabled,
                        (value) {
                          unawaited(settings.setVibrationEnabled(value));
                        },
                      ),
                    ],
                  ),
                ),
                if (settings.dirty && settings.saveFailure != null)
                  ListTile(
                    key: const ValueKey('settings-save-failure'),
                    title: Text(
                      settings.languageCode == 'en'
                          ? 'Settings are not saved on this device.'
                          : 'Ayarlar bu cihazda kaydedilemedi.',
                    ),
                    subtitle: Text(
                      settings.languageCode == 'en'
                          ? 'Your current choices remain active.'
                          : 'Mevcut seçimlerin geçerli olmaya devam ediyor.',
                    ),
                    trailing: IconButton(
                      key: const ValueKey('settings-save-retry'),
                      tooltip:
                          settings.languageCode == 'en'
                              ? 'Retry saving'
                              : 'Kaydetmeyi yeniden dene',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed:
                          settings.saving
                              ? null
                              : () {
                                if (_canAct) unawaited(settings.retrySave());
                              },
                    ),
                  ),
                const SizedBox(height: 14),
                _SettingsLabel(l10n.account),
                LunoSurface(
                  color: LunoColors.bgPanel,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const LunoArt(
                          LunoAssets.settingsGame,
                          width: 34,
                          height: 34,
                        ),
                        title: Text(
                          linkingGoogle ? l10n.googleLinking : l10n.googleLink,
                        ),
                        subtitle: Text(
                          l10n.googleSubtitle,
                          style: TextStyle(color: LunoColors.textDim),
                        ),
                        onTap:
                            linkingGoogle || restoringGoogle || deletingAccount
                                ? null
                                : _linkGoogle,
                        trailing:
                            linkingGoogle
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.chevron_right_rounded),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GoogleAccountRestoreButton(
                          online: online,
                          english: settings.languageCode == 'en',
                          disabled: linkingGoogle || deletingAccount,
                          onBusyChanged: (value) {
                            if (mounted) setState(() => restoringGoogle = value);
                          },
                        ),
                      ),
                      ListTile(
                        leading: const LunoArt(
                          LunoAssets.settingsGuide,
                          width: 34,
                          height: 34,
                        ),
                        title: Text(l10n.replayGuide),
                        onTap: () {
                          if (!_canAct) return;
                          Navigator.of(
                            context,
                          ).push(lunoRoute(const TutorialScreen()));
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(
                          settings.languageCode == 'en'
                              ? 'Blocked players'
                              : 'Engellenen oyuncular',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          if (!_canAct) return;
                          Navigator.of(context).push(
                            lunoRoute(
                              LunoAccountScope(
                                service: online,
                                page: BlockedPlayersScreen(online: online),
                              ),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        key: const ValueKey('product-privacy-settings'),
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: Text(
                          settings.languageCode == 'en'
                              ? 'Privacy choices'
                              : 'Veri tercihleri',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          if (!_canAct) return;
                          unawaited(
                            showProductPrivacySettings(
                              context: context,
                              store: GameStore.instance,
                              online: online,
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const LunoArt(
                          LunoAssets.settingsSignout,
                          width: 34,
                          height: 34,
                        ),
                        title: Text(
                          l10n.signOut,
                          style: TextStyle(color: LunoColors.danger),
                        ),
                        onTap: _showGuestAccountInfo,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.delete_forever_rounded,
                          color: LunoColors.danger,
                        ),
                        title: Text(
                          settings.languageCode == 'en'
                              ? 'Delete account'
                              : 'Hesabımı sil',
                          style: TextStyle(color: LunoColors.danger),
                        ),
                        onTap:
                            linkingGoogle || restoringGoogle || deletingAccount
                                ? null
                                : _deleteAccount,
                        trailing:
                            deletingAccount
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.chevron_right_rounded),
                      ),
                      ListTile(
                        key: const ValueKey('settings-licenses'),
                        leading: const Icon(Icons.description_outlined),
                        title: Text(settings.languageCode == 'en'
                            ? 'Open-source licenses' : 'Açık kaynak lisansları'),
                        onTap: () {
                          if (!_canAct) return;
                          showLicensePage(context: context, applicationName: 'LUNO Chess');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _switch(
    String title,
    String art,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    secondary: LunoArt(art, width: 34, height: 34),
    title: Text(title),
    value: value,
    onChanged: onChanged,
    activeThumbColor: LunoColors.gold,
    contentPadding: EdgeInsets.zero,
  );

  Widget _levelControl({
    required String title,
    required String art,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final l10n = LunoLocalizations(Locale(settings.languageCode));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LunoArt(art, width: 34, height: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 400 ||
                  MediaQuery.textScalerOf(context).scale(16) > 20;
              final labels = [
                settings.languageCode == 'en' ? 'OFF' : 'KAPALI',
                l10n.low,
                l10n.medium,
                l10n.high,
              ];
              final control = SegmentedButton<int>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(
                      horizontal: compact ? 2 : 8,
                      vertical: 19,
                    ),
                  ),
                  visualDensity: VisualDensity.standard,
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.selected)
                            ? LunoColors.goldDeep
                            : Colors.transparent,
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  side: const WidgetStatePropertyAll(
                    BorderSide(color: LunoColors.bgPanel2),
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.selected)
                            ? LunoColors.bgDeep
                            : LunoColors.ivory,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'Nunito',
                      fontFamilyFallback: const ['SpectralTurkish'],
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                segments: [
                  for (var index = 0; index < labels.length; index++)
                    ButtonSegment(value: index, label: Text(labels[index])),
                ],
                selected: {value.clamp(0, 3)},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) onChanged(selection.first);
                },
              );
              if (!compact) return control;
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: LunoColors.bgPanel2),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Wrap(
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      SizedBox(
                        width: constraints.maxWidth / 2 - 1,
                        child: Semantics(
                          button: true,
                          selected: value == index,
                          label: '$title: ${labels[index]}',
                          child: InkWell(
                            onTap: () => onChanged(index),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 48),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    value == index
                                        ? LunoColors.goldDeep
                                        : Colors.transparent,
                                border: Border(
                                  right:
                                      index.isOdd
                                          ? BorderSide.none
                                          : const BorderSide(
                                            color: LunoColors.bgPanel2,
                                          ),
                                  bottom:
                                      index < 2
                                          ? const BorderSide(
                                            color: LunoColors.bgPanel2,
                                          )
                                          : BorderSide.none,
                                ),
                              ),
                              child: Text(
                                labels[index],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      value == index
                                          ? LunoColors.bgDeep
                                          : LunoColors.ivory,
                                  fontFamily: 'Nunito',
                                  fontFamilyFallback: const ['SpectralTurkish'],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showGuestAccountInfo() async {
    if (!_canAct) return;
    final l10n = LunoLocalizations(Locale(settings.languageCode));
    await showLunoAccountDialog<void>(
      context: context,
      service: online,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.guestAccount),
            content: Text(l10n.guestDescription),
            actions: [
              TextButton(
                onPressed: () => dismissLunoAccountModal(dialogContext),
                child: Text(l10n.ok),
              ),
            ],
          ),
    );
  }
}

class EditProfileScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const EditProfileScreen({super.key, this.online, this.playerStore});

  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  final _ugcConsent = UgcConsent();
  static const countryLabels = <String, String>{
    'TR': 'Türkiye',
    'US': 'United States',
    'GB': 'United Kingdom',
    'DE': 'Deutschland',
    'FR': 'France',
    'IT': 'Italia',
    'ES': 'Espana',
    'NL': 'Nederland',
    'RU': 'Rossiya',
    'JP': 'Japan',
    'CN': 'China',
    'KR': 'South Korea',
    'BR': 'Brasil',
    'AR': 'Argentina',
    'MX': 'Mexico',
    'IN': 'India',
    'AU': 'Australia',
    'CA': 'Canada',
    'PL': 'Polska',
    'SE': 'Sverige',
    'NO': 'Norge',
    'FI': 'Suomi',
    'DK': 'Danmark',
    'GR': 'Ellada',
    'PT': 'Portugal',
    'BE': 'Belgique',
    'CH': 'Schweiz',
    'AT': 'Osterreich',
    'IE': 'Ireland',
    'UA': 'Ukraine',
    'AZ': 'Azerbaijan',
    'SA': 'Saudi Arabia',
    'AE': 'United Arab Emirates',
    'EG': 'Egypt',
    'ZA': 'South Africa',
  };
  late final TextEditingController bio;
  String country = 'TR';
  String avatar = 'av_pawn';
  bool saving = false;
  String? _bioError;
  late final AccountOperationGuard editorOwner;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsEditor =>
      identical(store, editorOwner.store) &&
      identical(online, editorOwner.online) &&
      editorOwner.isCurrent;

  @override
  void initState() {
    super.initState();
    editorOwner = AccountOperationGuard(store, online);
    bio = TextEditingController(text: store.data.bio);
    final savedCountry = store.data.country.toUpperCase();
    country = countryLabels.containsKey(savedCountry) ? savedCountry : 'TR';
    avatar = store.data.avatarEmoji;
  }

  @override
  void dispose() {
    _ugcConsent.dispose();
    _requestTimeouts.dispose();
    bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false || saving) {
      return;
    }
    final english = LunoLocalizations.of(context).isEnglish;
    if (!_ownsEditor) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english
                ? 'Your account changed. Reopen the profile editor.'
                : 'Hesabın değişti. Profil düzenleyicisini yeniden aç.',
          ),
        ),
      );
      return;
    }
    final biography = normalizeUgcText(
      bio.text,
      maxLength: bioMaxLength,
      allowEmpty: true,
    );
    if (biography == null) {
      setState(() => _bioError = ugcTextError(english: english, bio: true));
      return;
    }
    final submitted = <String, String>{
      'country': country,
      'avatarEmoji': avatar,
      'bio': biography,
    };
    setState(() {
      saving = true;
      _bioError = null;
    });
    var synced = false;
    var declined = false;
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      if (!_ownsEditor) return;
      if (online.isOnline) {
        final result = await _ugcConsent.run(
          context: context,
          online: online,
          playerStore: store,
          isRelevant: () => _ownsEditor,
          operation: () => online.updateProfile(submitted),
        );
        if (result == null) {
          declined = true;
        } else {
          if (!_ownsEditor) return;
          store.applyServerState(
            validateProfileUpdateResult(result, submitted),
          );
          if (!_ownsEditor) return;
          synced = true;
        }
      }
    } on LunoApiException catch (error) {
      if (error.code == 'invalid-bio' && mounted && _ownsEditor) {
        setState(() => _bioError = ugcTextError(english: english, bio: true));
      }
    } catch (_) {
      // Do not close the editor when the remote write failed: a local-only
      // bio is not visible to friends and must not look like a completed save.
    } finally {
      if (mounted) setState(() => saving = false);
    }
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!_ownsEditor) return;
    if (!synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            declined
                ? (english
                    ? 'Accept the community rules before publishing your bio.'
                    : 'Biyografini yayınlamadan önce topluluk kurallarını kabul et.')
                : english
                ? 'Your profile could not be saved. Check your connection and try again.'
                : 'Profil sunucuya kaydedilemedi. Bağlantıyı kontrol edip tekrar dene.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(english ? 'Profile updated.' : 'Profil güncellendi.'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const avatars = [
      'av_pawn',
      'av_knight',
      'av_bishop',
      'av_rook',
      'av_queen',
      'av_king',
      'av_robot',
      'av_robotcrown',
      'av_crown',
      'av_lightning',
      'av_fire',
    ];
    final english = LunoLocalizations.of(context).isEnglish;
    final avatarNames =
        english
            ? const [
              'Pawn',
              'Knight',
              'Bishop',
              'Rook',
              'Queen',
              'King',
              'Robot',
              'Robot King',
              'Crown',
              'Lightning',
              'Flame',
            ]
            : const [
              'Piyon',
              'At',
              'Fil',
              'Kale',
              'Vezir',
              'Şah',
              'Robot',
              'Robot Kral',
              'Taç',
              'Yıldırım',
              'Alev',
            ];
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight:
            (MediaQuery.textScalerOf(context).scale(17) * 2.3 + 16)
                .clamp(56.0, 104.0)
                .toDouble(),
        title: Text(
          english ? 'EDIT PROFILE' : 'PROFİLİ DÜZENLE',
          style: LunoType.screenTitle,
          maxLines: 2,
        ),
        actions: [
          IconButton(
            onPressed: saving ? null : _save,
            tooltip: english ? 'Save' : 'Kaydet',
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: ColoredBox(
        color: LunoColors.bgDeep,
        child: _SocialViewport(
          maxWidth: 640,
          child: SafeArea(
            top: false,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _ProfileIdentityPreview(
                  avatar: avatar,
                  username: store.data.username,
                  avatarName:
                      avatars.contains(avatar)
                          ? avatarNames[avatars.indexOf(avatar)]
                          : 'Avatar',
                ),
                const SizedBox(height: 24),
                _ProfileFieldHeading(
                  label: english ? 'PLAYER DETAILS' : 'OYUNCU BİLGİLERİ',
                  art: LunoAssets.profileCrest,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const ValueKey('edit-profile-country'),
                  initialValue: country,
                  isDense: false,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: InputDecoration(
                    labelText: english ? 'Country' : 'Ülke',
                    filled: true,
                    fillColor: const Color(0xFF172A2C),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items:
                      countryLabels.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  entry.value,
                                  localize: false,
                                  style: const TextStyle(fontSize: 14),
                                  maxLines: 2,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged:
                      saving
                          ? null
                          : (value) {
                            if (value != null) setState(() => country = value);
                          },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: bio,
                  readOnly: saving,
                  maxLength: bioMaxLength,
                  minLines: 3,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 160),
                  decoration: InputDecoration(
                    labelText: english ? 'Bio' : 'Biyo',
                    errorText: _bioError,
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFF172A2C),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ProfileFieldHeading(
                  label: english ? 'AVATAR ICON' : 'AVATAR İKONU',
                  art: LunoAssets.profileGallery,
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: avatars.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent:
                        180 +
                        (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                                .clamp(0, 2) *
                            120,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent:
                        96 + MediaQuery.textScalerOf(context).scale(14) * 3.2,
                  ),
                  itemBuilder: (_, index) {
                    final selected = avatar == avatars[index];
                    return Semantics(
                      selected: selected,
                      button: true,
                      label: avatarNames[index],
                      child: Material(
                        color:
                            selected ? LunoColors.bgRaised : LunoColors.bgPanel,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color:
                                selected
                                    ? LunoColors.gold
                                    : LunoColors.bgPanel2,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap:
                              saving
                                  ? null
                                  : () =>
                                      setState(() => avatar = avatars[index]),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 68,
                                  height: 68,
                                  child: LunoArt(
                                    LunoAssets.avatar(avatars[index]),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  avatarNames[index],
                                  key: ValueKey(
                                    'profile-avatar-label-${avatars[index]}',
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        selected
                                            ? LunoColors.gold
                                            : LunoColors.ivory,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(english ? 'SAVE' : 'KAYDET'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileIdentityPreview extends StatelessWidget {
  const _ProfileIdentityPreview({
    required this.avatar,
    required this.username,
    required this.avatarName,
  });

  final String avatar;
  final String username;
  final String avatarName;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: LunoColors.gold.withValues(alpha: .35)),
      ),
    ),
    child: Column(
      children: [
        Container(
          width: 104,
          height: 104,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF172A2C),
            shape: BoxShape.circle,
            border: Border.all(color: LunoColors.gold, width: 2),
          ),
          child: LunoArt(LunoAssets.avatar(avatar), width: 88, height: 88),
        ),
        const SizedBox(height: 12),
        Text(
          username,
          localize: false,
          textAlign: TextAlign.center,
          style: LunoType.screenTitle,
        ),
        const SizedBox(height: 4),
        Text(
          avatarName,
          localize: false,
          textAlign: TextAlign.center,
          style: LunoType.bodyMuted,
        ),
      ],
    ),
  );
}

class _ProfileFieldHeading extends StatelessWidget {
  const _ProfileFieldHeading({required this.label, required this.art});
  final String label;
  final String art;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      LunoArt(art, width: 28, height: 28),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: LunoType.sectionTitle)),
    ],
  );
}

class _CollectionHeader extends StatelessWidget {
  final int score;
  final int owned;
  const _CollectionHeader({required this.score, required this.owned});
  @override
  Widget build(BuildContext context) => Container(
    color: LunoColors.bgPanel,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        const SizedBox(
          width: 42,
          height: 42,
          child: LunoArt(LunoAssets.collection),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LunoLocalizations.of(context).isEnglish
                    ? 'LEGACY CARD ARCHIVE'
                    : 'ESKİ KART ARŞİVİ',
                style: const TextStyle(
                  color: LunoColors.gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                LunoLocalizations.of(context).isEnglish
                    ? '$owned/29 archived · $score historical points'
                    : '$owned/29 arşiv · $score geçmiş puan',
                style: const TextStyle(color: LunoColors.textDim, fontSize: 11),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: LunoColors.gold),
      ],
    ),
  );
}

class _Tabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(const TextStyle(fontWeight: FontWeight.w700, fontSize: 12));
    var minimumWidth = 48.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: l.translate(label), style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width + 12 > minimumWidth) minimumWidth = painter.width + 12;
      painter.dispose();
    }
    return Container(
      color: LunoColors.bgPanel,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth / labels.length).clamp(
            minimumWidth,
            double.infinity,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      selected: selected == i,
                      button: true,
                      child: InkWell(
                        onTap:
                            selected == i
                                ? null
                                : () {
                                  LunoFeedback.tap();
                                  onChanged(i);
                                },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: LunoMotion.adaptive(
                            context,
                            LunoMotion.micro,
                          ),
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: LunoColors.bgPanel,
                            image: lunoFace(
                              selected == i
                                  ? LunoVisualAssets.selected
                                  : LunoVisualAssets.inactive,
                              button: true,
                              opacity: selected == i ? 1 : .65,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  selected == i
                                      ? LunoColors.gold
                                      : LunoColors.textDim,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  final String text;
  const _SettingsLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: LunoColors.gold,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    ),
  );
}
