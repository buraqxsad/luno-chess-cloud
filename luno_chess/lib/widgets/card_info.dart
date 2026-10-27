import 'package:flutter/material.dart' hide Text;

import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../services/account_operation_guard.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import 'luno_surface.dart';

String cardTargetLabel(CardTarget t) {
  switch (t) {
    case CardTarget.none:
      return 'Hedefsiz';
    case CardTarget.enemy:
      return 'Rakip taş';
    case CardTarget.enemyQueen:
      return 'Rakip vezir';
    case CardTarget.ownPawn:
      return 'Kendi piyon';
    case CardTarget.ownPawnPair:
      return 'İki piyon (yan yana)';
    case CardTarget.ownKnight:
      return 'Kendi at';
    case CardTarget.ownBishop:
      return 'Kendi fil';
    case CardTarget.ownKnBi:
      return 'Kendi at / fil';
    case CardTarget.ownQueen:
      return 'Kendi vezir';
    case CardTarget.ownPiece:
      return 'Kendi taş';
    case CardTarget.empty:
      return 'Boş kare';
    case CardTarget.emptyOwn:
      return 'Kendi yarı alanındaki boş kare';
    case CardTarget.anySq:
      return 'Boş kare';
  }
}

String rarityLabel(CardRarity r) {
  switch (r) {
    case CardRarity.common:
      return 'Sıradan';
    case CardRarity.rare:
      return 'Nadir';
    case CardRarity.legendary:
      return 'Efsanevi';
    case CardRarity.mythic:
      return 'Mitik';
  }
}

/// Koleksiyon ekranındaki kart eylem menüsü.
/// Eski HTML akışındaki "kartı incele / desteye al" kararını tek bir yerde
/// toplar; kilitli kartlar yalnızca ayrıntı gösterir.
void showCardActionMenu(
  BuildContext context,
  String key, {
  required bool owned,
  VoidCallback? onAddToDeck,
  VoidCallback? onRemoveFromDeck,
  GameStore? playerStore,
  LunoOnlineService? online,
}) {
  final c = kCards[key];
  if (c == null ||
      !context.mounted ||
      ModalRoute.of(context)?.isCurrent == false) {
    return;
  }
  var acted = false;
  final owner = AccountOperationGuard(
    playerStore ?? GameStore.instance,
    online ?? LunoOnlineService.instance,
  );
  void perform(BuildContext sheetContext, VoidCallback action) {
    if (acted ||
        !sheetContext.mounted ||
        ModalRoute.of(sheetContext)?.isCurrent != true) {
      return;
    }
    acted = true;
    Navigator.of(sheetContext).pop();
    if (context.mounted && owner.isCurrent) action();
  }

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF29423F),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder:
        (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 76,
                        height: 90,
                        child: LunoArt(LunoAssets.card(key, c.level)),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                LunoArt(
                                  owned
                                      ? 'assets/native_art/status-check-v116.png'
                                      : 'assets/native_art/status-lock-v116.png',
                                  width: 24,
                                  height: 24,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    owned ? 'Koleksiyonunda' : 'Henüz açılmadı',
                                    style: const TextStyle(
                                      color: LunoColors.textDim,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: LunoLocalizations.of(ctx).translate('KAPAT'),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => perform(ctx, () {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LunoButton(
                    label: 'Kart detayları',
                    icon: Icons.info_outline_rounded,
                    kind: LunoButtonKind.secondary,
                    onPressed:
                        () => perform(ctx, () => showCardInfo(context, key)),
                  ),
                  const SizedBox(height: 10),
                  if (owned && onAddToDeck != null)
                    LunoButton(
                      label: 'Desteye ekle',
                      icon: Icons.add_rounded,
                      onPressed: () => perform(ctx, onAddToDeck),
                    ),
                  if (owned && onRemoveFromDeck != null)
                    LunoButton(
                      label: 'Desteden çıkar',
                      kind: LunoButtonKind.danger,
                      icon: Icons.remove_rounded,
                      onPressed: () => perform(ctx, onRemoveFromDeck),
                    ),
                ],
              ),
            ),
          ),
        ),
  );
}

/// Bir kartın tüm bilgilerini gösteren açılır pencere.
void showCardInfo(BuildContext context, String key) {
  final c = kCards[key];
  if (c == null ||
      !context.mounted ||
      ModalRoute.of(context)?.isCurrent == false) {
    return;
  }
  var closed = false;
  showDialog<void>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF29423F),
          scrollable: true,
          titleTextStyle: LunoType.sectionTitle,
          title: Row(
            children: [
              SizedBox(
                width: 64,
                height: 80,
                child: LunoArt(LunoAssets.card(key, c.level)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(c.name)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Mana', '${c.mana} mana'),
              _row('Hedef', cardTargetLabel(c.target)),
              _row('Nadirlik', rarityLabel(c.rarity)),
              if (c.upgradeable)
                _row(
                  'Seviye',
                  LunoLocalizations.of(ctx).cardLevel(c.level, c.maxLevel),
                ),
              if (c.skipMove) _row('Not', 'Oynayınca hamle yapmazsın'),
              const SizedBox(height: 10),
              Text(
                c.desc,
                style: const TextStyle(
                  color: Color(0xFFF2F0E6),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            LunoButton(
              expand: false,
              kind: LunoButtonKind.secondary,
              label: 'KAPAT',
              icon: Icons.close_rounded,
              onPressed: () {
                if (closed ||
                    !ctx.mounted ||
                    ModalRoute.of(ctx)?.isCurrent != true) {
                  return;
                }
                closed = true;
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
  );
}

Widget _row(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        flex: 2,
        child: Text(k, style: const TextStyle(color: LunoColors.textDim)),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 3,
        child: Text(
          v,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  ),
);
