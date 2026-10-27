import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Text;

import '../data/pass.dart';
import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_modal.dart';
import '../navigation/luno_account_scope.dart';
import '../services/luno_online_service.dart';
import '../services/account_operation_guard.dart';
import '../services/screen_request_timeouts.dart';
import '../services/pass_action_result.dart';
import '../services/cosmetic_catalog.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/currency_bar.dart';
import '../widgets/luno_surface.dart';
import '../widgets/resource_amount.dart';
import '../widgets/pass_purchase_recovery.dart';
import 'shop_screen.dart' show ChestRevealDialog, ShopRewardDialog;

/// Luno Pass: bedava + premium ödül şeritleri.
class PassScreen extends StatefulWidget implements LunoAccountScopedPage {
  const PassScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends State<PassScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  final Set<String> _busyRewards = <String>{};
  bool _openingChest = false;
  Future<void>? _entryRefresh;
  AccountOperationGuard? _entryRefreshOwner;
  int _entryRefreshSerial = 0;
  int _premiumRecoveryRevision = 0;
  int? _seasonNumber;
  DateTime? _seasonEnd;
  int? _seasonOwnerRevision;
  String? _chestRecoveryOwner;
  int? _chestRecoveryRevision;
  GameStore? _chestRecoveryStore;
  Future<List<String>>? _chestRecoveryFuture;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  String copy(String tr, String en) =>
      LunoLocalizations.of(context).isEnglish ? en : tr;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool _isCurrent(AccountOperationGuard guard) =>
      identical(store, guard.store) &&
      identical(online, guard.online) &&
      guard.isCurrent;

  void _checkCurrent(AccountOperationGuard guard) {
    if (!_isCurrent(guard)) {
      throw const LunoApiException('session-changed', 409);
    }
  }

  bool _canPresent(BuildContext context, AccountOperationGuard guard) =>
      mounted &&
      context.mounted &&
      _foreground &&
      _isCurrent(guard) &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void didUpdateWidget(covariant PassScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerStore != widget.playerStore ||
        oldWidget.online != widget.online) {
      _entryRefresh = null;
      _entryRefreshOwner = null;
      ++_entryRefreshSerial;
      _seasonNumber = null;
      _seasonEnd = null;
      _seasonOwnerRevision = null;
      _chestRecoveryFuture = null;
      ++_premiumRecoveryRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_refreshEntry().catchError((Object _) {}));
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshEntry().catchError((Object _) {}));
      }
    });
  }

  Future<void> _refreshEntry() {
    final current = _entryRefresh;
    final owner = _entryRefreshOwner;
    if (current != null && owner != null && _isCurrent(owner)) return current;
    _entryRefreshOwner = AccountOperationGuard(store, online);
    final serial = ++_entryRefreshSerial;
    final pending = _requestTimeouts.run(
      _readSeason(serial),
      const Duration(seconds: 12),
    );
    _entryRefresh = pending;
    // A timed-out read must not overwrite a successful later retry or reward.
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_entryRefresh, pending)) {
            _entryRefresh = null;
            ++_entryRefreshSerial;
          }
        },
      ),
    );
    return pending;
  }

  Future<void> _readSeason(int serial) async {
    final guard = AccountOperationGuard(store, online);
    await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
    _checkCurrent(guard);
    if (serial != _entryRefreshSerial ||
        !online.isOnline ||
        !mounted ||
        !_canPresent(context, guard)) {
      return;
    }
    final result = await _requestTimeouts.run(
      online.getPlayerState(),
      const Duration(seconds: 12),
    );
    _checkCurrent(guard);
    if (serial != _entryRefreshSerial) return;
    final state = result['state'];
    final economy = state is Map ? state['economy'] : null;
    final periods = economy is Map ? economy['periods'] : null;
    if (result['ok'] != true ||
        periods is! Map ||
        periods['seasonNumber'] is! int ||
        periods['seasonEndAt'] is! int) {
      return;
    }
    if (!mounted || !_canPresent(context, guard)) return;
    final end = DateTime.fromMillisecondsSinceEpoch(
      periods['seasonEndAt'] as int,
    );
    store.applyServerState(Map<String, dynamic>.from(state as Map));
    _checkCurrent(guard);
    setState(() {
      _seasonNumber = periods['seasonNumber'] as int;
      _seasonEnd = end;
      _seasonOwnerRevision = store.accountBindingRevision;
    });
  }

  @override
  void dispose() {
    _requestTimeouts.dispose();
    super.dispose();
  }

  void _releaseReward(String key) {
    if (!mounted) {
      _busyRewards.remove(key);
      return;
    }
    setState(() {
      _busyRewards.remove(key);
      if (key == 'premium') _premiumRecoveryRevision++;
    });
  }

  void _releaseChest() {
    if (!mounted) {
      _openingChest = false;
      return;
    }
    setState(() {
      _openingChest = false;
      _chestRecoveryFuture = null;
    });
  }

  Widget _pendingChestTile(BuildContext context, List<String> inventory) {
    final owner = store.accountUid;
    final revision = store.accountBindingRevision;
    final guard = AccountOperationGuard(store, online);
    if (_chestRecoveryFuture == null ||
        _chestRecoveryOwner != owner ||
        _chestRecoveryRevision != revision ||
        !identical(_chestRecoveryStore, store)) {
      _chestRecoveryOwner = owner;
      _chestRecoveryRevision = revision;
      _chestRecoveryStore = store;
      _chestRecoveryFuture =
          owner == null
              ? Future.value(<String>[])
              : store.pendingPassChestRequestKinds(owner);
    }
    return FutureBuilder<List<String>>(
      future: _chestRecoveryFuture,
      builder: (context, snapshot) {
        final recoveries =
            snapshot.connectionState == ConnectionState.done &&
                    _isCurrent(guard)
                ? snapshot.data ?? <String>[]
                : <String>[];
        final recovering = recoveries.isNotEmpty;
        final chestId =
            recovering
                ? recoveries.first
                : inventory.isNotEmpty
                ? inventory.first
                : null;
        if (chestId == null) return const SizedBox.shrink();
        final artwork = LunoArt(
          LunoAssets.chest(chestId),
          width: 42,
          height: 42,
        );
        final message = Text(
          recovering
              ? 'Bekleyen sandık açılışını tamamla.'
              : '${inventory.length} Pass sandığı açılmayı bekliyor.',
          style: const TextStyle(fontWeight: FontWeight.w800),
        );
        final button = FilledButton(
          onPressed:
              _openingChest || _busyRewards.isNotEmpty
                  ? null
                  : () {
                    if (!_canPresent(context, guard)) return;
                    unawaited(_openPassChest(context, chestId));
                  },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 36),
          ),
          child: Text(recovering ? 'TEKRAR DENE' : 'AÇ'),
        );
        return Padding(
          key: const ValueKey('pending-pass-chest'),
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: LunoSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18;
                if (stacked) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          artwork,
                          const SizedBox(width: 9),
                          Expanded(child: message),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: button),
                    ],
                  );
                }
                return Row(
                  children: [
                    artwork,
                    const SizedBox(width: 9),
                    Expanded(child: message),
                    const SizedBox(width: 8),
                    button,
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _buyPremium(BuildContext context) async {
    if (!mounted ||
        !context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true ||
        _busyRewards.isNotEmpty ||
        _openingChest) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    setState(() => _busyRewards.add('premium'));
    try {
      await _refreshEntry();
      _checkCurrent(guard);
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      _checkCurrent(guard);
      if (!context.mounted || !_canPresent(context, guard)) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.purchaseSoftItem('pass:premium');
      _checkCurrent(guard);
      validatePassActionResult(result, 'purchased');
      final state = result['state'];
      if (state is Map) {
        store.applyServerState(Map<String, dynamic>.from(state));
      }
      if (context.mounted && _canPresent(context, guard)) {
        final alreadyActive = result['purchased'] == false;
        showLunoNotice(
          context,
          result['passActive'] == false
              ? 'Önceki sezonun Premium alımı doğrulandı. Yeni sezon etkinleştirilmedi.'
              : alreadyActive
              ? 'Luno Pass Premium zaten etkin.'
              : 'Luno Pass Premium etkinleştirildi.',
        );
      }
    } catch (error) {
      if (!context.mounted || !_canPresent(context, guard)) {
        return;
      }
      final message =
          error is LunoApiException &&
                  (error.code == 'app-check-required' ||
                      error.code == 'invalid-app-check')
              ? 'Güvenli bağlantı doğrulanamadı.'
              : error is LunoApiException &&
                  error.code == 'insufficient-balance'
              ? 'Yeterli elmasın yok.'
              : error is LunoApiException && error.code == 'pass-season-changed'
              ? 'Sezon değişti. Güncel Pass durumunu kontrol edip yeniden dene.'
              : 'Premium işlemi doğrulanamadı. Bağlantı yenilendiğinde Pass durumunu kontrol et.';
      showLunoNotice(context, message);
    } finally {
      _releaseReward('premium');
    }
  }

  Future<void> _claimReward(
    BuildContext context,
    int level,
    String track,
  ) async {
    final key = '$track:$level';
    if (!mounted ||
        !context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true ||
        _busyRewards.isNotEmpty ||
        _openingChest) {
      return;
    }
    final store = this.store;
    final eligible =
        track == 'free'
            ? store.canClaimPassFree(level)
            : track == 'premium' && store.canClaimPassPrem(level);
    if (!eligible) return;
    final guard = AccountOperationGuard(store, online);
    setState(() => _busyRewards.add(key));
    try {
      await _refreshEntry();
      _checkCurrent(guard);
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      _checkCurrent(guard);
      if (!context.mounted || !_canPresent(context, guard)) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.claimPassReward(level, track);
      _checkCurrent(guard);
      validatePassActionResult(result, 'granted');
      final expectedReward =
          track == 'free'
              ? passFree(level)
              : passPrem(level, rewardVersion: store.data.passRewardVersion);
      if (result['granted'] == true &&
          expectedReward.kind == PassRewardKind.emoji) {
        final content = result['content'];
        final state = result['state'] as Map;
        final inventory = state['inventory'];
        if (content is! Map ||
            content['kind'] != 'emoji' ||
            content['id'] != expectedReward.key ||
            content['duplicate'] is! bool ||
            inventory is! Map ||
            inventory['ownedEmojis'] is! List ||
            !(inventory['ownedEmojis'] as List).contains(expectedReward.key)) {
          throw const FormatException('Unconfirmed Pass emote delivery');
        }
      }
      final state = result['state'];
      if (state is Map) {
        store.applyServerState(Map<String, dynamic>.from(state));
      }
      if (context.mounted && _canPresent(context, guard)) {
        final alreadyClaimed = result['granted'] == false;
        final content = result['content'];
        final emote =
            content is Map && content['kind'] == 'emoji'
                ? cosmeticEmote(content['id']?.toString() ?? '')
                : null;
        if (!alreadyClaimed &&
            content is Map &&
            content['duplicate'] == false &&
            emote != null &&
            store.data.ownedEmojis.contains(emote.id)) {
          await showLunoAccountDialog<void>(
            context: context,
            service: online,
            playerStore: store,
            builder:
                (_) => ShopRewardDialog(
                  title: copy('YENİ İFADE', 'NEW EMOTE'),
                  art: LunoAssets.emoji(emote.id),
                  emoteId: emote.id,
                  playerStore: store,
                  online: online,
                  message:
                      '${emote.title(LunoLocalizations.of(context).isEnglish)}\n${copy('İfade koleksiyonunda hazır. Hızlı yuvana ekleyebilirsin.', 'Ready in your emote collection. Add it to a quick slot.')}',
                ),
          );
          return;
        }
        showLunoNotice(
          context,
          alreadyClaimed
              ? 'Bu Pass ödülü zaten alınmış.'
              : 'Pass ödülü hesabına eklendi.',
        );
      }
    } catch (error) {
      if (!context.mounted || !_canPresent(context, guard)) {
        return;
      }
      final message =
          error is LunoApiException &&
                  error.code == 'pass-reward-not-configured'
              ? 'Bu Pass ödülü sunucuda henüz tanımlı değil.'
              : error is LunoApiException &&
                  (error.code == 'app-check-required' ||
                      error.code == 'invalid-app-check')
              ? 'Güvenli bağlantı doğrulanamadı.'
              : 'Ödül işlemi doğrulanamadı. Bağlantı yenilendiğinde ödül durumunu kontrol et.';
      showLunoNotice(context, message);
    } finally {
      _releaseReward(key);
    }
  }

  Future<void> _openPassChest(BuildContext context, String chestId) async {
    if (!mounted ||
        !context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true ||
        _openingChest ||
        _busyRewards.isNotEmpty) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    setState(() => _openingChest = true);
    try {
      await _refreshEntry();
      _checkCurrent(guard);
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      _checkCurrent(guard);
      if (!context.mounted || !_canPresent(context, guard)) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.openPassChest(chestId);
      _checkCurrent(guard);
      validatePassActionResult(result, 'opened');
      final state = result['state'];
      if (state is Map) {
        store.applyServerState(Map<String, dynamic>.from(state));
      }
      final rewards = result['rewards'];
      if (!context.mounted || !_canPresent(context, guard)) {
        return;
      }
      if ((rewards as List).isEmpty) {
        showLunoNotice(
          context,
          'Bu sandık işlemi daha önce tamamlandı. Koleksiyonunu kontrol et.',
        );
        return;
      }
      await showLunoAccountDialog<void>(
        context: context,
        service: online,
        playerStore: store,
        barrierDismissible: false,
        builder: (_) => ChestRevealDialog(chestId: chestId, rewards: rewards),
      );
    } catch (_) {
      if (context.mounted && _canPresent(context, guard)) {
        showLunoNotice(
          context,
          'Sandık işlemi doğrulanamadı. Bağlantı yenilendiğinde sandıklarını kontrol et.',
        );
      }
    } finally {
      _releaseChest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = this.store;
    final compactHeader =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    final compactOffer =
        MediaQuery.sizeOf(context).width < 560 || compactHeader;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final d = store.data;
        final level = store.passLevel();
        final progress = (d.passXp % kPassXpPerLevel) / kPassXpPerLevel;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: LunoColors.bgPanel,
            title: const Text('LUNO PASS'),
            actions: [
              if (!compactHeader)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Center(child: CurrencyBar()),
                ),
            ],
          ),
          body: LunoBackdrop(
            art: LunoAssets.passSceneV27,
            overlay: const Color(0x66100A24),
            child: CustomScrollView(
              slivers: [
                if (compactHeader)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: CurrencyBar(),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _pendingChestTile(context, d.pendingChests),
                ),
                SliverToBoxAdapter(
                  child: PassPurchaseRecoveryTile(
                    store: store,
                    revision: _premiumRecoveryRevision,
                    busy: _busyRewards.contains('premium'),
                    enabled: _busyRewards.isEmpty && !_openingChest,
                    onRetry: () => unawaited(_buyPremium(context)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xE6192934),
                      border: Border(
                        bottom: BorderSide(
                          color: LunoColors.gold.withValues(alpha: .5),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 76,
                          child: LunoArt(LunoAssets.passSeason),
                        ),
                        if (_seasonOwnerRevision ==
                                store.accountBindingRevision &&
                            _seasonEnd != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              copy(
                                    'Sezon $_seasonNumber · Bitiş: ',
                                    'Season $_seasonNumber · Ends: ',
                                  ) +
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(_seasonEnd!),
                              style: const TextStyle(
                                color: LunoColors.ivory,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        Flex(
                          direction:
                              compactOffer ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment:
                              compactOffer
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              flex: compactOffer ? 0 : 1,
                              child: Text(
                                'Seviye $level / $kPassMaxLevel',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: LunoColors.gold,
                                ),
                              ),
                            ),
                            if (compactOffer) const SizedBox(height: 8),
                            if (!d.premium)
                              Flexible(
                                flex: compactOffer ? 0 : 1,
                                child: LunoButton(
                                  label: copy(
                                    '$kPassPremiumCost · PASS PREMIUM AL',
                                    '$kPassPremiumCost · GET PASS PREMIUM',
                                  ),
                                  leading: const LunoArt(
                                    LunoAssets.statusGem,
                                    width: 28,
                                    height: 28,
                                  ),
                                  backgroundArt: LunoAssets.actionSurfaceV27,
                                  loading: _busyRewards.contains('premium'),
                                  onPressed:
                                      store.data.gems >= kPassPremiumCost &&
                                              _busyRewards.isEmpty &&
                                              !_openingChest
                                          ? () =>
                                              unawaited(_buyPremium(context))
                                          : null,
                                ),
                              )
                            else
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LunoArt(
                                    LunoAssets.passPremium,
                                    width: 24,
                                    height: 24,
                                  ),
                                  SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'PASS PREMIUM',
                                      style: TextStyle(
                                        color: LunoColors.gold,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: level >= kPassMaxLevel ? 1 : progress,
                            ),
                            duration: LunoMotion.adaptive(
                              context,
                              LunoMotion.reward,
                            ),
                            curve: Curves.easeOutCubic,
                            builder:
                                (context, value, _) => LinearProgressIndicator(
                                  value: value,
                                  minHeight: 10,
                                  backgroundColor: LunoColors.bgDeep,
                                  valueColor: const AlwaysStoppedAnimation(
                                    LunoColors.gold,
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          copy(
                            'Ranked maçlarla Pass XP kazan',
                            'Earn Pass XP in Ranked matches',
                          ),
                          style: TextStyle(
                            color: LunoColors.textDim,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          copy(
                            'Sezonluk ödül yolu · Luno Premium üyeliğinden ayrı.',
                            'Seasonal reward track · Separate from Luno Premium membership.',
                          ),
                          key: const ValueKey('pass-not-membership'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: LunoColors.textDim,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          level >= kPassMaxLevel
                              ? copy(
                                'Ödül yolu tamamlandı',
                                'Reward track completed',
                              )
                              : copy(
                                'Sıradaki ödül: Seviye ${level + 1} · ${kPassXpPerLevel - d.passXp % kPassXpPerLevel} XP',
                                'Next reward: Level ${level + 1} · ${kPassXpPerLevel - d.passXp % kPassXpPerLevel} XP',
                              ),
                          style: const TextStyle(
                            color: LunoColors.ivory,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: const [
                        Expanded(
                          child: Text(
                            'ÜCRETSİZ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: LunoColors.textDim,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'PASS PREMIUM',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: LunoColors.gold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _tierRow(context, store, i + 1),
                    childCount: kPassMaxLevel,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tierRow(BuildContext context, GameStore store, int level) {
    final free = passFree(level);
    final prem = passPrem(level, rewardVersion: store.data.passRewardVersion);
    return Container(
      key: ValueKey('pass-tier-$level'),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xD9162632),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              level == store.passLevel()
                  ? LunoColors.gold.withValues(alpha: .7)
                  : Colors.transparent,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScaler = MediaQuery.textScalerOf(context);
          final radius = textScaler.scale(12) + 2;
          final trackWidth = (constraints.maxWidth - radius * 2 - 8) / 2;
          final stacked = trackWidth < textScaler.scale(96) + 20;
          final freeReward = _reward(
            free,
            store.canClaimPassFree(level),
            () => unawaited(_claimReward(context, level, 'free')),
            store.data.passFreeClaimed.contains(level),
            busy: _busyRewards.isNotEmpty || _openingChest,
            claimKey: ValueKey('pass-claim-free-$level'),
            stateKey: ValueKey('pass-state-free-$level'),
            trackLabel: stacked ? 'ÜCRETSİZ' : null,
          );
          final premiumReward = _reward(
            prem,
            store.canClaimPassPrem(level),
            () => unawaited(_claimReward(context, level, 'premium')),
            store.data.passPremClaimed.contains(level),
            locked: !store.data.premium,
            premiumTrack: true,
            busy: _busyRewards.isNotEmpty || _openingChest,
            claimKey: ValueKey('pass-claim-premium-$level'),
            stateKey: ValueKey('pass-state-premium-$level'),
            trackLabel: stacked ? 'PASS PREMIUM' : null,
          );
          return Row(
            children: [
              CircleAvatar(
                radius: radius,
                backgroundColor:
                    level <= store.passLevel()
                        ? LunoColors.gold
                        : LunoColors.bgPanel2,
                child: Text(
                  '$level',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        level <= store.passLevel()
                            ? LunoColors.bgDeep
                            : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (stacked)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      freeReward,
                      const SizedBox(height: 8),
                      premiumReward,
                    ],
                  ),
                )
              else ...[
                Expanded(child: freeReward),
                Expanded(child: premiumReward),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _reward(
    PassTier reward,
    bool canClaim,
    VoidCallback onClaim,
    bool claimed, {
    bool locked = false,
    bool premiumTrack = false,
    Key? claimKey,
    Key? stateKey,
    String? trackLabel,
    bool busy = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: premiumTrack ? const Color(0xFF3C3830) : const Color(0xFF1B3A39),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          top: BorderSide(
            width: 2,
            color:
                premiumTrack
                    ? const Color(0xFFE9C980)
                    : const Color(0xFF8BD1BE),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trackLabel != null) ...[
            Text(
              trackLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: premiumTrack ? LunoColors.gold : LunoColors.textDim,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _rewardValue(
            reward,
            obscured: !claimed && !canClaim,
            premium: locked,
          ),
          const SizedBox(height: 6),
          if (canClaim && !claimed)
            LunoButton(
              key: claimKey,
              label: 'AL',
              loading: busy,
              backgroundArt: LunoAssets.actionSurfaceV27,
              onPressed: busy ? null : onClaim,
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (claimed)
                  ClipOval(
                    child: LunoArt(
                      claimed
                          ? 'assets/native_art/arena-unlocked-v41.png'
                          : 'assets/native_art/arena-lock-v41.png',
                      width: 24,
                      height: 24,
                    ),
                  ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    claimed
                        ? 'Alındı'
                        : locked
                        ? 'Premium'
                        : '',
                    key: stateKey,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: claimed ? LunoColors.success : LunoColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rewardValue(
    PassTier reward, {
    bool obscured = false,
    bool premium = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reward.kind != null || obscured) ...[
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: .9, sigmaY: .9),
                  enabled: obscured,
                  child: Opacity(
                    opacity: obscured ? .75 : 1,
                    child: SizedBox(
                      width: 72,
                      height: 56,
                      child:
                          reward.kind != null
                              ? LunoArt(_passRewardArt(reward))
                              : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (reward.gold > 0)
                                    const LunoCurrencyArt(
                                      LunoAssets.coin,
                                      size: 32,
                                    ),
                                  if (reward.gems > 0)
                                    const LunoCurrencyArt(
                                      LunoAssets.gem,
                                      size: 32,
                                    ),
                                ],
                              ),
                    ),
                  ),
                ),
              ),
              if (obscured)
                LunoArt(
                  premium
                      ? 'assets/native_art/v205-lock-premium.png'
                      : 'assets/native_art/v205-lock-common.png',
                  width: 42,
                  height: 46,
                ),
            ],
          ),
          const SizedBox(height: 2),
        ],
        if (reward.kind != null) ...[
          Text(
            reward.name ?? 'Özel ödül',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 5,
          runSpacing: 2,
          children: [
            if (reward.gold > 0)
              ResourceAmount.coin(reward.gold, iconSize: 28, fontSize: 13),
            if (reward.gems > 0)
              ResourceAmount.gem(reward.gems, iconSize: 28, fontSize: 13),
          ],
        ),
      ],
    );
  }

  String _passRewardArt(PassTier reward) {
    switch (reward.kind) {
      case PassRewardKind.chest:
        return LunoAssets.chest(reward.key ?? 'common');
      case PassRewardKind.emoji:
        return LunoAssets.emoji(reward.key ?? 'emoji-smile');
      case PassRewardKind.costume:
        return LunoAssets.setPreview(reward.key ?? 'luno');
      case null:
        return LunoAssets.passLevelFrame;
    }
  }
}
