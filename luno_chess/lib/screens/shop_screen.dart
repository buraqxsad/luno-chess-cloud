import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart' hide Text;
import '../theme/luno_visual_assets.dart';
import '../widgets/luno_polish.dart';
import '../widgets/shop_offer_layout.dart';
import '../widgets/cosmetic_match_preview.dart';
import '../widgets/cosmetic_emote_art.dart';
import '../services/cosmetic_catalog.dart';
import '../data/board_finishes.dart';
import '../data/card_pool.dart';
import '../battle_ui/cards.dart';
import '../battle_v1/model.dart';
import '../battle_v1/deck_account.dart';
import '../services/battle_v1_deck_result.dart';
import '../services/battle_welcome_reward.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';

import '../models/game_store.dart';
import '../i18n/luno_text.dart';
import '../navigation/luno_route.dart';
import '../navigation/luno_account_modal.dart';
import '../navigation/luno_account_scope.dart';
import '../services/luno_online_service.dart';
import '../services/luno_audio_service.dart';
import '../services/luno_billing_service.dart';
import '../services/chest_odds.dart';
import '../widgets/chest_odds_dialog.dart';
import '../services/shop_action_result.dart';
import '../services/account_operation_guard.dart';
import '../services/screen_request_timeouts.dart';
import '../services/collection_selection_result.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/currency_bar.dart';
import '../widgets/luno_surface.dart';
import '../widgets/resource_amount.dart';
import 'legacy_parity_screens.dart';
import 'collection_screens.dart'
    show
        CostumeBoardPreview,
        CosmeticPresentationFeedback,
        CosmeticPresentationFeedbackState,
        EmojiCollectionScreen;
import 'pass_screen.dart' show PassScreen;
import 'battle_deck_screen.dart' show BattleDeckScreen;

/// Server-owned rewards, cosmetics and verified Google Play products.
class ShopScreen extends StatefulWidget implements LunoAccountScopedPage {
  const ShopScreen({
    super.key,
    this.online,
    this.playerStore,
    this.billingService,
    this.cosmeticsOnly = false,
    this.focusPieceSet,
  });
  final LunoOnlineService? online;
  final GameStore? playerStore;
  final LunoBillingService? billingService;
  final bool cosmeticsOnly;
  final String? focusPieceSet;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  final Set<String> _busy = <String>{};
  String _section = 'featured';
  final _costumeScroll = ScrollController();
  bool _focusedCostume = false;
  Future<void>? _entryRefresh;
  String? _chestRecoveryOwner;
  int? _chestRecoveryRevision;
  GameStore? _chestRecoveryStore;
  Future<List<String>>? _chestRecoveryFuture;
  String? _purchaseRecoveryOwner;
  int? _purchaseRecoveryRevision;
  GameStore? _purchaseRecoveryStore;
  Future<List<String>>? _purchaseRecoveryFuture;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  bool get _nativeBilling =>
      widget.billingService != null ||
      ((widget.online == null ||
              identical(widget.online, LunoOnlineService.instance)) &&
          (widget.playerStore == null ||
              identical(widget.playerStore, GameStore.instance)));
  LunoBillingService get billing =>
      widget.billingService ?? LunoBillingService.instance;

  @override
  void dispose() {
    _requestTimeouts.dispose();
    _costumeScroll.dispose();
    super.dispose();
  }

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
  void didUpdateWidget(covariant ShopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerStore != widget.playerStore ||
        oldWidget.online != widget.online) {
      _entryRefresh = null;
      _chestRecoveryFuture = null;
      _purchaseRecoveryFuture = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _entryRefresh = _refreshServerState();
          unawaited(_entryRefresh!);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.cosmeticsOnly) _section = 'cosmetics';
    // The server owns the claim day. Refreshing on entry prevents a stale
    // local snapshot from showing a reward that was already claimed elsewhere.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entryRefresh = _refreshServerState();
        unawaited(_entryRefresh!);
      }
    });
  }

  Future<void> _refreshServerState() async {
    final guard = AccountOperationGuard(store, online);
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      _checkCurrent(guard);
      if (!mounted || !_canPresent(context, guard)) return;
      if (online.isOnline) {
        await online.refreshState();
        _checkCurrent(guard);
        if (!mounted || !_canPresent(context, guard)) return;
        unawaited(
          _refreshDeck(guard).then<void>((_) {}, onError: (Object _) {}),
        );
        if (_nativeBilling) {
          unawaited(billing.start().catchError((Object _) {}));
        }
      }
    } catch (_) {
      // Offline shop browsing remains available; the claim action still
      // requires a successful server response.
    }
  }

  Future<BattleDeckAccount> _refreshDeck(AccountOperationGuard guard) async {
    _checkCurrent(guard);
    final response = await _requestTimeouts.run(
      online.getBattleV1Deck(),
      const Duration(seconds: 15),
    );
    _checkCurrent(guard);
    final account = BattleDeckAccount.fromResponse(response);
    if (mounted && _isCurrent(guard)) setState(() {});
    return account;
  }

  bool get _welcomeAvailable {
    if (!store.firstSessionMatchCompleted ||
        online.user?.uid != store.accountUid) {
      return false;
    }
    final account = online.cachedBattleDeck;
    if (account == null || account.owned.contains(CardId.mine)) return false;
    final mine = account.progression?.path.where(
      (row) => row.card == CardId.mine,
    );
    return mine != null &&
        mine.any(
          (row) =>
              !row.owned &&
              row.requirements.any(
                (requirement) =>
                    requirement.kind == BattleUnlockKind.welcomeClaim &&
                    requirement.current == 0,
              ),
        );
  }

  Future<void> _claimWelcome(BuildContext context) async {
    if (!_welcomeAvailable || _busy.isNotEmpty) return;
    final guard = AccountOperationGuard(store, online);
    final result = await _onlineAction(
      context,
      'welcome',
      online.claimOnboardingReward,
      outcome: 'granted',
      validate: (response) {
        BattleWelcomeReward.fromResponse(response);
      },
    );
    if (result == null || !context.mounted || !_canPresent(context, guard)) {
      return;
    }
    setState(() => _busy.add('reward-follow-up'));
    try {
      final account = await _refreshDeck(guard);
      if (!context.mounted || !_canPresent(context, guard)) return;
      if (!account.owned.contains(CardId.mine)) {
        throw const FormatException('Unconfirmed Mine ownership');
      }
      final edit = await _showRewardDialog(
        context,
        title:
            LunoLocalizations.of(context).isEnglish
                ? 'MINE UNLOCKED'
                : 'MAYIN AÇILDI',
        art: battleCardArtAsset(CardId.mine),
        message:
            LunoLocalizations.of(context).isEnglish
                ? '500 gold and Mine are confirmed in your account.'
                : '500 altın ve Mayın hesabında doğrulandı.',
        cardUnlock: CardId.mine,
      );
      if (edit == true && context.mounted && _canPresent(context, guard)) {
        Navigator.of(context).push(
          lunoRoute(BattleDeckScreen(online: online, focusCard: CardId.mine)),
        );
      }
    } catch (_) {
      if (context.mounted && _canPresent(context, guard)) {
        _toast(
          context,
          LunoLocalizations.of(context).isEnglish
              ? 'Reward saved. Refresh your collection to verify the card.'
              : 'Ödül kaydedildi. Kartı doğrulamak için koleksiyonunu yenile.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove('reward-follow-up'));
    }
  }

  Future<Map<String, dynamic>?> _onlineAction(
    BuildContext context,
    String key,
    Future<Map<String, dynamic>> Function() action, {
    String? outcome,
    void Function(Map<String, dynamic>)? validate,
  }) async {
    if (_busy.isNotEmpty) return null;
    if (!mounted ||
        !context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return null;
    }
    final guard = AccountOperationGuard(store, online);
    setState(() => _busy.add(key));
    try {
      await _entryRefresh;
      _checkCurrent(guard);
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      _checkCurrent(guard);
      if (!context.mounted || !_canPresent(context, guard)) return null;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await action();
      _checkCurrent(guard);
      validateShopActionResult(result, outcome: outcome);
      validate?.call(result);
      final state = result['state'];
      if (state is Map) {
        store.applyServerState(Map<String, dynamic>.from(state));
      }
      _checkCurrent(guard);
      return result;
    } catch (error) {
      if (!context.mounted || !_canPresent(context, guard)) return null;
      _toast(context, _onlineError(error));
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(key);
        });
      }
    }
  }

  String _onlineError(Object error) {
    if (error is LunoApiException) {
      switch (error.code) {
        case 'app-check-required':
        case 'invalid-app-check':
          return 'Güvenli bağlantı doğrulanamadı. Uygulamayı Google Play sürümünden açıp tekrar dene.';
        case 'insufficient-balance':
          return 'Yeterli bakiyen yok.';
        case 'chest-collection-complete':
          return LunoLocalizations.of(context).isEnglish
              ? 'This chest has no remaining cosmetic target in your collection.'
              : 'Bu sandıkta koleksiyonun için kalan kozmetik hedefi yok.';
        case 'already-owned':
          return 'Bu ürün zaten hesabında bulunuyor.';
        case 'billing-review-required':
          return 'Hesap doğrulaması tamamlanmadan bu işlem kullanılamaz.';
        case 'online-unavailable':
          return 'Online servis şu an kullanılamıyor.';
        case 'request-in-progress':
          return 'İşlem henüz sonuçlanmadı. Kısa süre sonra tekrar dene.';
      }
    }
    return 'İşlem doğrulanamadı. Bağlantı yenilendiğinde durumunu kontrol et.';
  }

  Future<void> _claimDaily(BuildContext context) async {
    if (_busy.isNotEmpty) return;
    final guard = AccountOperationGuard(store, online);
    final before = online.cachedBattleDeck?.owned;
    final result = await _onlineAction(
      context,
      'daily',
      online.claimDailyReward,
      outcome: 'granted',
    );
    if (!context.mounted || !_canPresent(context, guard) || result == null) {
      return;
    }
    if (result['granted'] == false) {
      _toast(context, 'Bugünkü ödülünü zaten aldın.');
      return;
    }
    final reward = result['reward'];
    final gold = reward is Map ? reward['gold'] : null;
    if (gold is num) {
      setState(() => _busy.add('reward-follow-up'));
      CardId? unlocked;
      try {
        try {
          final account = await _refreshDeck(guard);
          final newCards =
              before == null
                  ? <CardId>[]
                  : account.owned.difference(before).toList();
          if (newCards.isNotEmpty) unlocked = newCards.first;
        } catch (_) {
          // Gold receipt remains valid when the independent card refresh fails.
        }
        if (!context.mounted || !_canPresent(context, guard)) return;
        final edit = await _showRewardDialog(
          context,
          title: 'GÜNLÜK ÖDÜL',
          art: 'assets/native_art/v205-daily-gift.png',
          message: '+${gold.toInt()} altın hesabına eklendi.',
          reward: ResourceAmount.coin(gold.toInt(), iconSize: 40, fontSize: 20),
          cardUnlock: unlocked,
        );
        if (edit == true &&
            unlocked != null &&
            context.mounted &&
            _canPresent(context, guard)) {
          Navigator.of(context).push(
            lunoRoute(BattleDeckScreen(online: online, focusCard: unlocked)),
          );
        }
      } finally {
        if (mounted) setState(() => _busy.remove('reward-follow-up'));
      }
    }
  }

  Future<void> _openServerChest(
    BuildContext context,
    String chestId, {
    bool recoverPendingOnly = false,
  }) async {
    if (_busy.isNotEmpty) return;
    final guard = AccountOperationGuard(store, online);
    if (!_canPresent(context, guard)) return;
    try {
      final prepareKey = 'chest-prepare:$chestId';
      setState(() => _busy.add(prepareKey));
      late final bool recoverPending;
      try {
        final owner = store.accountUid;
        if (owner == null || owner != online.user?.uid) return;
        final pending = await store.pendingShopChestRequestKinds(owner);
        _checkCurrent(guard);
        recoverPending = pending.contains(chestId);
        if (recoverPendingOnly && !recoverPending) return;
      } finally {
        if (mounted) setState(() => _busy.remove(prepareKey));
      }
      if (!context.mounted || !_canPresent(context, guard)) return;
      if (!recoverPending) {
        final accepted = await _confirmChestOdds(context, chestId, guard);
        if (accepted != true ||
            !context.mounted ||
            !_canPresent(context, guard)) {
          return;
        }
      }
      final result = await _onlineAction(
        context,
        'chest:$chestId',
        () => online.openChest(chestId, recoverPendingOnly: recoverPending),
        outcome: 'opened',
      );
      if (!context.mounted || !_canPresent(context, guard) || result == null) {
        return;
      }
      if ((result['rewards'] as List).isEmpty) {
        _toast(
          context,
          'Bu sandık işlemi daha önce tamamlandı. Koleksiyonunu kontrol et.',
        );
        return;
      }
      await _showServerChestResult(context, result);
    } catch (error) {
      if (context.mounted && _canPresent(context, guard)) {
        _toast(context, _onlineError(error));
      }
    } finally {
      if (mounted && _isCurrent(guard)) {
        setState(() => _chestRecoveryFuture = null);
      }
    }
  }

  Future<bool?> _confirmChestOdds(
    BuildContext context,
    String chestId,
    AccountOperationGuard guard,
  ) async {
    final key = 'chest-odds:$chestId';
    setState(() => _busy.add(key));
    try {
      await _entryRefresh;
      _checkCurrent(guard);
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      _checkCurrent(guard);
      if (!context.mounted || !_canPresent(context, guard)) return false;
      final response = await _requestTimeouts.run(
        online.getPlayerState(),
        const Duration(seconds: 12),
      );
      _checkCurrent(guard);
      final state = response['state'];
      if (response['ok'] != true ||
          state is! Map ||
          state['uid'] != online.user?.uid ||
          state['uid'] != store.accountUid) {
        throw const FormatException('Unconfirmed chest owner');
      }
      final odds = ChestOdds.fromPlayerState(
        chestId,
        Map<String, dynamic>.from(state),
      );
      final availability = state['shopChests'];
      final chest = availability is Map ? availability[chestId] : null;
      if (chest is! Map ||
          chest['price'] != odds.price ||
          chest['currency'] != odds.currency ||
          chest['canPurchase'] != odds.canPurchase ||
          chest['guaranteedGold'] is! Map ||
          chest['guaranteedGold']['min'] != odds.goldMin ||
          chest['guaranteedGold']['max'] != odds.goldMax) {
        throw const FormatException('Chest contract mismatch');
      }
      if (!context.mounted || !_canPresent(context, guard)) return false;
      return await showLunoAccountDialog<bool>(
        context: context,
        service: online,
        playerStore: store,
        builder:
            (_) => ChestOddsDialog(
              odds: odds,
              english: LunoLocalizations.of(context).isEnglish,
            ),
      );
    } catch (_) {
      if (context.mounted && _canPresent(context, guard)) {
        _toast(
          context,
          LunoLocalizations.of(context).isEnglish
              ? 'Chest odds could not be confirmed. No purchase was sent. Refresh and try again.'
              : 'Sandık olasılıkları doğrulanamadı. Satın alma gönderilmedi. Yenileyip tekrar dene.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _buySoftItem(BuildContext context, _ShopProduct product) =>
      _purchasePermanentItem(context, product.itemId, product: product);

  Future<void> _purchasePermanentItem(
    BuildContext context,
    String itemId, {
    _ShopProduct? product,
  }) async {
    if (_busy.isNotEmpty) return;
    final guard = AccountOperationGuard(store, online);
    try {
      final result = await _onlineAction(
        context,
        'item:$itemId',
        () => online.purchaseSoftItem(itemId),
        outcome: 'purchased',
        validate:
            product?.emoteId == null
                ? null
                : (response) =>
                    validatePermanentPurchaseResult(response, itemId),
      );
      if (!context.mounted || !_canPresent(context, guard) || result == null) {
        return;
      }
      if (result['purchased'] == false && result['idempotent'] != true) {
        _toast(context, 'Bu ürün zaten hesabında bulunuyor.');
        return;
      }
      final equip = await _showRewardDialog(
        context,
        title:
            product?.emoteId != null
                ? (LunoLocalizations.of(context).isEnglish
                    ? 'EMOTE UNLOCKED'
                    : 'İFADE AÇILDI')
                : product?.ownedLabel ?? 'SATIN ALIM DOĞRULANDI',
        art: product?.art ?? LunoAssets.shop,
        message:
            product?.emoteId != null
                ? (LunoLocalizations.of(context).isEnglish
                    ? 'Confirmed in your emote collection. Add it to your four quick slots.'
                    : 'İfade koleksiyonunda doğrulandı. Dört hızlı yuvandan birine ekleyebilirsin.')
                : result['idempotent'] == true
                ? 'Satın alma doğrulandı. Ürün hesabında.'
                : product?.successMessage ?? 'Ürün hesabına eklendi.',
        pieceSet: product?.setId,
        emoteId: product?.emoteId,
      );
      if (equip == true &&
          product != null &&
          context.mounted &&
          _canPresent(context, guard)) {
        await _activatePieceSet(context, product);
      }
    } finally {
      // Keep the tile mounted while the account-scoped reward modal is open.
      if (mounted && _isCurrent(guard)) {
        setState(() => _purchaseRecoveryFuture = null);
      }
    }
  }

  Future<void> _activatePieceSet(
    BuildContext context,
    _ShopProduct product,
  ) async {
    final guard = AccountOperationGuard(store, online);
    final result = await _onlineAction(
      context,
      'activate-set:${product.setId}',
      () => online.setPieceSet(product.setId!),
      validate: (result) {
        validatePieceSetResult(result, product.setId!);
      },
    );
    if (!context.mounted || !_canPresent(context, guard) || result == null) {
      return;
    }
    _toast(context, '${product.name} taşları aktif edildi.');
  }

  Widget _pendingShopChest(BuildContext context) {
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
              : store.pendingShopChestRequestKinds(owner);
    }
    return FutureBuilder<List<String>>(
      future: _chestRecoveryFuture,
      builder: (context, snapshot) {
        final pending =
            snapshot.connectionState == ConnectionState.done &&
                    _isCurrent(guard)
                ? snapshot.data ?? <String>[]
                : <String>[];
        if (pending.isEmpty) return const SizedBox.shrink();
        final chestId = pending.first;
        return Padding(
          key: const ValueKey('pending-shop-chest'),
          padding: const EdgeInsets.only(bottom: 14),
          child: _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    LunoArt(LunoAssets.chest(chestId), width: 48, height: 48),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Bekleyen sandık işlemi',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LunoButton(
                  label: 'TEKRAR DENE',
                  backgroundArt: LunoAssets.actionSurfaceV27,
                  loading: _busy.contains('chest:$chestId'),
                  onPressed:
                      _busy.isNotEmpty
                          ? null
                          : () {
                            if (!_canPresent(context, guard)) return;
                            unawaited(
                              _openServerChest(
                                context,
                                chestId,
                                recoverPendingOnly: true,
                              ),
                            );
                          },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pendingPermanentPurchase(BuildContext context) {
    final owner = store.accountUid;
    final revision = store.accountBindingRevision;
    final guard = AccountOperationGuard(store, online);
    if (_purchaseRecoveryFuture == null ||
        _purchaseRecoveryOwner != owner ||
        _purchaseRecoveryRevision != revision ||
        !identical(_purchaseRecoveryStore, store)) {
      _purchaseRecoveryOwner = owner;
      _purchaseRecoveryRevision = revision;
      _purchaseRecoveryStore = store;
      _purchaseRecoveryFuture =
          owner == null
              ? Future.value(<String>[])
              : store.pendingPermanentPurchaseItems(owner);
    }
    return FutureBuilder<List<String>>(
      future: _purchaseRecoveryFuture,
      builder: (context, snapshot) {
        final pending =
            snapshot.connectionState == ConnectionState.done &&
                    _isCurrent(guard)
                ? snapshot.data ?? <String>[]
                : <String>[];
        if (pending.isEmpty) return const SizedBox.shrink();
        final itemId = pending.first;
        _ShopProduct? product;
        for (final candidate in [
          ..._shopPieceSets,
          ..._emoteProducts(context),
        ]) {
          if (candidate.itemId == itemId) {
            product = candidate;
            break;
          }
        }
        return Padding(
          key: const ValueKey('pending-permanent-purchase'),
          padding: const EdgeInsets.only(bottom: 14),
          child: _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    LunoArt(
                      product?.art ?? LunoAssets.shop,
                      width: 48,
                      height: 48,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Bekleyen ürün işlemi',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LunoButton(
                  label: 'TEKRAR DENE',
                  backgroundArt: LunoAssets.actionSurfaceV27,
                  loading: _busy.contains('item:$itemId'),
                  onPressed:
                      _busy.isNotEmpty
                          ? null
                          : () {
                            if (!_canPresent(context, guard)) return;
                            unawaited(
                              _purchasePermanentItem(
                                context,
                                itemId,
                                product: product,
                              ),
                            );
                          },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = this.store;
    final compactHeader =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    return ListenableBuilder(
      listenable: Listenable.merge([store, if (_nativeBilling) billing]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: LunoColors.bgPanel,
            title: const Text('MAĞAZA'),
            actions: [
              if (!compactHeader)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Center(child: CurrencyBar()),
                ),
            ],
          ),
          body: LunoBackdrop(
            art: LunoAssets.phase2ShopShowcase,
            overlay: const Color(0xD9100A24),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (compactHeader)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: CurrencyBar(),
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: 'featured',
                          label: Text(
                            LunoLocalizations.of(context).isEnglish
                                ? 'Featured'
                                : 'Öne çıkan',
                          ),
                        ),
                        ButtonSegment(
                          value: 'cosmetics',
                          label: Text(
                            LunoLocalizations.of(context).isEnglish
                                ? 'Cosmetics'
                                : 'Kozmetik',
                          ),
                        ),
                        ButtonSegment(
                          value: 'chests',
                          label: Text(
                            LunoLocalizations.of(context).isEnglish
                                ? 'Chests'
                                : 'Sandıklar',
                          ),
                        ),
                        ButtonSegment(
                          value: 'currency',
                          label: Text(
                            LunoLocalizations.of(context).isEnglish
                                ? 'Currency'
                                : 'Para birimi',
                          ),
                        ),
                      ],
                      selected: {_section},
                      onSelectionChanged: (selection) {
                        if (_busy.isEmpty &&
                            ModalRoute.of(context)?.isCurrent == true) {
                          setState(() => _section = selection.single);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _pendingShopChest(context),
                  _pendingPermanentPurchase(context),
                  if (_section == 'featured') ...[
                    if (_welcomeAvailable)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: LunoButton(
                          key: const ValueKey('shop-welcome-reward'),
                          loading: _busy.contains('welcome'),
                          label:
                              LunoLocalizations.of(context).isEnglish
                                  ? 'WELCOME · 500 GOLD + MINE'
                                  : 'KARŞILAMA · 500 ALTIN + MAYIN',
                          onPressed:
                              _busy.isEmpty
                                  ? () => unawaited(_claimWelcome(context))
                                  : null,
                        ),
                      ),
                    _premiumBanner(context, store.data.isMembershipActive),
                    const SizedBox(height: 10),
                    _passEntry(context),
                    const SizedBox(height: 14),
                    _dailyCard(context, store),
                    const SizedBox(height: 14),
                  ],
                  if (_section == 'featured' || _section == 'chests') ...[
                    const Text(
                      'SANDIKLAR',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _chestCard(
                      context,
                      store,
                      title: 'Altın Sandık',
                      art: LunoAssets.chestCommon,
                      chestId: 'common',
                      cost: 500,
                      gem: false,
                      desc:
                          LunoLocalizations.of(context).isEnglish
                              ? 'Gold, board-frame pieces and emote pieces. No competitive cards.'
                              : 'Altın, tahta çerçevesi ve ifade parçaları. Rekabetçi kart vermez.',
                    ),
                    const SizedBox(height: 10),
                    _chestCard(
                      context,
                      store,
                      title: 'Nadir Sandık',
                      art: LunoAssets.chestRare,
                      chestId: 'rare',
                      cost: 1500,
                      gem: false,
                      desc:
                          LunoLocalizations.of(context).isEnglish
                              ? 'Gold and cosmetic pieces up to Legendary rarity.'
                              : 'Altın ve efsanevi nadirliğe kadar kozmetik parçaları.',
                    ),
                    const SizedBox(height: 10),
                    _chestCard(
                      context,
                      store,
                      title: 'Efsanevi Sandık',
                      art: LunoAssets.chestLegendary,
                      chestId: 'legendary',
                      cost: 3500,
                      gem: false,
                      desc:
                          LunoLocalizations.of(context).isEnglish
                              ? 'Gold and cosmetic pieces, with a Mythic chance.'
                              : 'Altın ve kozmetik parçaları; mitik parça şansı.',
                    ),
                    const SizedBox(height: 10),
                    _chestCard(
                      context,
                      store,
                      title: 'Kraliyet Sandığı',
                      art: LunoAssets.chestRoyal,
                      chestId: 'royal',
                      cost: 380,
                      gem: true,
                      desc:
                          LunoLocalizations.of(context).isEnglish
                              ? 'Gold and at least one remaining cosmetic part. No competitive cards.'
                              : 'Altın ve en az bir kalan kozmetik parçası. Rekabetçi kart vermez.',
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_section == 'featured' || _section == 'cosmetics') ...[
                    const Text(
                      'TAŞ KOSTÜMLERİ',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _costumeStrip(context, store),
                    const SizedBox(height: 18),
                    Text(
                      LunoLocalizations.of(context).isEnglish
                          ? 'EMOTES'
                          : 'İFADELER',
                      style: LunoType.sectionTitle,
                    ),
                    const SizedBox(height: 8),
                    _emoteShop(context),
                    const SizedBox(height: 18),
                  ],
                  if (_section == 'featured' || _section == 'currency') ...[
                    Text(
                      LunoLocalizations.of(context).isEnglish
                          ? 'GOLD & GEMS'
                          : 'ALTIN VE ELMAS',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final pack in const [
                      (
                        'luno_gold_1000',
                        1000,
                        'gold',
                        LunoAssets.packGoldSmall,
                      ),
                      (
                        'luno_gold_5500',
                        5500,
                        'gold',
                        LunoAssets.shopGoldMedium,
                      ),
                      (
                        'luno_gold_15000',
                        15000,
                        'gold',
                        LunoAssets.packGoldLarge,
                      ),
                      ('luno_gem_80', 80, 'gems', LunoAssets.packGemSmall),
                      ('luno_gem_500', 500, 'gems', LunoAssets.shopGemMedium),
                      ('luno_gem_1500', 1500, 'gems', LunoAssets.packGemLarge),
                    ]) ...[
                      _gemPack(
                        context,
                        '${MaterialLocalizations.of(context).formatDecimal(pack.$2)} ${LunoLocalizations.of(context).isEnglish ? (pack.$3 == 'gold' ? 'gold' : 'gems') : (pack.$3 == 'gold' ? 'altın' : 'elmas')}',
                        LunoLocalizations.of(context).isEnglish
                            ? 'Account-bound currency'
                            : 'Hesabına bağlı para birimi',
                        pack.$4,
                        productId: pack.$1,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _gemPack(
                      context,
                      LunoLocalizations.of(context).isEnglish
                          ? 'Starter Bundle'
                          : 'Başlangıç Paketi',
                      LunoLocalizations.of(context).isEnglish
                          ? '2,500 gold + 100 gems'
                          : '2.500 altın + 100 elmas',
                      LunoAssets.shopStarter,
                      productId: 'luno_bundle_starter',
                    ),
                    const SizedBox(height: 10),
                    _gemPack(
                      context,
                      LunoLocalizations.of(context).isEnglish
                          ? 'Expert Bundle'
                          : 'Uzman Paketi',
                      LunoLocalizations.of(context).isEnglish
                          ? '12,000 gold + 500 gems'
                          : '12.000 altın + 500 elmas',
                      LunoAssets.shopExpert,
                      productId: 'luno_bundle_pro',
                    ),
                    if (_nativeBilling &&
                        billing.status == LunoBillingStatus.queued)
                      TextButton.icon(
                        key: const ValueKey('store-retry-verification'),
                        onPressed:
                            () => unawaited(_retryPlayVerification(context)),
                        icon: const Icon(Icons.sync),
                        label: Text(
                          LunoLocalizations.of(context).isEnglish
                              ? 'Retry verification'
                              : 'Doğrulamayı tekrar dene',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panel({
    required Widget child,
    Color accent = const Color(0xFF7FADBE),
    Color fill = const Color(0xFF192B36),
  }) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: accent.withValues(alpha: .5)),
    ),
    padding: const EdgeInsets.all(14),
    child: child,
  );

  Widget _dailyCard(BuildContext context, GameStore store) {
    final can = store.canClaimDaily();
    return _panel(
      accent: const Color(0xFF87D8BC),
      fill: const Color(0xFF193A35),
      child: ShopOfferLayout(
        art: 'assets/native_art/v205-daily-gift.png',
        copy: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Günlük Ödül',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              can ? 'Bugünkü ödülün hazır' : 'Yarın tekrar gel',
              style: const TextStyle(color: LunoColors.textDim, fontSize: 12),
            ),
            if (can)
              ResourceAmount.coin(
                store.dailyPreview(),
                iconSize: 38,
                fontSize: 16,
              ),
          ],
        ),
        action: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: can ? LunoColors.gold : LunoColors.bgPanel2,
            foregroundColor: LunoColors.ivory,
            padding: EdgeInsets.zero,
          ),
          onPressed: can && _busy.isEmpty ? () => _claimDaily(context) : null,
          child:
              _busy.contains('daily')
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LunoArt(
                          'assets/native_art/v205-daily-gift.png',
                          width: 28,
                          height: 28,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'AL',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _chestCard(
    BuildContext context,
    GameStore store, {
    required String title,
    required String art,
    required String chestId,
    required int cost,
    required bool gem,
    required String desc,
  }) {
    final price = gem ? store.data.gems : store.data.gold;
    final afford = price >= cost;
    return _panel(
      accent: gem ? const Color(0xFFE8C67B) : const Color(0xFF8CBBD2),
      child: ShopOfferLayout(
        art: art,
        copy: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              desc,
              style: const TextStyle(color: LunoColors.textDim, fontSize: 12),
            ),
          ],
        ),
        action: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: afford ? LunoColors.gold : LunoColors.bgPanel2,
            foregroundColor: LunoColors.ivory,
            padding: EdgeInsets.zero,
          ),
          onPressed:
              afford && _busy.isEmpty
                  ? () => _openServerChest(context, chestId)
                  : null,
          child:
              _busy.contains('chest:$chestId')
                  ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$cost',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 4),
                        LunoCurrencyArt(
                          gem ? LunoAssets.gem : LunoAssets.coin,
                          size: 36,
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _gemPack(
    BuildContext context,
    String title,
    String contents,
    String art, {
    required String productId,
  }) {
    final product = _nativeBilling ? billing.products[productId] : null;
    final status = _nativeBilling ? billing.productStatuses[productId] : null;
    final busy = const {
      LunoBillingStatus.purchasing,
      LunoBillingStatus.pending,
      LunoBillingStatus.verifying,
      LunoBillingStatus.queued,
    }.contains(status);
    final l = LunoLocalizations.of(context);
    return _panel(
      accent: const Color(0xFF8BCACD),
      fill: const Color(0xFF183237),
      child: ShopOfferLayout(
        art: art,
        copy: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              contents,
              style: const TextStyle(color: LunoColors.textDim, fontSize: 12),
            ),
          ],
        ),
        action: FilledButton(
          key: ValueKey('store-product-$productId'),
          onPressed:
              product == null || busy || _busy.isNotEmpty
                  ? null
                  : () => unawaited(_purchasePlayProduct(context, productId)),
          child: Text(
            busy
                ? (l.isEnglish ? 'Pending' : 'Bekliyor')
                : product?.localizedPrice ??
                    (l.isEnglish ? 'Unavailable' : 'Kullanılamıyor'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _purchasePlayProduct(
    BuildContext context,
    String productId,
  ) async {
    if (!_nativeBilling ||
        !context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    try {
      await billing.purchase(productId);
      _checkCurrent(guard);
    } catch (_) {
      if (context.mounted && _canPresent(context, guard)) {
        final l = LunoLocalizations.of(context);
        showLunoNotice(
          context,
          l.isEnglish
              ? 'The store could not complete this request. Retry when connected.'
              : 'Mağaza işlemi tamamlayamadı. Bağlanınca tekrar deneyebilirsin.',
        );
      }
    }
  }

  Future<void> _retryPlayVerification(BuildContext context) async {
    if (!_nativeBilling ||
        !context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    try {
      await billing.restore();
      _checkCurrent(guard);
    } catch (_) {
      if (context.mounted && _canPresent(context, guard)) {
        showLunoNotice(
          context,
          LunoLocalizations.of(context).isEnglish
              ? 'Verification is still pending. No second charge was requested.'
              : 'Doğrulama hâlâ bekliyor. İkinci bir ödeme istenmedi.',
        );
      }
    }
  }

  Future<void> _showServerChestResult(
    BuildContext context,
    Map<String, dynamic> result,
  ) async {
    if (!context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final chestId = result['chestId']?.toString() ?? 'common';
    await showLunoAccountDialog<void>(
      context: context,
      service: online,
      playerStore: store,
      barrierDismissible: false,
      builder:
          (_) =>
              ChestRevealDialog(chestId: chestId, rewards: result['rewards']),
    );
  }

  Future<bool?> _showRewardDialog(
    BuildContext context, {
    required String title,
    required String art,
    required String message,
    Widget? reward,
    String? pieceSet,
    String? emoteId,
    CardId? cardUnlock,
  }) async {
    if (!context.mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return null;
    }
    return showLunoAccountDialog<bool>(
      context: context,
      service: online,
      playerStore: store,
      builder:
          (_) => ShopRewardDialog(
            title: title,
            art: art,
            message: message,
            reward: reward,
            pieceSet: pieceSet,
            emoteId: emoteId,
            cardUnlock: cardUnlock,
            playerStore: store,
            online: online,
          ),
    );
  }

  void _toast(BuildContext context, String msg) {
    showLunoNotice(context, msg);
  }

  Widget _premiumBanner(BuildContext context, bool active) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (ModalRoute.of(context)?.isCurrent != true) return;
          Navigator.of(context).push(
            lunoRoute(
              LunoPremiumScreen(
                online: online,
                playerStore: store,
                billingService: widget.billingService,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
            color: LunoColors.bgPanel,
            image: lunoFace(LunoVisualAssets.premium),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x99D6A63E)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const LunoArt(
                'assets/native_art/premium-crest-v30.png',
                width: 60,
                height: 60,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'LUNO PREMIUM AKTİF' : 'LUNO PREMIUM',
                      style: const TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      LunoLocalizations.of(context).isEnglish
                          ? 'Membership · Profile cosmetics'
                          : 'Üyelik · Profil kozmetikleri',
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: LunoColors.gold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passEntry(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    tileColor: LunoColors.bgRaised,
    leading: const LunoArt(LunoAssets.passSeason, width: 48, height: 48),
    title: const Text(
      'LUNO PASS',
      style: TextStyle(fontWeight: FontWeight.w900),
    ),
    subtitle: Text(
      LunoLocalizations.of(context).isEnglish
          ? 'Seasonal rewards · Free and paid tracks'
          : 'Sezon ödülleri · Ücretsiz ve ücretli yol',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () {
      if (ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.of(
        context,
      ).push(lunoRoute(PassScreen(online: online, playerStore: store)));
    },
  );

  Widget _costumeStrip(BuildContext context, GameStore store) {
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    if (!_focusedCostume && widget.focusPieceSet != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_costumeScroll.hasClients || _focusedCostume) return;
        final index = _shopPieceSets.indexWhere(
          (product) => product.setId == widget.focusPieceSet,
        );
        if (index >= 0) {
          _costumeScroll.jumpTo(
            (index * (164 + (scale - 1).clamp(0, 2) * 60))
                .clamp(0, _costumeScroll.position.maxScrollExtent)
                .toDouble(),
          );
        }
        _focusedCostume = true;
      });
    }
    return SizedBox(
      height: 256 + (scale - 1).clamp(0, 2) * 96,
      child: ListView.separated(
        controller: _costumeScroll,
        scrollDirection: Axis.horizontal,
        itemCount: _shopPieceSets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final product = _shopPieceSets[index];
          return _pieceSetCard(context, store, product);
        },
      ),
    );
  }

  List<_ShopProduct> _emoteProducts(BuildContext context) => [
    for (final emote in cosmeticEmotes)
      _ShopProduct(
        itemId: 'emoji:${emote.id}',
        name: emote.title(LunoLocalizations.of(context).isEnglish),
        art: LunoAssets.emoji(emote.id),
        cost: emote.goldPrice,
        gem: false,
        emoteId: emote.id,
      ),
  ];

  Widget _emoteShop(BuildContext context) {
    final en = LunoLocalizations.of(context).isEnglish;
    final products = _emoteProducts(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var minimumWidth = 160.0;
    final ownedWidth = textWidth(en ? 'OWNED' : 'SENİN', LunoType.button) + 64;
    if (ownedWidth > minimumWidth) minimumWidth = ownedWidth;
    for (final product in products) {
      // Keep prices and CTA labels whole; let product names wrap at spaces.
      final label = '${product.cost} ${en ? 'GOLD' : 'ALTIN'}';
      final required = textWidth(label, LunoType.button) + 100;
      if (required > minimumWidth) minimumWidth = required;
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = ((box.maxWidth + 10) / (minimumWidth + 10))
            .floor()
            .clamp(1, 4);
        final width = (box.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final product in products)
              SizedBox(
                width: width,
                child: _panel(
                  accent: cosmeticEmote(product.emoteId!)!.rarity.color,
                  fill: const Color(0xFF21313B),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LunoArt(product.art, width: 80, height: 80),
                      const SizedBox(height: 6),
                      Text(
                        product.name,
                        key: ValueKey('shop-emote-title-${product.emoteId}'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cosmeticEmote(product.emoteId!)!.rarity.title(en),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cosmeticEmote(product.emoteId!)!.rarity.color,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 54),
                        child: LunoButton(
                          key: ValueKey('shop-emote-${product.emoteId}'),
                          kind:
                              store.data.ownedEmojis.contains(product.emoteId)
                                  ? LunoButtonKind.secondary
                                  : LunoButtonKind.primary,
                          label:
                              store.data.ownedEmojis.contains(product.emoteId)
                                  ? (en ? 'OWNED' : 'SENİN')
                                  : '${product.cost} ${en ? 'GOLD' : 'ALTIN'}',
                          leading:
                              store.data.ownedEmojis.contains(product.emoteId)
                                  ? null
                                  : const LunoCurrencyArt(
                                    LunoAssets.coin,
                                    size: 28,
                                  ),
                          loading: _busy.contains('item:${product.itemId}'),
                          onPressed:
                              _busy.isNotEmpty
                                  ? null
                                  : store.data.ownedEmojis.contains(
                                    product.emoteId,
                                  )
                                  ? () {
                                    if (ModalRoute.of(context)?.isCurrent !=
                                        true) {
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      lunoRoute(
                                        EmojiCollectionScreen(
                                          online: online,
                                          playerStore: store,
                                        ),
                                      ),
                                    );
                                  }
                                  : store.data.gold >= product.cost
                                  ? () =>
                                      unawaited(_buySoftItem(context, product))
                                  : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _pieceSetCard(
    BuildContext context,
    GameStore store,
    _ShopProduct product,
  ) {
    final owned = store.data.ownedPieceSets.contains(product.setId);
    final active = store.data.pieceSet == product.setId;
    final balance = product.gem ? store.data.gems : store.data.gold;
    final affordable = balance >= product.cost;
    return SizedBox(
      width:
          154 +
          (MediaQuery.textScalerOf(context).scale(13) / 13 - 1).clamp(0, 2) *
              60,
      child: _panel(
        accent: const Color(0xFFE3BE77),
        fill: const Color(0xFF292E35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CostumeBoardPreview(
                  setId: product.setId!,
                  bothSides: true,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  backgroundColor:
                      active
                          ? LunoColors.success
                          : owned
                          ? LunoColors.bgRaised
                          : affordable
                          ? LunoColors.gold
                          : LunoColors.bgPanel2,
                  foregroundColor: active ? LunoColors.bgDeep : null,
                ),
                onPressed:
                    active || _busy.isNotEmpty
                        ? null
                        : owned
                        ? () => _activatePieceSet(context, product)
                        : affordable &&
                            !_busy.contains('item:${product.itemId}')
                        ? () => _buySoftItem(context, product)
                        : null,
                child:
                    _busy.contains('item:${product.itemId}') ||
                            _busy.contains('activate-set:${product.setId}')
                        ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : active
                        ? Text(
                          LunoLocalizations.of(context).isEnglish
                              ? 'EQUIPPED'
                              : 'KUŞANILDI',
                          style: const TextStyle(fontSize: 11),
                        )
                        : owned
                        ? Text(
                          LunoLocalizations.of(context).isEnglish
                              ? 'EQUIP'
                              : 'KUŞAN',
                          style: const TextStyle(fontSize: 11),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('${product.cost}'),
                              ),
                            ),
                            const SizedBox(width: 3),
                            LunoCurrencyArt(
                              product.gem ? LunoAssets.gem : LunoAssets.coin,
                              size: 34,
                            ),
                          ],
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopProduct {
  final String itemId;
  final String name;
  final String art;
  final int cost;
  final bool gem;
  final String? setId;
  final String? emoteId;

  const _ShopProduct({
    required this.itemId,
    required this.name,
    required this.art,
    required this.cost,
    required this.gem,
    this.setId,
    this.emoteId,
  });

  String get ownedLabel => '$name HAZIR';

  String get successMessage => '$name hesabına eklendi ve taşların hazır.';
}

final _shopPieceSets = <_ShopProduct>[
  _ShopProduct(
    itemId: 'piece_set:ottoman',
    setId: 'ottoman',
    name: 'OSMANLI',
    art: LunoAssets.setPreview('ottoman'),
    cost: 1000,
    gem: false,
  ),
  _ShopProduct(
    itemId: 'piece_set:roma',
    setId: 'roma',
    name: 'ROMA',
    art: LunoAssets.setPreview('roma'),
    cost: 480,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:brit',
    setId: 'brit',
    name: 'BRİTANYA',
    art: LunoAssets.setPreview('brit'),
    cost: 480,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:viking',
    setId: 'viking',
    name: 'VİKİNG',
    art: LunoAssets.setPreview('viking'),
    cost: 480,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:tasdevri',
    setId: 'tasdevri',
    name: 'TAŞ DEVRİ',
    art: LunoAssets.setPreview('tasdevri'),
    cost: 480,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:samuray',
    setId: 'samuray',
    name: 'SAMURAY',
    art: LunoAssets.setPreview('samuray'),
    cost: 480,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:ice',
    setId: 'ice',
    name: 'BUZ KRALLIĞI',
    art: LunoAssets.setPreview('ice'),
    cost: 720,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:dragon',
    setId: 'dragon',
    name: 'EJDERHA',
    art: LunoAssets.setPreview('dragon'),
    cost: 720,
    gem: true,
  ),
  _ShopProduct(
    itemId: 'piece_set:neon',
    setId: 'neon',
    name: 'NEON KRALLIK',
    art: LunoAssets.setPreview('neon'),
    cost: 980,
    gem: true,
  ),
];

class ShopRewardDialog extends StatefulWidget {
  const ShopRewardDialog({
    super.key,
    required this.title,
    required this.art,
    required this.message,
    this.reward,
    this.pieceSet,
    this.cardUnlock,
    this.emoteId,
    this.playerStore,
    this.online,
  });

  final String title;
  final String art;
  final String message;
  final Widget? reward;
  final String? pieceSet;
  final CardId? cardUnlock;
  final String? emoteId;
  final GameStore? playerStore;
  final LunoOnlineService? online;

  @override
  State<ShopRewardDialog> createState() => _ShopRewardDialogState();
}

class _ShopRewardDialogState extends State<ShopRewardDialog> {
  bool _closing = false;
  final _feedback = GlobalKey<CosmeticPresentationFeedbackState>();

  void _close([bool equip = false]) {
    if (!mounted || _closing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _closing = true;
    _feedback.currentState?.cancel();
    if (widget.pieceSet != null || widget.cardUnlock != null) {
      Navigator.of(context).pop(equip);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => CosmeticPresentationFeedback(
    key: _feedback,
    settleOnCancel: true,
    playerStore: widget.playerStore,
    online: widget.online,
    sound:
        widget.cardUnlock != null
            ? LunoSound.cardUnlock
            : widget.emoteId != null
            ? LunoSound.emoteUnlock
            : widget.pieceSet != null
            ? LunoSound.costumeUnlock
            : LunoSound.reward,
    child: Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: LunoEntrance(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: LunoColors.bgPanel,
            image: lunoFace(
              LunoVisualAssets.premium,
              centerSlice: LunoVisualAssets.rewardPanelSlice,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: LunoType.sectionTitle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (widget.pieceSet != null)
                        CosmeticMatchPreview(setId: widget.pieceSet!)
                      else if (widget.emoteId != null)
                        CosmeticEmoteArt(id: widget.emoteId!, size: 144)
                      else if (widget.cardUnlock != null)
                        Semantics(
                          image: true,
                          label: LunoLocalizations.of(
                            context,
                          ).battleCardName(widget.cardUnlock!),
                          child: ExcludeSemantics(
                            child: IgnorePointer(
                              child: SizedBox(
                                width: 148,
                                height: 218,
                                child: BattleCardTile(
                                  card: widget.cardUnlock!,
                                  cost:
                                      cardDefinitions[widget.cardUnlock!]!.cost,
                                  enabled: true,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        LunoRewardArt(
                          child: LunoArt(widget.art, width: 128, height: 128),
                        ),
                      const SizedBox(height: 8),
                      Text(widget.message, textAlign: TextAlign.center),
                      if (widget.reward != null) ...[
                        const SizedBox(height: 10),
                        widget.reward!,
                      ],
                      if (widget.cardUnlock != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${LunoLocalizations.of(context).isEnglish ? 'Card unlocked' : 'Kart açıldı'}: ${LunoLocalizations.of(context).battleCardName(widget.cardUnlock!)}',
                            style: const TextStyle(
                              color: LunoColors.gold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              LunoButton(
                key: const ValueKey('shop-reward-action'),
                leading: const SizedBox(
                  width: 28,
                  height: 28,
                  child: ClipOval(
                    child: LunoArt('assets/native_art/arena-unlocked-v41.png'),
                  ),
                ),
                onPressed:
                    widget.pieceSet == null && widget.cardUnlock == null
                        ? _close
                        : () => _close(true),
                label:
                    widget.cardUnlock != null
                        ? LunoLocalizations.of(context).isEnglish
                            ? 'EDIT DECK'
                            : 'DESTENİ DÜZENLE'
                        : widget.pieceSet == null
                        ? (LunoLocalizations.of(context).isEnglish
                            ? 'CONTINUE'
                            : 'TAMAM')
                        : LunoLocalizations.of(context).isEnglish
                        ? 'EQUIP'
                        : 'KUŞAN',
              ),
              if (widget.pieceSet != null || widget.cardUnlock != null)
                TextButton(
                  onPressed: _close,
                  child: Text(
                    LunoLocalizations.of(context).isEnglish ? 'LATER' : 'SONRA',
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChestRevealDialog extends StatefulWidget {
  final String chestId;
  final dynamic rewards;

  const ChestRevealDialog({
    super.key,
    required this.chestId,
    required this.rewards,
  });

  @override
  State<ChestRevealDialog> createState() => _ChestRevealDialogState();
}

class _ChestRevealDialogState extends State<ChestRevealDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _motionConfigured = false;
  bool _revealed = false;
  bool _closing = false;
  final _feedback = GlobalKey<CosmeticPresentationFeedbackState>();

  void _close() {
    if (!mounted ||
        _closing ||
        !_revealed ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _closing = true;
    _feedback.currentState?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this, duration: LunoMotion.reward)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _revealed = true);
        }
      });
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scale = Tween<double>(begin: .94, end: 1).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      _revealed = true;
      _controller.value = 1;
    } else if (!_motionConfigured) {
      _controller.forward();
    }
    _motionConfigured = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _feedback.currentState?.cancel();
      _controller.stop();
      if (mounted) setState(() => _revealed = true);
    }
  }

  List<Map<String, dynamic>> get _rewardItems {
    final raw = widget.rewards;
    if (raw is! List) {
      return const [];
    }
    final items = <Map<String, dynamic>>[];
    final seen = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map || item.keys.any((key) => key is! String)) continue;
      if (item['type'] is! String ||
          (item['type'] as String).isEmpty ||
          (item.containsKey('id') && item['id'] is! String) ||
          (item.containsKey('name') && item['name'] is! String) ||
          (item.containsKey('unlocked') && item['unlocked'] is! bool)) {
        continue;
      }
      final amount = item['amount'];
      // Server amounts are safe JSON integers; toInt must not saturate them.
      if (item.containsKey('amount') &&
          (amount is! num ||
              !amount.isFinite ||
              amount <= 0 ||
              amount > 9007199254740991 ||
              amount != amount.roundToDouble())) {
        continue;
      }
      final reward = Map<String, dynamic>.from(item);
      if (seen.any((existing) => mapEquals(existing, reward))) continue;
      seen.add(Map<String, dynamic>.of(reward));
      if (reward['type'] == 'emoji' &&
          reward['unlocked'] == true &&
          items.any(
            (existing) =>
                existing['type'] == 'emoji' &&
                existing['id'] == reward['id'] &&
                existing['unlocked'] == true,
          )) {
        reward['unlocked'] = false;
      }
      items.add(reward);
    }
    return items;
  }

  Color get _accent {
    switch (widget.chestId) {
      case 'royal':
        return const Color(0xFF70D8FF);
      case 'legendary':
        return const Color(0xFFFF8C55);
      case 'rare':
        return const Color(0xFF79C9B3);
      default:
        return LunoColors.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rewards = _rewardItems;
    final en = LunoLocalizations.of(context).isEnglish;
    return CosmeticPresentationFeedback(
      key: _feedback,
      settleOnCancel: true,
      sound:
          !_revealed
              ? null
              : rewards.any(
                (item) =>
                    item['type'] == 'emoji' &&
                    item['unlocked'] == true &&
                    cosmeticEmote(item['id']?.toString() ?? '') != null,
              )
              ? LunoSound.emoteUnlock
              : LunoSound.reward,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.fromLTRB(18, 44, 18, 14),
          decoration: BoxDecoration(
            color: LunoColors.bgPanel,
            image: lunoFace(
              LunoVisualAssets.premium,
              centerSlice: LunoVisualAssets.rewardPanelSlice,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accent.withValues(alpha: .7)),
            boxShadow: [
              BoxShadow(color: _accent.withValues(alpha: .18), blurRadius: 8),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: LunoMotion.adaptive(
                          context,
                          LunoMotion.micro,
                        ),
                        switchInCurve: LunoMotion.screenCurve,
                        switchOutCurve: LunoMotion.screenExitCurve,
                        child: Text(
                          _revealed
                              ? (en ? 'CHEST OPENED' : 'SANDIK AÇILDI')
                              : (en ? 'YOUR REWARDS' : 'ÖDÜLLERİN'),
                          key: ValueKey(_revealed),
                          style: LunoType.sectionTitle.copyWith(color: _accent),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedBuilder(
                        animation: _controller,
                        builder:
                            (_, child) => Transform.scale(
                              scale: _scale.value,
                              child: child,
                            ),
                        child: LunoRewardArt(
                          child: LunoArt(
                            LunoAssets.chest(widget.chestId),
                            width: 96,
                            height: 96,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_revealed)
                        Text(
                          en
                              ? 'Opening your rewards...'
                              : 'Ödüllerin açılıyor...',
                          style: LunoType.bodyMuted,
                          textAlign: TextAlign.center,
                        )
                      else ...[
                        Text(
                          rewards.isEmpty
                              ? (en
                                  ? 'Reward details unavailable.'
                                  : 'Ödül bilgisi alınamadı.')
                              : en
                              ? 'Added to your collection.'
                              : 'Koleksiyonuna eklendi.',
                          style: LunoType.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        if (rewards.isEmpty)
                          const SizedBox.shrink()
                        else
                          Column(
                            children: [
                              for (final reward in rewards)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _rewardRow(reward),
                                ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: LunoButton(
                  key: const ValueKey('chest-reveal-continue'),
                  onPressed:
                      _revealed
                          ? _close
                          : () {
                            if (mounted &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              _controller.value = 1;
                            }
                          },
                  label:
                      _revealed
                          ? (en ? 'CONTINUE' : 'HARİKA')
                          : (en ? 'REVEAL NOW' : 'HEMEN GÖSTER'),
                  backgroundArt: LunoAssets.actionSurfaceV27,
                  leading: const SizedBox(
                    width: 28,
                    height: 28,
                    child: ClipOval(
                      child: LunoArt(
                        'assets/native_art/arena-unlocked-v41.png',
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

  Widget _rewardRow(Map<String, dynamic> item) {
    final en = LunoLocalizations.of(context).isEnglish;
    final amount = item['amount'];
    final suffix = amount is num ? '  x${amount.toInt()}' : '';
    final unlocked = item['unlocked'] == true;
    final emote =
        item['type'] == 'emoji'
            ? cosmeticEmote(item['id']?.toString() ?? '')
            : null;
    CardId? battleCard;
    if (item['type'] == 'battle_card') {
      try {
        battleCard = CardId.parse(item['id']?.toString() ?? '');
      } catch (_) {}
    }
    if (emote != null && unlocked) {
      return Container(
        key: ValueKey('reward-unlocked-emote-${emote.id}'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF14282E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: emote.rarity.color),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              en ? 'NEW EMOTE' : 'YENİ İFADE',
              style: TextStyle(
                color: emote.rarity.color,
                fontWeight: FontWeight.w800,
              ),
            ),
            CosmeticEmoteArt(id: emote.id, size: 100),
            Text(
              emote.title(en),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              en
                  ? 'Ready in your emote collection'
                  : 'İfade koleksiyonunda hazır',
              textAlign: TextAlign.center,
              style: LunoType.bodyMuted,
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: LunoColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LunoColors.line),
      ),
      child: Row(
        children: [
          if (item['type'] == 'skin')
            const SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.grid_view_rounded,
                color: Color(0xFF83C9EF),
                size: 32,
              ),
            )
          else if (battleCard == null)
            LunoArt(_rewardArt(item), width: 44, height: 44)
          else
            SizedBox(
              width: 44,
              height: 44,
              child: BattleCardArt(card: battleCard),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${battleCard == null ? _rewardName(item, en) : LunoLocalizations.of(context).battleCardName(battleCard)}$suffix'
              '${item['type'] == 'skin' ? (en ? '\nCollection > Piece sets > Board frames' : '\nKoleksiyon > Taş kostümleri > Tahta çerçeveleri') : ''}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
          if (unlocked && (item['type'] != 'emoji' || emote != null))
            const SizedBox(
              width: 26,
              height: 26,
              child: ClipOval(
                child: LunoArt('assets/native_art/arena-unlocked-v41.png'),
              ),
            ),
        ],
      ),
    );
  }
}

String _rewardName(Map<String, dynamic> item, bool en) {
  final emote =
      item['type'] == 'emoji'
          ? cosmeticEmote(item['id']?.toString() ?? '')
          : null;
  if (emote != null) {
    return '${emote.title(en)} · ${en ? 'pieces' : 'parça'}';
  }
  if (item['type'] == 'skin') {
    final finish = boardFinish(item['id']?.toString() ?? 'classic');
    return '${finish.title(en)} · ${en ? 'board-frame pieces' : 'tahta çerçevesi parçası'}';
  }
  final name = item['name']?.toString().trim();
  if (!en && name != null && name.isNotEmpty) {
    return name;
  }
  switch (item['type']?.toString()) {
    case 'gold':
      return en ? 'Gold' : 'Altın';
    case 'gems':
      return en ? 'Gems' : 'Elmas';
    case 'card':
      return en ? 'Card' : 'Kart';
    case 'battle_card':
      return en ? 'Battle card' : 'Savaş kartı';
    case 'emoji':
      return en ? 'Emote pieces' : 'İfade parçası';
    case 'skin':
      return en ? 'Board-frame pieces' : 'Tahta çerçevesi parçası';
    case 'frame_shard':
      return en ? 'Avatar-frame pieces' : 'Avatar çerçevesi parçası';
    case 'bioframe_shard':
      return en ? 'Bio-frame pieces' : 'Biyo çerçevesi parçası';
    default:
      return en ? 'Reward' : 'Ödül';
  }
}

String _rewardArt(Map<String, dynamic> item) {
  final type = item['type']?.toString();
  switch (type) {
    case 'gold':
      return LunoAssets.coin;
    case 'gems':
      return LunoAssets.gem;
    case 'emoji':
      final id = item['id']?.toString() ?? '';
      return cosmeticEmote(id) == null
          ? LunoAssets.uiCollectionEmoji
          : LunoAssets.emoji(id);
    case 'card':
      final id = item['id']?.toString() ?? '';
      if (isKnownOwnableKey(id)) {
        return LunoAssets.card(id, GameStore.instance.data.cardLevel[id] ?? 1);
      }
      return LunoAssets.uiCollectionCards;
    case 'skin':
      return LunoAssets.uiCollectionSkins;
    case 'frame_shard':
    case 'bioframe_shard':
      return LunoAssets.profileCrest;
    default:
      return LunoAssets.chestCommon;
  }
}
