import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;

import '../data/card_pool.dart';
import '../data/rank_catalog.dart';
import '../i18n/luno_text.dart';
import '../models/game_store.dart';
import '../services/luno_online_service.dart';
import '../services/account_operation_guard.dart';
import '../services/luno_feedback.dart';
import '../services/deck_update_result.dart';
import '../services/card_upgrade_result.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/card_info.dart';
import '../widgets/card_upgrade_confirmation.dart';
import '../widgets/currency_bar.dart';
import '../widgets/luno_surface.dart';
import '../widgets/resource_amount.dart';

/// Deste kurma + kart yükseltme.
class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  int selectedSlot = 0;
  final Set<String> _busy = <String>{};

  Future<void> _syncDeckChange(
    List<String> previousDeck,
    AccountOperationGuard guard,
  ) async {
    if (_busy.contains('deck')) return;
    final online = guard.online;
    final submitted = List<String>.of(GameStore.instance.data.deck);
    setState(() => _busy.add('deck'));
    try {
      await online.start().timeout(const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.updatePreferences(deck: submitted);
      final state = validateDeckUpdateResult(result, submitted);
      guard.check();
      if (listEquals(GameStore.instance.data.deck, submitted)) {
        GameStore.instance.applyServerState(state);
      }
    } catch (_) {
      final unchanged =
          guard.isCurrent &&
          listEquals(GameStore.instance.data.deck, submitted);
      if (unchanged) GameStore.instance.replaceDeck(previousDeck);
      if (unchanged && mounted && ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          'Deste kaydı doğrulanamadı. Önceki desten geri yüklendi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove('deck'));
    }
  }

  Future<void> _setDeckSlot(String ownedKey) async {
    if (!mounted || _busy.isNotEmpty) return;
    final store = GameStore.instance;
    if (!isKnownOwnableKey(ownedKey) ||
        !store.data.ownedCards.contains(ownershipKeyForCard(ownedKey))) {
      return;
    }
    final previousDeck = List<String>.of(store.data.deck);
    final guard = AccountOperationGuard(store, LunoOnlineService.instance);
    store.setDeckSlot(selectedSlot, ownedKey);
    await _syncDeckChange(previousDeck, guard);
  }

  Future<void> _removeFromDeck(String ownedKey) async {
    if (!mounted || _busy.isNotEmpty) return;
    final store = GameStore.instance;
    final previousDeck = List<String>.of(store.data.deck);
    final guard = AccountOperationGuard(store, LunoOnlineService.instance);
    if (!store.removeFromDeck(ownedKey)) return;
    await _syncDeckChange(previousDeck, guard);
  }

  Future<void> _upgradeCard(String family) async {
    if (!mounted ||
        _busy.isNotEmpty ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final store = GameStore.instance;
    if (!store.canUpgrade(family)) return;
    final online = LunoOnlineService.instance;
    final guard = AccountOperationGuard(store, online);
    final currentLevel = store.data.cardLevel[family] ?? 1;
    bool stillEligible() =>
        store.canUpgrade(family) &&
        (store.data.cardLevel[family] ?? 1) == currentLevel;
    void showChangedNotice() {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          'Kart veya bakiyen değişti. Güncel bilgileri kontrol edip tekrar dene.',
        );
      }
    }

    setState(() => _busy.add('upgrade:$family'));
    try {
      final accepted = await confirmCardUpgrade(context, family, currentLevel);
      guard.check();
      if (!accepted || !mounted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (!stillEligible()) {
        showChangedNotice();
        return;
      }
      await online.start().timeout(const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!stillEligible()) {
        showChangedNotice();
        return;
      }
      final result = await online.upgradeCard(family, currentLevel + 1);
      final state = validateCardUpgradeResult(result, family, currentLevel + 1);
      guard.check();
      store.applyServerState(state);
      if (guard.isCurrent &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(context, 'Kart yükseltildi.');
      }
    } catch (error) {
      if (guard.isCurrent &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          error is LunoApiException && error.code == 'app-check-required'
              ? 'Güvenli bağlantı doğrulanamadı.'
              : 'Yükseltme doğrulanamadı. Bağlantı yenilendiğinde kartını kontrol et.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove('upgrade:$family'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = GameStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final d = store.data;
        final scaler = MediaQuery.textScalerOf(context);
        final columns = ((MediaQuery.sizeOf(context).width - 20) /
                (scaler.scale(14) > 20 ? 145 : 110))
            .floor()
            .clamp(2, 6);
        final owned = kAllOwnable.where(d.ownedCards.contains).toList();
        final ownedPhysical = ownedPhysicalCardCount(d.ownedCards, d.cardLevel);
        final deck = normalizeDeck(
          d.deck,
          d.ownedCards,
          fallback: kStarterOwned,
        );
        return Scaffold(
          appBar: AppBar(
            backgroundColor: LunoColors.bgPanel,
            title: const Text('DESTE'),
          ),
          body: LunoBackdrop(
            art: LunoAssets.collectionSceneV28,
            overlay: const Color(0x6610141B),
            child: SafeArea(
              top: false,
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: CurrencyBar(),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: LunoColors.bgPanel,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: LunoArt(
                            'assets/native_art/profile-collection-v4.png',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Koleksiyon Puanı: ${store.collectionScore()}   ·   $ownedPhysical/29 kart',
                            maxLines: 3,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: LunoColors.textDim),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'DESTEN (${deck.length}/6)',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisExtent: 110 + scaler.scale(60),
                      children: [
                        for (int i = 0; i < deck.length; i++)
                          _slot(i, deck[i], store),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: LunoColors.bgPanel2),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'KARTLARIN',
                      style: TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: columns,
                    padding: const EdgeInsets.all(10),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 180 + scaler.scale(52),
                    children: [
                      for (final k in owned) _ownedCard(context, k, store),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _slot(int i, String ownedKey, GameStore store) {
    final def = cardForOwned(ownedKey, store.data.cardLevel[ownedKey] ?? 1);
    final sel = i == selectedSlot;
    return Semantics(
      button: true,
      selected: sel,
      label: def.name,
      child: GestureDetector(
        onTap:
            _busy.isNotEmpty
                ? null
                : () {
                  if (!mounted ||
                      _busy.isNotEmpty ||
                      ModalRoute.of(context)?.isCurrent != true) {
                    return;
                  }
                  LunoFeedback.tap();
                  setState(() => selectedSlot = i);
                },
        child: AnimatedContainer(
          duration: LunoMotion.adaptive(context, LunoMotion.cardSelect),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: sel ? LunoColors.bgRaised : LunoColors.bgPanel2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel ? LunoColors.gold : LunoColors.bgPanel2,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 76,
                child: LunoArt(LunoAssets.card(ownedKey, def.level)),
              ),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(30),
                child: Text(
                  def.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ResourceAmount.mana(def.mana, iconSize: 18, fontSize: 12),
              if (isFamily(ownedKey))
                Text(
                  'Sv${store.data.cardLevel[ownedKey] ?? 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: LunoColors.textDim,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ownedCard(BuildContext context, String ownedKey, GameStore store) {
    final lvl = store.data.cardLevel[ownedKey] ?? 1;
    final def = cardForOwned(ownedKey, lvl);
    final inDeck = store.data.deck.contains(ownedKey);
    final canUp = store.canUpgrade(ownedKey);
    final requiredArena = upgradeRequiredArena(ownedKey, lvl);
    final arenaLocked =
        requiredArena != null &&
        arenaIndexForPlayer(store.data.trophies, store.data.arenaIdx) <
            requiredArena;
    return GestureDetector(
      onTap:
          _busy.isNotEmpty
              ? null
              : () => showCardActionMenu(
                context,
                resolvedKey(ownedKey, lvl),
                owned: true,
                onAddToDeck:
                    inDeck ? null : () => unawaited(_setDeckSlot(ownedKey)),
                onRemoveFromDeck:
                    inDeck ? () => unawaited(_removeFromDeck(ownedKey)) : null,
              ),
      onLongPress: () => showCardInfo(context, resolvedKey(ownedKey, lvl)),
      child: Container(
        decoration: BoxDecoration(
          color: LunoColors.bgPanel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: inDeck ? const Color(0xFF5DADA0) : LunoColors.bgPanel2,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 94,
              child: LunoArt(LunoAssets.card(ownedKey, lvl)),
            ),
            const SizedBox(height: 2),
            Text(
              def.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ResourceAmount.mana(def.mana, iconSize: 12, fontSize: 10),
                  if (isFamily(ownedKey))
                    Text(
                      ' · Sv$lvl',
                      style: const TextStyle(
                        fontSize: 10,
                        color: LunoColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            if (isFamily(ownedKey) && lvl < 3)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(48, 48),
                  foregroundColor: canUp ? LunoColors.gold : LunoColors.textDim,
                ),
                onPressed:
                    canUp && _busy.isEmpty
                        ? () => unawaited(_upgradeCard(ownedKey))
                        : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (arenaLocked) ...[
                        const LunoArt(
                          'assets/native_art/status-lock-v116.png',
                          width: 18,
                          height: 18,
                        ),
                        Text(
                          'Arena ${requiredArena + 1} · ',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ] else
                        const Icon(Icons.upgrade_rounded, size: 14),
                      const SizedBox(width: 3),
                      ResourceAmount.coin(
                        upgradeGoldCost(lvl),
                        iconSize: 13,
                        fontSize: 10,
                      ),
                    ],
                  ),
                ),
              )
            else if (inDeck)
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: LunoArt('assets/native_art/status-check-v116.png'),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Destede',
                      style: TextStyle(fontSize: 10, color: LunoColors.success),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
