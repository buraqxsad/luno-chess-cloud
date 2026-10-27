import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import '../theme/luno_visual_assets.dart';
import '../widgets/luno_polish.dart';
import '../widgets/resource_amount.dart';

import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/battle_learning_copy.dart';
import '../models/game_store.dart';
import '../models/player_data.dart';
import '../data/rank_catalog.dart';
import '../services/luno_online_service.dart';
import '../services/luno_audio_service.dart';
import '../services/first_session_telemetry.dart';
import '../services/account_operation_guard.dart';
import '../engine/ai.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../navigation/luno_route.dart';
import '../navigation/luno_account_modal.dart';
import 'legacy_parity_screens.dart';
import 'native_hubs_screen.dart';
import 'pass_screen.dart';
import 'parity_extra_screens.dart';
import 'play_mode_screen.dart';
import 'profile_screen.dart';
import 'shop_screen.dart';
import 'battle_v1_screen.dart';
import 'battle_practice_campaign.dart';
import '../navigation/online_match_recovery.dart';

/// HTML sürümündeki son ana menünün native Flutter karşılığı.
/// Görsel navigasyon taşları aynı asset ailesinden, hareketler hafif ve
/// ekranın altındaki güvenli alanı hesaba katar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.online});
  final LunoOnlineService? online;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _onlineTimer;
  final _closed = Completer<void>();
  bool _recoveryAttempted = false;
  late final int _entryAccountRevision;
  bool _foreground = true;
  bool _preparingBattle = false;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;

  bool get _canNavigate =>
      mounted &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      _entryAccountRevision == GameStore.instance.accountBindingRevision &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _entryAccountRevision = GameStore.instance.accountBindingRevision;
    unawaited(LunoAudioService.instance.setScene(LunoMusicScene.menu));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FirstSessionTelemetry.forStore(
        GameStore.instance,
      ).record(FirstSessionEvent.homeFirstSeen, _entryAccountRevision);
      // Firebase starts after the first home frame, never during launch.
      _onlineTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) unawaited(_startOnlineAndRecoverMatch());
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onlineTimer?.cancel();
    _closed.complete();
    super.dispose();
  }

  Future<T> _withHomeDeadline<T>(Future<T> operation, Duration duration) async {
    final timeout = Completer<T>();
    final timer = Timer(
      duration,
      () => timeout.completeError(TimeoutException('Home recovery deadline')),
    );
    try {
      return await Future.any<T>([
        operation,
        timeout.future,
        _closed.future.then<T>((_) => throw StateError('Home recovery closed')),
      ]);
    } finally {
      timer.cancel();
    }
  }

  void _go(Widget screen) {
    if (!_canNavigate) return;
    Navigator.of(context).push(lunoRoute(screen));
  }

  Future<void> _battle() async {
    final store = GameStore.instance;
    if (!_canNavigate || _preparingBattle) return;
    final first = store.needsFirstSessionMatch;
    if (!first) {
      _go(PlayModeScreen(online: _online));
      return;
    }
    final online = _online;
    final navigator = Navigator.of(context), route = ModalRoute.of(context)!;
    final l = LunoLocalizations.of(context);
    final entryRevision = store.accountBindingRevision;
    final authRevision = online.accountRevision;
    final entryUid = store.accountUid, authUid = online.user?.uid;
    final foreground = _FirstBattleForegroundGuard();
    bool entryIsCurrent() {
      final currentUid = store.accountUid;
      final currentAuthUid = online.user?.uid;
      final currentAuthRevision = online.accountRevision;
      if (authUid != null) {
        if (currentAuthUid != authUid || currentAuthRevision != authRevision) {
          return false;
        }
      } else if (currentAuthUid == null) {
        if (currentAuthRevision != authRevision) return false;
      } else if ((currentAuthRevision != authRevision &&
              currentAuthRevision != authRevision + 1) ||
          (entryUid != null && currentAuthUid != entryUid)) {
        return false;
      }
      if (currentUid == entryUid &&
          store.accountBindingRevision == entryRevision) {
        return true;
      }
      // The one initial binding must belong to the bootstrapped auth user.
      return entryUid == null &&
          store.accountBindingRevision == entryRevision + 1 &&
          currentUid != null &&
          currentUid == currentAuthUid;
    }

    setState(() => _preparingBattle = true);
    FirstSessionTelemetry.forStore(store).record(
      FirstSessionEvent.firstMatchCtaPressed,
      _entryAccountRevision,
      mode: SessionMatchMode.ai,
    );
    try {
      if (online.cachedBattleDeck == null ||
          online.user == null ||
          store.accountUid != online.user?.uid) {
        await online.start().timeout(const Duration(seconds: 12));
      }
      // One initial guest binding may replace the Home widget. The navigator
      // intent survives only that first binding, never a switch or signout.
      if (!entryIsCurrent()) return;
      if (online.user == null) {
        throw const LunoApiException('network-unavailable', 0);
      }
      if (store.accountUid != online.user?.uid) {
        return;
      }
      final owner = AccountOperationGuard(store, online);
      await online.resolveAiBattleDeck().timeout(const Duration(seconds: 15));
      owner.check();
      final life = WidgetsBinding.instance.lifecycleState;
      if (!navigator.mounted ||
          !route.isCurrent ||
          !foreground.isCurrent ||
          (life != null && life != AppLifecycleState.resumed)) {
        return;
      }
      unawaited(
        navigator.push(
          lunoRoute(BattleV1Screen(level: aiLevels.first, deckOnline: online)),
        ),
      );
    } catch (error) {
      if (navigator.mounted &&
          route.isCurrent &&
          foreground.isCurrent &&
          entryIsCurrent()) {
        if (online.accountFailure == null &&
            !online.authTransitioning &&
            !(error is LunoApiException &&
                (error.accountAccessMessage != null ||
                    const {
                      'session-changed',
                      'account-required',
                      'deck-save-pending',
                    }.contains(error.code)))) {
          await _offerOfflinePractice(
            navigator: navigator,
            route: route,
            online: online,
            foreground: foreground,
            entryIsCurrent: entryIsCurrent,
            l: l,
          );
          return;
        }
        ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
          SnackBar(
            content: Text(
              l.learning(
                'İlk maçın için hesabın ve desten hazırlanamadı. Bağlantını kontrol edip yeniden dene.',
                'Your account and deck could not be prepared for the first match. Check your connection and retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      foreground.dispose();
      if (mounted) setState(() => _preparingBattle = false);
    }
  }

  Future<void> _offerOfflinePractice({
    required NavigatorState navigator,
    required ModalRoute<dynamic> route,
    required LunoOnlineService online,
    required _FirstBattleForegroundGuard foreground,
    required bool Function() entryIsCurrent,
    required LunoLocalizations l,
  }) async {
    final store = GameStore.instance;
    final offerContext = route.subtreeContext;
    if (offerContext == null || !offerContext.mounted) return;
    final owner = (
      store.accountUid,
      store.accountBindingRevision,
      online.user?.uid,
      online.accountRevision,
    );
    bool current() =>
        navigator.mounted &&
        route.isCurrent &&
        foreground.isCurrent &&
        entryIsCurrent() &&
        !online.authTransitioning &&
        online.accountFailure == null &&
        owner ==
            (
              store.accountUid,
              store.accountBindingRevision,
              online.user?.uid,
              online.accountRevision,
            );
    if (!current()) return;
    ModalRoute<dynamic>? offerRoute;
    foreground.onInterrupted = () {
      final modal = offerRoute;
      if (modal != null && modal.isActive) modal.navigator?.removeRoute(modal);
    };
    bool? accepted;
    try {
      accepted = await showLunoAccountDialog<bool>(
        context: offerContext,
        service: online,
        playerStore: store,
        builder: (dialogContext) {
          offerRoute = ModalRoute.of(dialogContext);
          return AlertDialog(
            key: const ValueKey('first-offline-practice-offer'),
            title: Text(
              l.learning('Çevrimdışı antrenman?', 'Offline practice?'),
            ),
            content: Text(
              l.learning(
                'Hesabın veya aktif desten şu anda doğrulanamıyor. '
                    'Luno Akademisi\'nde aktif desten yerine eğitim destesiyle '
                    'çevrimdışı oynayabilirsin. Kupa, harcanabilir ödül veya '
                    'sunucu ilerlemesi kazanılmaz.',
                'Your account or active deck cannot be confirmed right now. '
                    'You can play offline in Luno Academy with a teaching deck '
                    'instead of your active deck. No trophies, spendable '
                    'rewards or server progression are earned.',
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('first-offline-practice-cancel'),
                onPressed: () => dismissLunoAccountModal(dialogContext, false),
                child: Text(l.learning('Vazgeç', 'Cancel')),
              ),
              FilledButton.icon(
                key: const ValueKey('first-offline-practice-start'),
                onPressed: () => dismissLunoAccountModal(dialogContext, true),
                icon: const Icon(Icons.school_rounded),
                label: Text(l.learning('Antrenmana başla', 'Start practice')),
              ),
            ],
          );
        },
      );
    } catch (_) {
      return;
    } finally {
      foreground.onInterrupted = null;
    }
    if (accepted != true || !current()) return;
    unawaited(
      navigator.push(lunoRoute(const BattlePracticeCampaign(replay: true))),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  Future<void> _startOnlineAndRecoverMatch() async {
    if (_recoveryAttempted) return;
    _recoveryAttempted = true;
    final online = _online;
    try {
      await _withHomeDeadline(online.start(), const Duration(seconds: 12));
      if (!mounted ||
          !online.isOnline ||
          _entryAccountRevision != GameStore.instance.accountBindingRevision ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final recoveryUid = online.user?.uid;
      if (recoveryUid == null || recoveryUid.isEmpty) return;

      // The server maps the authenticated player to an active match. This is
      // deliberately queried only once on a fresh home screen so a process
      // death can resume a live match without adding a permanent poll loop.
      final result = await _withHomeDeadline(
        online.getBattleV1(''),
        const Duration(seconds: 8),
      );
      if (!mounted ||
          _entryAccountRevision != GameStore.instance.accountBindingRevision ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      openRecoveredOnlineMatch(
        context,
        result,
        requestedUid: recoveryUid,
        currentUid: online.user?.uid,
      );
    } catch (_) {
      // Offline launch remains fully usable; the online hub can retry when the
      // player explicitly opens it after connectivity returns.
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = GameStore.instance;
    final online = _online;
    return ListenableBuilder(
      listenable: Listenable.merge([store, online]),
      builder: (context, _) {
        final data = store.data;
        return Scaffold(
          backgroundColor: LunoColors.bgDeep,
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shortWide =
                    constraints.maxWidth > constraints.maxHeight &&
                    constraints.maxHeight < 500;
                final arenaBar = _ArenaBar(
                  trophies: store.rankTrophies,
                  arenaIdx: store.rankArenaIdx,
                  onTap: () => _go(const ArenasScreen()),
                );
                final bottomNav = _BottomNav(
                  onShop: () => _go(const ShopScreen()),
                  onCollection: () => _go(const CollectionScreen()),
                  onBattle: _battle,
                  onSeason: () => _go(const SeasonScreen()),
                  onProfile: () => _go(const ProfileScreen()),
                );
                return Column(
                  children: [
                    if (_preparingBattle)
                      const LinearProgressIndicator(
                        key: ValueKey('home-battle-preparing'),
                        minHeight: 2,
                      ),
                    _TopBar(
                      data: data,
                      trophies: store.rankTrophies,
                      online: online,
                      onProfile: () => _go(const ProfileScreen()),
                      onSeason: () => _go(const SeasonScreen()),
                      onShop: () => _go(const ShopScreen()),
                      onInbox: () => _go(const InboxScreen()),
                    ),
                    _QuickLinks(
                      store: store,
                      online: online,
                      onPass: () => _go(const PassScreen()),
                      onFriends: () => _go(const FriendsScreen()),
                      onMissions: () => _go(const MissionsScreen()),
                      onRanking: () => _go(const RankingScreen()),
                      onGuide: () => _go(const TutorialScreen()),
                      onSettings: () => _go(const SettingsScreen()),
                    ),
                    Expanded(
                      child:
                          shortWide
                              ? Row(
                                children: [
                                  Expanded(
                                    child: _MenuStage(
                                      firstMatch: store.needsFirstSessionMatch,
                                      onBattle: _battle,
                                    ),
                                  ),
                                  SizedBox(
                                    width: (constraints.maxWidth * .44).clamp(
                                      280.0,
                                      440.0,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        children: [arenaBar, bottomNav],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                              : _MenuStage(
                                firstMatch: store.needsFirstSessionMatch,
                                onBattle: _battle,
                              ),
                    ),
                    if (!shortWide) ...[arenaBar, bottomNav],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// A first-guest binding can replace Home while its entry intent is still pending.
class _FirstBattleForegroundGuard with WidgetsBindingObserver {
  _FirstBattleForegroundGuard() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _interrupted = false;
  VoidCallback? onInterrupted;

  bool get isCurrent {
    final state = WidgetsBinding.instance.lifecycleState;
    return !_interrupted &&
        (state == null || state == AppLifecycleState.resumed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _interrupted = true;
    onInterrupted?.call();
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}

class _TopBar extends StatelessWidget {
  final PlayerData data;
  final int trophies;
  final LunoOnlineService online;
  final VoidCallback onProfile;
  final VoidCallback onSeason;
  final VoidCallback onShop;
  final VoidCallback onInbox;

  const _TopBar({
    required this.data,
    required this.trophies,
    required this.online,
    required this.onProfile,
    required this.onSeason,
    required this.onShop,
    required this.onInbox,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _ProfilePill(data: data, onTap: onProfile)),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 50,
                child: _IconTile(
                  art: LunoAssets.navChat,
                  onTap: onInbox,
                  badge: online.unreadDirectMessageCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _CurrencyChip(
                  art: LunoAssets.trophy,
                  value: trophies,
                  color: LunoColors.gold,
                  onTap: onSeason,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: _CurrencyChip(
                  art: LunoAssets.coin,
                  value: data.gold,
                  color: LunoColors.gold,
                  onTap: onShop,
                  plus: true,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: _CurrencyChip(
                  art: LunoAssets.gem,
                  value: data.gems,
                  color: const Color(0xFF7FD0FF),
                  onTap: onShop,
                  plus: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  final PlayerData data;
  final VoidCallback onTap;

  const _ProfilePill({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
          decoration: BoxDecoration(
            color: LunoColors.bgPanel,
            image: lunoFace(LunoVisualAssets.neutral, opacity: .8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: LunoColors.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: LunoColors.bgStage,
                      border: Border.all(
                        color: const Color(0x99C8AA50),
                        width: 2,
                      ),
                    ),
                    child: const LunoArt(
                      LunoAssets.statusProfile,
                      width: 38,
                      height: 38,
                    ),
                  ),
                  Positioned(
                    bottom: -5,
                    left: 7,
                    right: 7,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: LunoColors.bgRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: LunoColors.bgDeep, width: 2),
                      ),
                      child: Text(
                        '${data.lvl}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Nunito',
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.username,
                      localize: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 10,
                          color: LunoColors.teal,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            'Luno Club',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: LunoColors.cyan,
                              fontSize: 9,
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
        ),
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String art;
  final int value;
  final Color color;
  final VoidCallback onTap;
  final bool plus;

  const _CurrencyChip({
    required this.art,
    required this.value,
    required this.color,
    required this.onTap,
    this.plus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: LunoColors.bgPanel,
            image: lunoFace(LunoVisualAssets.neutral, opacity: .8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LunoColors.line),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 7),
            ],
          ),
          child: Row(
            children: [
              LunoCurrencyArt(art, size: 34),
              const SizedBox(width: 2),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value.toString(),
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (plus) ...[
                const SizedBox(width: 2),
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: LunoColors.bgRaised,
                  ),
                  child: const Text(
                    '+',
                    style: TextStyle(
                      color: LunoColors.cyan,
                      fontSize: 14,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final String art;
  final VoidCallback onTap;
  final int badge;

  const _IconTile({required this.art, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: LunoColors.bgPanel,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: LunoColors.line),
              ),
              child: LunoArt(art),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(top: -5, right: -5, child: _UnreadBadge(value: badge)),
      ],
    );
  }
}

class _QuickLinks extends StatelessWidget {
  final GameStore store;
  final LunoOnlineService online;
  final VoidCallback onPass;
  final VoidCallback onFriends;
  final VoidCallback onMissions;
  final VoidCallback onRanking;
  final VoidCallback onGuide;
  final VoidCallback onSettings;

  const _QuickLinks({
    required this.store,
    required this.online,
    required this.onPass,
    required this.onFriends,
    required this.onMissions,
    required this.onRanking,
    required this.onGuide,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String, VoidCallback)>[
      (LunoAssets.navPass, onPass),
      (LunoAssets.navFriends, onFriends),
      (LunoAssets.navMissions, onMissions),
      (LunoAssets.navRanking, onRanking),
      (LunoAssets.navGuide, onGuide),
      (LunoAssets.navSettings, onSettings),
    ];
    final socialBadge = online.socialActivityBadgeCount;
    final passBadge = store.claimablePassRewardCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height < 500 ? 72 : null,
                child: _ArtButton(
                  art: items[i].$1,
                  onTap: items[i].$2,
                  badge:
                      i == 0 && passBadge > 0
                          ? passBadge.clamp(1, 9).toInt()
                          : i == 1 && socialBadge > 0
                          ? socialBadge.clamp(1, 9).toInt()
                          : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int value;

  const _UnreadBadge({required this.value});

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

class _ArtButton extends StatefulWidget {
  final String art;
  final VoidCallback onTap;
  final int? badge;

  const _ArtButton({required this.art, required this.onTap, this.badge});

  @override
  State<_ArtButton> createState() => _ArtButtonState();
}

class _ArtButtonState extends State<_ArtButton> with WidgetsBindingObserver {
  bool _pressed = false;
  bool _foreground = true;
  late final int _ownerRevision;
  bool get _canReact =>
      mounted &&
      _foreground &&
      _ownerRevision == GameStore.instance.accountBindingRevision &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent == true;
  String get art => widget.art;
  int? get badge => widget.badge;
  VoidCallback get onTap => widget.onTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownerRevision = GameStore.instance.accountBindingRevision;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canReact) _pressed = false;
  }

  @override
  void didUpdateWidget(_ArtButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canReact) _pressed = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) _pressed = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = LunoLocalizations.of(context).translate(_artLabel(art));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          button: true,
          label: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onHighlightChanged: (value) {
                if (!mounted || value && !_canReact || _pressed == value) {
                  return;
                }
                setState(() => _pressed = value);
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedScale(
                scale:
                    _pressed && !MediaQuery.disableAnimationsOf(context)
                        ? .985
                        : 1,
                duration:
                    _foreground
                        ? LunoMotion.adaptive(context, LunoMotion.press)
                        : Duration.zero,
                curve: Curves.easeOutCubic,
                child: AspectRatio(
                  aspectRatio: 0.95,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(1, 1, 1, 4),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Transform.scale(
                                  scale: 1,
                                  child: const LunoArt(
                                    LunoAssets.menuShortcutSurface,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(9),
                                child: LunoArt(art, fit: BoxFit.contain),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label.toUpperCase(),
                            maxLines: 1,
                            style: const TextStyle(
                              color: Color(0xFFFFF2CE),
                              fontFamily: 'Cinzel',
                              fontFamilyFallback: ['CinzelTurkish'],
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -4,
            right: -3,
            child: Container(
              width: 19,
              height: 19,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE23A4A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _artLabel(String path) {
    if (path == LunoAssets.navPass) return 'Luno Pass';
    if (path == LunoAssets.navFriends) return 'Arkadaş';
    if (path == LunoAssets.navMissions) return 'Görevler';
    if (path == LunoAssets.navRanking) return 'Sıralama';
    if (path == LunoAssets.navGuide) return 'Rehber';
    if (path == LunoAssets.navSettings) return 'Ayarlar';
    return 'Menü';
  }
}

class _MenuStage extends StatefulWidget {
  const _MenuStage({required this.onBattle, this.firstMatch = false});
  final VoidCallback onBattle;
  final bool firstMatch;

  @override
  State<_MenuStage> createState() => _MenuStageState();
}

class _MenuStageState extends State<_MenuStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _pressed = false;
  late final int _ownerRevision;
  late final AnimationController _arrival;
  bool _entered = false, _foreground = true;

  bool get _canReact =>
      mounted &&
      _foreground &&
      _ownerRevision == GameStore.instance.accountBindingRevision &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent == true;

  bool get _motionEnabled =>
      _canReact && !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownerRevision = GameStore.instance.accountBindingRevision;
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _arrival = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  void _settleArrival() {
    _arrival.stop();
    _arrival.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canReact) _pressed = false;
    if (!_motionEnabled) {
      _entered = true;
      _settleArrival();
    } else if (!_entered) {
      _entered = true;
      _arrival.forward();
    }
  }

  @override
  void didUpdateWidget(_MenuStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canReact) {
      _pressed = false;
      _settleArrival();
    }
    if (oldWidget.firstMatch != widget.firstMatch && _motionEnabled) {
      _arrival.forward(from: 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) _pressed = false;
    });
    if (!_foreground) {
      _settleArrival();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _arrival,
            child: const RepaintBoundary(
              child: LunoArt(LunoAssets.menuScene, fit: BoxFit.cover),
            ),
            builder:
                (context, child) => Transform.scale(
                  key: const ValueKey('home-scene-arrival'),
                  scale:
                      1 +
                      .018 *
                          (1 - Curves.easeOutCubic.transform(_arrival.value)),
                  child: child,
                ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x55122022)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 3,
            child: AnimatedBuilder(
              animation: _arrival,
              builder:
                  (context, child) => Transform.translate(
                    key: const ValueKey('home-cta-arrival'),
                    offset: Offset(
                      0,
                      12 * (1 - Curves.easeOutCubic.transform(_arrival.value)),
                    ),
                    child: child,
                  ),
              child: Center(
                child: Semantics(
                  button: true,
                  label:
                      widget.firstMatch
                          ? l.learning(
                            'İlk maçın · Bebek Luno',
                            'First match · Baby Luno',
                          )
                          : l.translate('Savaşa gir'),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('home-primary-battle'),
                      onHighlightChanged: (value) {
                        if (!mounted ||
                            value && !_canReact ||
                            _pressed == value) {
                          return;
                        }
                        setState(() => _pressed = value);
                      },
                      onTap: () {
                        if (!mounted) return;
                        widget.onBattle();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedScale(
                        scale:
                            _pressed && !MediaQuery.disableAnimationsOf(context)
                                ? .985
                                : 1,
                        duration:
                            _foreground
                                ? LunoMotion.adaptive(context, LunoMotion.press)
                                : Duration.zero,
                        curve: Curves.easeOutCubic,
                        child: SizedBox(
                          width: 280,
                          height: 90,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  image: lunoFace(
                                    LunoVisualAssets.primary,
                                    button: true,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          l.learning(
                                            'TAHTAN HAZIR',
                                            'YOUR BOARD IS READY',
                                          ),
                                          maxLines: 1,
                                          style: const TextStyle(
                                            color: LunoColors.cyan,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.firstMatch
                                              ? l.learning(
                                                'İLK MAÇIN',
                                                'FIRST MATCH',
                                              )
                                              : l.learning(
                                                'SAVAŞA GİR',
                                                'ENTER BATTLE',
                                              ),
                                          maxLines: 1,
                                          style: const TextStyle(
                                            color: LunoColors.ivory,
                                            fontFamily: 'Nunito',
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.firstMatch
                                              ? l.learning(
                                                'Bebek Luno · Kupa kaybı yok',
                                                'Baby Luno · No trophy loss',
                                              )
                                              : l.learning(
                                                'Modunu ve süreni seç',
                                                'Choose a mode and time',
                                              ),
                                          maxLines: 1,
                                          style: const TextStyle(
                                            color: LunoColors.textDim,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            height: 1,
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

class _ArenaBar extends StatelessWidget {
  final int trophies;
  final int arenaIdx;
  final VoidCallback onTap;

  const _ArenaBar({
    required this.trophies,
    required this.arenaIdx,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final arena = arenaIndexForPlayer(trophies, arenaIdx);
    final definition = arenaForIndex(arena);
    final arenaArt = LunoAssets.arena(arena);
    final progress = arenaProgress(trophies, arena);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: LunoColors.bgPanel,
              image: lunoFace(LunoVisualAssets.path, opacity: .8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xA6F0CD66)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackedProgress =
                    constraints.maxWidth < 350 ||
                    MediaQuery.textScalerOf(context).scale(14) > 16.8;
                final progressBar = Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 9,
                          backgroundColor: LunoColors.bgDeep,
                          valueColor: const AlwaysStoppedAnimation(
                            LunoColors.cyan,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: LunoColors.bgDeep,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: Text(
                          arenaProgressLabel(trophies, arena),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Nunito',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: stackedProgress ? 58 : 78,
                          height: 64,
                          decoration: BoxDecoration(
                            color: LunoColors.bgStage,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x66F0CD66)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            arenaArt,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -.7),
                            cacheWidth: 256,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MEVCUT ARENA',
                                style: TextStyle(
                                  color: LunoColors.cyan,
                                  fontFamily: 'Nunito',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                definition.displayName,
                                maxLines: stackedProgress ? null : 1,
                                overflow:
                                    stackedProgress
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: LunoColors.ivory,
                                  fontFamily: 'Nunito',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              if (!stackedProgress) ...[
                                const SizedBox(height: 3),
                                progressBar,
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        LunoArt(
                          'assets/native_art/v205-arena-next.png',
                          width: stackedProgress ? 32 : 40,
                          height: 48,
                        ),
                      ],
                    ),
                    if (stackedProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: progressBar,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final VoidCallback onShop;
  final VoidCallback onCollection;
  final VoidCallback onBattle;
  final VoidCallback onSeason;
  final VoidCallback onProfile;

  const _BottomNav({
    required this.onShop,
    required this.onCollection,
    required this.onBattle,
    required this.onSeason,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String, VoidCallback)>[
      (LunoAssets.navShop, onShop),
      (LunoAssets.navCollection, onCollection),
      (LunoAssets.navBattle, onBattle),
      (LunoAssets.navSeason, onSeason),
      (LunoAssets.navProfile, onProfile),
    ];
    return Container(
      margin: EdgeInsets.fromLTRB(
        8,
        0,
        8,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
      decoration: BoxDecoration(
        color: LunoColors.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LunoColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: item.$2,
                  borderRadius: BorderRadius.circular(9),
                  child: Semantics(
                    button: true,
                    label: LunoLocalizations.of(
                      context,
                    ).translate(_label(item.$1)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: SizedBox(
                        height: 58,
                        child: Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: SizedBox(
                                  width: 44,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      LunoArt(item.$1, fit: BoxFit.contain),
                                      if (item.$1 == LunoAssets.navShop &&
                                          GameStore.instance.canClaimDaily())
                                        const Positioned(
                                          top: 0,
                                          right: 0,
                                          child: _UnreadBadge(value: 1),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                LunoLocalizations.of(
                                  context,
                                ).translate(_label(item.$1)).toUpperCase(),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFFFFF2CE),
                                  fontFamily: 'Cinzel',
                                  fontFamilyFallback: ['CinzelTurkish'],
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
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

  String _label(String path) {
    if (path == LunoAssets.navShop) return 'Mağaza';
    if (path == LunoAssets.navCollection) return 'Koleksiyon';
    if (path == LunoAssets.navBattle) return 'Savaş';
    if (path == LunoAssets.navSeason) return 'Sezon';
    if (path == LunoAssets.navProfile) return 'Profil';
    return 'Menü';
  }
}
