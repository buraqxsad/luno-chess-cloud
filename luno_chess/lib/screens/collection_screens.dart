import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;

import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../data/card_pool.dart';
import '../engine/piece.dart';
import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/battle_v1_copy.dart';
import '../models/game_store.dart';
import '../models/player_data.dart';
import '../navigation/luno_route.dart';
import '../navigation/luno_account_scope.dart';
import '../services/luno_online_service.dart';
import '../services/luno_audio_service.dart';
import '../services/account_operation_guard.dart';
import '../services/deck_update_result.dart';
import '../services/collection_selection_result.dart';
import '../services/cosmetic_catalog.dart';
import '../navigation/luno_account_modal.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/card_info.dart';
import '../widgets/luno_surface.dart';
import '../widgets/resource_amount.dart';
import '../widgets/cosmetic_match_preview.dart';
import '../widgets/cosmetic_emote_art.dart';
import '../widgets/luno_polish.dart';
import '../battle_ui/art.dart';
import '../battle_ui/tokens.dart';
import 'deck_screen.dart';
import 'shop_screen.dart' show ShopScreen;
import 'board_finishes_screen.dart';

/// Historical card collection, not the Battle V1 production catalog.
/// New V1 collection/deck features belong to BattleDeckScreen.
class CardCollectionScreen extends StatefulWidget {
  const CardCollectionScreen({super.key});

  @override
  State<CardCollectionScreen> createState() => _CardCollectionScreenState();
}

class _CardCollectionScreenState extends State<CardCollectionScreen> {
  bool _savingDeck = false;

  Future<void> _removeCard(String ownedKey) async {
    if (!mounted || _savingDeck) return;
    final store = GameStore.instance;
    final previous = List<String>.of(store.data.deck);
    final online = LunoOnlineService.instance;
    final guard = AccountOperationGuard(store, online);
    if (!store.removeFromDeck(ownedKey)) return;
    final submitted = List<String>.of(store.data.deck);
    setState(() => _savingDeck = true);
    try {
      await online.start().timeout(const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await online.updatePreferences(deck: submitted);
      final state = validateDeckUpdateResult(result, submitted);
      guard.check();
      if (listEquals(store.data.deck, submitted)) store.applyServerState(state);
    } catch (_) {
      final unchanged =
          guard.isCurrent && listEquals(store.data.deck, submitted);
      if (unchanged) store.replaceDeck(previous);
      if (unchanged && mounted && ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          'Deste kaydı doğrulanamadı. Önceki desten geri yüklendi.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingDeck = false);
    }
  }

  static const _sections = <(CardRarity, String)>[
    (CardRarity.common, 'SIRADAN KARTLAR'),
    (CardRarity.rare, 'NADİR KARTLAR'),
    (CardRarity.legendary, 'EFSANEVİ KARTLAR'),
    (CardRarity.mythic, 'MİTİK KARTLAR'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = GameStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KART KOLEKSİYONU'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ListenableBuilder(
                listenable: store,
                builder:
                    (context, _) => Text(
                      '${ownedPhysicalCardCount(store.data.ownedCards, store.data.cardLevel)}/29',
                      style: const TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.collection,
        overlay: const Color(0xE6100A24),
        focalPoint: const Alignment(0, -.22),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
          children: [
            LunoSurface(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const LunoIconBadge(
                    icon: Icons.auto_awesome_rounded,
                    color: LunoColors.gold,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: store,
                      builder:
                          (context, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'KART ARŞİVİ',
                                style: TextStyle(
                                  color: LunoColors.gold,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .9,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${store.collectionScore()} koleksiyon puanı',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Bir karta dokunarak mana, hedef ve etkisini gör.',
                                style: TextStyle(
                                  color: LunoColors.textDim,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final section in _sections) ...[
              _SectionHeading(title: section.$2),
              const SizedBox(height: 7),
              ListenableBuilder(
                listenable: store,
                builder: (context, _) => _cardGrid(context, section.$1),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardGrid(BuildContext context, CardRarity rarity) {
    final entries =
        kCards.entries.where((entry) => entry.value.rarity == rarity).toList();
    final store = GameStore.instance;
    final scaler = MediaQuery.textScalerOf(context);
    final columns = ((MediaQuery.sizeOf(context).width - 28) /
            (scaler.scale(12) > 18 ? 145 : 115))
        .floor()
        .clamp(2, 6);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 120 + scaler.scale(52),
      ),
      itemBuilder: (context, index) {
        final def = entries[index].value;
        final ownedKey = def.family.isNotEmpty ? def.family : def.key;
        final familyLevel =
            def.family.isNotEmpty
                ? store.data.cardLevel[def.family] ?? 1
                : def.level;
        final owned =
            def.family.isNotEmpty
                ? store.data.ownedCards.contains(def.family) &&
                    familyLevel >= def.level
                : store.data.ownedCards.contains(def.key);
        return _CardTile(
          def: def,
          owned: owned,
          level: def.level,
          onTap:
              () => showCardActionMenu(
                context,
                def.key,
                owned: owned,
                onAddToDeck:
                    !_savingDeck && owned && !store.data.deck.contains(ownedKey)
                        ? () => Navigator.of(
                          context,
                        ).push(lunoRoute(const DeckScreen()))
                        : null,
                onRemoveFromDeck:
                    !_savingDeck && owned && store.data.deck.contains(ownedKey)
                        ? () => unawaited(_removeCard(ownedKey))
                        : null,
              ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: LunoType.sectionTitle.copyWith(letterSpacing: 0),
          ),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final CardDef def;
  final bool owned;
  final int level;
  final VoidCallback onTap;

  const _CardTile({
    required this.def,
    required this.owned,
    required this.level,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final artKey = def.key;
    final border = switch (def.rarity) {
      CardRarity.common => LunoColors.bgPanel2,
      CardRarity.rare => LunoColors.success.withValues(alpha: .72),
      CardRarity.legendary => const Color(0xFFD4A8FF),
      CardRarity.mythic => LunoColors.gold,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient:
              owned
                  ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [LunoColors.bgPanel, LunoColors.bgPanel2],
                  )
                  : const LinearGradient(
                    colors: [Color(0xFF283D41), Color(0xFF233235)],
                  ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: owned ? 1.5 : 1),
          boxShadow:
              owned
                  ? [
                    BoxShadow(
                      color: border.withValues(alpha: .12),
                      blurRadius: 10,
                    ),
                  ]
                  : null,
        ),
        child: Stack(
          children: [
            Opacity(
              opacity: owned ? 1 : .65,
              child: Column(
                children: [
                  SizedBox(
                    height: 96,
                    child: LunoArt(
                      LunoAssets.card(artKey, def.level),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(30),
                    child: Text(
                      def.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LunoType.label.copyWith(
                        color: LunoColors.ivory,
                        fontSize: 12,
                        height: 1.2,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  ResourceAmount.mana(def.mana, iconSize: 16, fontSize: 12),
                ],
              ),
            ),
            if (!owned)
              const Positioned(
                left: 0,
                top: 0,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: LunoArt('assets/native_art/status-lock-v116.png'),
                ),
              ),
            if (def.family.isNotEmpty)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LunoColors.goldDeep,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${LunoLocalizations.of(context).isEnglish ? 'LV' : 'SV'}$level',
                    style: const TextStyle(
                      color: LunoColors.bgDeep,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PieceCostumeScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const PieceCostumeScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<PieceCostumeScreen> createState() => _PieceCostumeScreenState();
}

class _PieceCostumeScreenState extends State<PieceCostumeScreen> {
  static const _sets = <(String, String, String)>[
    ('luno', 'LUNO', 'STANDART'),
    ('ottoman', 'OTTOMAN', 'NADİR'),
    ('roma', 'ROMA', 'NADİR'),
    ('brit', 'BRİTANYA', 'NADİR'),
    ('viking', 'VİKİNG', 'NADİR'),
    ('tasdevri', 'TAŞ DEVRİ', 'NADİR'),
    ('samuray', 'SAMURAY', 'NADİR'),
    ('ice', 'BUZ KRALLIĞI', 'EFSANEVİ'),
    ('dragon', 'EJDERHA', 'EFSANEVİ'),
    ('neon', 'NEON KRALLIK', 'MİTİK'),
  ];
  final Set<String> _saving = <String>{};
  PieceColor _previewColor = PieceColor.white;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;

  bool _previewOpen = false;
  int _equipPresentation = 0;

  final _equipFeedback = GlobalKey<CosmeticPresentationFeedbackState>();

  Future<void> _previewSet(String id, String name) async {
    if (!mounted || _previewOpen || _saving.isNotEmpty ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    _previewOpen = true;
    try {
      final equip = await showLunoAccountBottomSheet<bool>(
        context: context, service: online, playerStore: store,
        builder: (_) => _CostumePreviewSheet(
          id: id, name: name, store: store,
        ),
      );
      if (equip == true && mounted && guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        await _selectPieceSet(context, id);
      }
    } finally {
      _previewOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = this.store;
    return CosmeticPresentationFeedback(
      key: _equipFeedback,
      playerStore: store,
      online: online,
      sequence: _equipPresentation,
      sound: _equipPresentation == 0 ? null : LunoSound.costumeEquip,
      child: Scaffold(
      appBar: AppBar(title: const Text('TAŞ KOSTÜMLERİ')),
      body: LunoBackdrop(
        art: LunoAssets.collection,
        overlay: const Color(0xE8100A24),
        focalPoint: const Alignment(0, .15),
        child: ListenableBuilder(
          listenable: store,
          builder:
              (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: LunoArt(LunoAssets.uiCollectionSkins),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'TAHTA STİLİNİ SEÇ\nSeçtiğin set maç tahtasında kullanılır.',
                            style: TextStyle(
                              color: LunoColors.textDim,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<PieceColor>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: PieceColor.white,
                        label: Text('Beyaz'),
                      ),
                      ButtonSegment(
                        value: PieceColor.black,
                        label: Text('Siyah'),
                      ),
                    ],
                    selected: {_previewColor},
                    onSelectionChanged: (selection) {
                      if (!mounted ||
                          ModalRoute.of(context)?.isCurrent != true) {
                        return;
                      }
                      setState(() => _previewColor = selection.single);
                    },
                    style: SegmentedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      selectedBackgroundColor: LunoColors.bgRaised,
                      selectedForegroundColor: LunoColors.ivory,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LunoButton(
                    key: const ValueKey('collection-board-finishes'),
                    label: LunoLocalizations.of(context).isEnglish
                        ? 'CHEST COLLECTION · BOARD FRAMES' : 'SANDIK KOLEKSİYONU · TAHTA ÇERÇEVELERİ',
                    icon: Icons.grid_4x4_rounded,
                    kind: LunoButtonKind.secondary,
                    onPressed: () {
                      if (_saving.isNotEmpty || ModalRoute.of(context)?.isCurrent != true) return;
                      Navigator.of(context).push(lunoRoute(BoardFinishesScreen(online: online, playerStore: store)));
                    },
                  ),
                  const SizedBox(height: 14),
                  for (final item in _sets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PieceSetTile(
                        id: item.$1,
                        name: item.$2,
                        rarity: item.$3,
                        previewColor: _previewColor,
                        active: store.data.pieceSet == item.$1,
                        owned: store.data.ownedPieceSets.contains(item.$1),
                        saving: _saving.contains(item.$1),
                        onPreview: () => unawaited(_previewSet(item.$1, item.$2)),
                        onTap:
                            store.data.ownedPieceSets.contains(item.$1) &&
                                    _saving.isEmpty
                                ? () =>
                                    unawaited(_selectPieceSet(context, item.$1))
                                : null,
                        onShop: () {
                          if (_saving.isNotEmpty ||
                              ModalRoute.of(context)?.isCurrent != true) {
                            return;
                          }
                          Navigator.of(context).push(
                            lunoRoute(
                              ShopScreen(
                                online: online,
                                playerStore: store,
                                cosmeticsOnly: true,
                                focusPieceSet: item.$1,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
        ),
      ),
      ),
    );
  }

  Future<void> _selectPieceSet(BuildContext context, String pieceSet) async {
    if (!mounted ||
        _saving.isNotEmpty ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final store = this.store;
    if (!store.data.ownedPieceSets.contains(pieceSet) ||
        store.data.pieceSet == pieceSet) {
      return;
    }
    final previous = store.data.pieceSet;
    final online = this.online;
    final guard = AccountOperationGuard(store, online);
    var epoch = store.serverStateEpoch;
    bool current() => guard.isCurrent && store.serverStateEpoch == epoch &&
        identical(store, this.store) && identical(online, this.online);
    if (mounted) {
      setState(() => _saving.add(pieceSet));
    }
    try {
      final bootstrap = online.start();
      epoch = store.serverStateEpoch;
      await bootstrap.timeout(const Duration(seconds: 12));
      guard.check();
      if (!current()) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      if (!mounted || !context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final result = await online.setPieceSet(pieceSet)
          .timeout(const Duration(seconds: 12));
      final state = validatePieceSetResult(result, pieceSet);
      guard.check();
      final inventory = state['inventory'] as Map;
      final owned = inventory['ownedSets'];
      if (inventory.containsKey('ownedSets') &&
          (owned is! List || !owned.contains(pieceSet == 'luno' ? 'std' : pieceSet))) {
        throw const FormatException('Equipped set is not owned');
      }
      if (!current() || store.data.pieceSet != previous) return;
      store.applyServerState(state);
      if (current() && store.data.pieceSet == pieceSet &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _equipPresentation++);
        showLunoNotice(
          context,
          LunoLocalizations.of(context).isEnglish
              ? 'Equipped. Your pieces are ready for the next battle.'
              : 'Kuşanıldı. Taşların sonraki maç için hazır.',
        );
      }
    } catch (error) {
      if (mounted && current() && store.data.pieceSet == previous &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        final l = LunoLocalizations.of(context);
        showLunoNotice(context, error is TimeoutException
            ? l.translate('Taş seti sunucuya kaydedilemedi.')
            : l.isEnglish
                ? 'Could not equip this set. Try again.'
                : 'Taş seti kuşanılamadı. Tekrar dene.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving.remove(pieceSet));
      }
    }
  }
}

/// A bounded cosmetic presentation owns SFX only while its cue can be audible.
class CosmeticPresentationFeedback extends StatefulWidget {
  const CosmeticPresentationFeedback({super.key, required this.child,
    this.sound, this.sequence = 0, this.playerStore, this.online,
    this.settleOnCancel = false});
  final Widget child;
  final LunoSound? sound;
  final int sequence;
  final GameStore? playerStore;
  final LunoOnlineService? online;
  final bool settleOnCancel;

  @override
  CosmeticPresentationFeedbackState createState() => CosmeticPresentationFeedbackState();
}

class CosmeticPresentationFeedbackState extends State<CosmeticPresentationFeedback>
    with WidgetsBindingObserver {
  GameStore get _store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  late AccountOperationGuard _guard;
  late int _epoch;
  Timer? _tail;
  Timer? _ownerWatch;
  bool _cancelled = false;
  bool _scheduled = false;
  bool _ownsEffects = false;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    _captureOwner();
    _store.addListener(_checkOwner);
    _online.addListener(_checkOwner);
    WidgetsBinding.instance.addObserver(this);
  }

  void _captureOwner() {
    _guard = AccountOperationGuard(_store, _online);
    _epoch = _store.serverStateEpoch;
  }

  bool get _current => _guard.isCurrent && _store.serverStateEpoch == _epoch;
  void _checkOwner() { if (!_current) cancel(); }

  void cancel() {
    final changed = !_cancelled;
    _cancelled = true;
    _tail?.cancel();
    _ownerWatch?.cancel();
    if (_ownsEffects) LunoAudioService.instance.cancelEffects();
    _ownsEffects = false;
    if (changed && mounted && !_disposing && widget.settleOnCancel) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CosmeticPresentationFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStore = oldWidget.playerStore ?? GameStore.instance;
    final oldOnline = oldWidget.online ?? LunoOnlineService.instance;
    if (!identical(oldStore, _store) || !identical(oldOnline, _online)) {
      cancel();
      oldStore.removeListener(_checkOwner);
      oldOnline.removeListener(_checkOwner);
      _store.addListener(_checkOwner);
      _online.addListener(_checkOwner);
    }
    if (widget.sequence != oldWidget.sequence) {
      cancel();
      _captureOwner();
      _cancelled = false;
      _scheduled = false;
    }
    _checkOwner();
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled || ModalRoute.of(context)?.isCurrent != true) {
      cancel();
    }
    _schedule();
  }

  void _schedule() {
    final sound = widget.sound;
    if (sound == null || _scheduled || _cancelled || !_current) return;
    _scheduled = true;
    final sequence = widget.sequence;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cancelled || !_current || widget.sequence != sequence ||
          !TickerMode.valuesOf(context).enabled || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _ownsEffects = true;
      unawaited(LunoAudioService.instance.playEffect(sound,
        isCurrent: () => mounted && !_cancelled && _current &&
            widget.sequence == sequence && TickerMode.valuesOf(context).enabled &&
            ModalRoute.of(context)?.isCurrent == true));
      // Covers the longest cosmetic cue plus the service's preparation budget.
      _tail = Timer(const Duration(seconds: 2), () {
        _ownsEffects = false;
        _ownerWatch?.cancel();
      });
      _ownerWatch = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || !_current || ModalRoute.of(context)?.isCurrent != true) cancel();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }

  @override
  void dispose() {
    _disposing = true;
    cancel();
    _store.removeListener(_checkOwner);
    _online.removeListener(_checkOwner);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_cancelled || !widget.settleOnCancel
      ? widget.child
      : TickerMode(enabled: false, child: MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: widget.child));
}

class _PieceSetTile extends StatelessWidget {
  final String id;
  final String name;
  final String rarity;
  final PieceColor previewColor;
  final bool active;
  final bool owned;
  final bool saving;
  final VoidCallback? onTap;
  final VoidCallback onShop;
  final VoidCallback onPreview;

  const _PieceSetTile({
    required this.id,
    required this.name,
    required this.rarity,
    required this.previewColor,
    required this.active,
    required this.owned,
    required this.saving,
    required this.onTap,
    required this.onShop,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        !owned
            ? LunoColors.textDim
            : rarity == 'MİTİK'
            ? LunoColors.gold
            : rarity == 'EFSANEVİ'
            ? const Color(0xFFD4A8FF)
            : const Color(0xFF5FE0C0);
    final en = LunoLocalizations.of(context).isEnglish;
    final rarityLabel = !en ? rarity : switch (rarity) {
      'STANDART' => 'Standard', 'NADİR' => 'Rare',
      'EFSANEVİ' => 'Legendary', _ => 'Mythic',
    };
    return Material(
      color: const Color(0xFF14282E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: active ? color : color.withValues(alpha: .25)),
      ),
      child: InkWell(
        onTap: onPreview,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LunoLocalizations.of(context).pieceSetTitle(id, name),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$rarityLabel · ${owned ? (en ? 'Owned' : 'Sahipsin') : (en ? 'Locked' : 'Kilitli')}',
                          style: const TextStyle(
                            color: LunoColors.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('costume-preview-$id'),
                    tooltip: en ? 'Board preview' : 'Tahtada önizle',
                    onPressed: onPreview,
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                  if (!owned || active)
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: LunoArt(
                        !owned
                            ? 'assets/native_art/status-lock-v116.png'
                            : 'assets/native_art/status-check-v116.png',
                      ),
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: LunoColors.gold,
                    ),
                ],
              ),
              const SizedBox(height: 7),
              CostumeBoardPreview(setId: id, color: previewColor),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(costumeSource(id, en),
                  style: const TextStyle(color: LunoColors.textDim, fontSize: 13, height: 1.35)),
              ),
              const SizedBox(height: 10),
              LunoButton(
                key: ValueKey('costume-equip-$id'),
                loading: saving,
                onPressed:
                    saving || active
                        ? null
                        : owned
                        ? onTap
                        : onShop,
                label:
                    saving
                        ? (en ? 'SAVING' : 'KAYDEDİLİYOR')
                        : active
                        ? (en ? 'EQUIPPED' : 'KUŞANILDI')
                        : owned
                        ? (en ? 'EQUIP' : 'KUŞAN')
                        : (en ? 'VIEW IN SHOP' : 'MAĞAZADA GÖR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uses the same square colors and piece files as the production battle.
class CostumeBoardPreview extends StatelessWidget {
  const CostumeBoardPreview({
    super.key,
    required this.setId,
    this.color = PieceColor.white,
    this.bothSides = false,
  });
  final String setId;
  final PieceColor color;
  final bool bothSides;
  static const types = [
    PieceType.king,
    PieceType.queen,
    PieceType.rook,
    PieceType.bishop,
    PieceType.knight,
    PieceType.pawn,
  ];

  static String assetFor(String set, PieceColor side, PieceType type) =>
      BattleArt.piecePath(side, type, set: set);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cell = (box.maxWidth / 6).clamp(20.0, 64.0);
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: cell * 6,
          height: cell * (bothSides ? 2 : 1),
          child: Column(
            children: [
              for (final side in bothSides ? PieceColor.values : [color])
                Row(
                  children: [
                    for (var i = 0; i < types.length; i++)
                      Semantics(
                        label:
                            '${LunoLocalizations.of(context).battlePiece(types[i])}, ${LunoLocalizations.of(context).battle(side.isWhite ? BattleCopy.white : BattleCopy.black)}',
                        image: true,
                        child: SizedBox(
                          width: cell,
                          height: cell,
                          child: ColoredBox(
                            color:
                                (i + (side == PieceColor.white ? 0 : 1)).isEven
                                    ? BattleTokens.lightSquare
                                    : BattleTokens.darkSquare,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Image.asset(
                                assetFor(setId, side, types[i]),
                                fit: BoxFit.contain,
                                cacheWidth:
                                    (cell *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .ceil(),
                                errorBuilder:
                                    (_, _, _) => Image.asset(
                                      BattleArt.piecePath(side, types[i]),
                                      fit: BoxFit.contain,
                                    ),
                              ),
                            ),
                          ),
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

class _CostumePreviewSheet extends StatefulWidget {
  const _CostumePreviewSheet({required this.id, required this.name, required this.store});
  final String id, name;
  final GameStore store;
  @override
  State<_CostumePreviewSheet> createState() => _CostumePreviewSheetState();
}

class _CostumePreviewSheetState extends State<_CostumePreviewSheet> {
  PieceColor _side = PieceColor.white;
  @override
  Widget build(BuildContext context) {
    final en = LunoLocalizations.of(context).isEnglish;
    final owned = widget.store.data.ownedPieceSets.contains(widget.id);
    final equipped = widget.store.data.pieceSet == widget.id;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(LunoLocalizations.of(context).pieceSetTitle(widget.id, widget.name),
            style: LunoType.sectionTitle, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(owned ? (en ? 'Complete set · 6 piece types, both sides' : 'Tam set · 6 taş türü, iki takım')
              : costumeSource(widget.id, en),
            textAlign: TextAlign.center, style: LunoType.bodyMuted),
          if (owned) Text(costumeSource(widget.id, en),
            textAlign: TextAlign.center, style: LunoType.bodyMuted),
          const SizedBox(height: 12),
          SegmentedButton<PieceColor>(
            segments: [
              ButtonSegment(value: PieceColor.white, label: Text(en ? 'White' : 'Beyaz')),
              ButtonSegment(value: PieceColor.black, label: Text(en ? 'Black' : 'Siyah')),
            ],
            selected: {_side},
            onSelectionChanged: (value) => setState(() => _side = value.single),
          ),
          const SizedBox(height: 12),
          CosmeticMatchPreview(setId: widget.id, side: _side),
            ]),
          )),
          const SizedBox(height: 16),
          if (owned)
            LunoButton(
              key: ValueKey('costume-preview-equip-${widget.id}'),
              label: equipped ? (en ? 'EQUIPPED' : 'KUŞANILDI') : (en ? 'EQUIP' : 'KUŞAN'),
              onPressed: equipped ? null : () => dismissLunoAccountModal(context, true),
            ),
          TextButton(onPressed: () => dismissLunoAccountModal(context),
            child: Text(en ? 'CLOSE' : 'KAPAT')),
        ]),
      ),
    );
  }
}

class EmojiCollectionScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const EmojiCollectionScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<EmojiCollectionScreen> createState() => _EmojiCollectionScreenState();
}

class _EmojiCollectionScreenState extends State<EmojiCollectionScreen> {
  static const _ids = kEmojiIds;

  bool saving = false;
  bool _previewOpen = false;
  String? _pendingId;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant EmojiCollectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.playerStore ?? GameStore.instance;
    if (!identical(previous, store)) {
      previous.removeListener(_refresh);
      store.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _previewEmoji(String id) async {
    if (!mounted || saving || _previewOpen || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final item = cosmeticEmote(id);
    if (item == null) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    _previewOpen = true;
    try {
      final select = await showLunoAccountBottomSheet<bool>(
        context: context, service: online, playerStore: store,
        builder: (_) => _EmotePreviewSheet(item: item, store: store, online: online),
      );
      if (select == true && mounted && guard.isCurrent && ModalRoute.of(context)?.isCurrent == true) {
        await _toggleEmoji(id);
      }
    } finally {
      _previewOpen = false;
    }
  }

  Future<void> _toggleEmoji(String id) async {
    if (!mounted || saving || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final store = this.store;
    if (!store.data.ownedEmojis.contains(id)) {
      return;
    }
    final previous = List<String>.of(store.data.emojiLoadout);
    final online = this.online;
    final guard = AccountOperationGuard(store, online);
    final next = List<String>.of(previous);
    var epoch = store.serverStateEpoch;
    bool current() => guard.isCurrent && store.serverStateEpoch == epoch &&
        identical(store, this.store) && identical(online, this.online);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      if (next.length >= 4) {
        _toast(LunoLocalizations.of(context).isEnglish
            ? 'You can select up to 4 quick emotes.'
            : 'Maçta en fazla 4 hızlı ifade kullanabilirsin.');
        return;
      }
      next.add(id);
    }
    store.setEmojiLoadout(next);
    setState(() { saving = true; _pendingId = id; });
    try {
      final bootstrap = online.start();
      epoch = store.serverStateEpoch;
      await bootstrap.timeout(const Duration(seconds: 12));
      guard.check();
      if (!current()) return;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        if (listEquals(store.data.emojiLoadout, next)) {
          store.setEmojiLoadout(previous);
        }
        return;
      }
      final result = await online.updatePreferences(emojiLoadout: next)
          .timeout(const Duration(seconds: 12));
      final state = validateEmojiLoadoutResult(result, next);
      guard.check();
      if (!current()) return;
      if (listEquals(store.data.emojiLoadout, next)) {
        store.applyServerState(state);
      }
    } catch (_) {
      if (current() && listEquals(store.data.emojiLoadout, next)) {
        store.setEmojiLoadout(previous);
      }
      if (current() && mounted) {
        _toast(LunoLocalizations.of(context).isEnglish
            ? 'Could not save emotes. Try again.'
            : 'İfadeler kaydedilemedi. Tekrar dene.');
      }
    } finally {
      if (mounted) {
        setState(() { saving = false; _pendingId = null; });
      }
    }
  }

  void _toast(String message) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    showLunoNotice(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final store = this.store;
    final en = LunoLocalizations.of(context).isEnglish;
    return Scaffold(
      appBar: AppBar(title: const Text('EMOJİ KOLEKSİYONU')),
      body: LunoBackdrop(
        art: LunoAssets.collection,
        overlay: const Color(0xE8100A24),
        focalPoint: const Alignment(0, .3),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: LunoArt(LunoAssets.uiCollectionEmoji),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MAÇ İFADELERİ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          LunoLocalizations.of(
                            context,
                          ).selectedEmotes(store.data.emojiLoadout.length),
                          style: const TextStyle(
                            color: LunoColors.gold,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 352),
              child: Row(children: [
              for (var slot = 0; slot < 4; slot++) ...[
                if (slot > 0) const SizedBox(width: 8),
                Expanded(child: AspectRatio(aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14282E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: LunoColors.line),
                    ),
                    child: slot < store.data.emojiLoadout.length
                      ? InkWell(
                          onTap: saving ? null : () => unawaited(_toggleEmoji(store.data.emojiLoadout[slot])),
                          child: Padding(padding: const EdgeInsets.all(5),
                            child: LunoArt(LunoAssets.emoji(store.data.emojiLoadout[slot]))),
                        )
                      : Center(child: Icon(Icons.add_rounded, color: LunoColors.textDim.withValues(alpha: .55))),
                  ),
                )),
              ],
            ]))),
            if (saving) ...[
              const SizedBox(height: 10),
              Text(en ? 'Saving selection...' : 'Seçim kaydediliyor...',
                textAlign: TextAlign.center, style: LunoType.bodyMuted),
            ],
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ids.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ((MediaQuery.sizeOf(context).width - 28) /
                    MediaQuery.textScalerOf(context).scale(130).clamp(130, 182))
                    .floor()
                    .clamp(2, 6),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent:
                    114 + MediaQuery.textScalerOf(context).scale(98),
              ),
              itemBuilder: (context, index) {
                final owned = store.data.ownedEmojis.contains(_ids[index]);
                final active =
                    owned && store.data.emojiLoadout.contains(_ids[index]);
                final item = cosmeticEmotes[index];
                return LunoPressFeedback(child: InkWell(
                  key: ValueKey('emote-select-${item.id}'),
                  onTap:
                      owned && !saving
                          ? () => unawaited(_toggleEmoji(_ids[index]))
                          : !saving ? () => unawaited(_previewEmoji(_ids[index])) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF25443F) : const Color(0xFF14282E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active ? LunoColors.gold : item.rarity.color.withValues(alpha: .35),
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Stack(children: [SizedBox(
                          width: double.infinity,
                          height: 80,
                          child: Opacity(
                            opacity: owned ? 1 : .60,
                            child: LunoArt(LunoAssets.emoji(_ids[index])),
                          ),
                        ), Positioned(right: -8, top: -8,
                          child: IconButton(
                            key: ValueKey('emote-preview-${item.id}'),
                            tooltip: en ? 'Preview and unlock' : 'Önizleme ve kazanım',
                            onPressed: saving ? null : () => unawaited(_previewEmoji(item.id)),
                            icon: const Icon(Icons.info_outline_rounded, size: 19),
                          )),
                        ]),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: MediaQuery.textScalerOf(context).scale(38),
                          child: Text(
                            item.title(en),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: LunoType.label.copyWith(
                              color: LunoColors.ivory,
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(item.rarity.title(en), style: TextStyle(
                          color: item.rarity.color, fontSize: 12, height: 1.25)),
                        const SizedBox(height: 6),
                        Text(
                          saving && _pendingId == item.id
                              ? (en ? 'SAVING' : 'KAYDEDİLİYOR')
                              : !owned
                              ? (en ? 'LOCKED' : 'KİLİTLİ')
                              : active
                              ? (en ? 'SELECTED' : 'SEÇİLİ')
                              : (en ? 'SELECT' : 'KULLAN'),
                          style: TextStyle(
                            color:
                                active
                                    ? LunoColors.success
                                    : LunoColors.textDim,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmotePreviewSheet extends StatefulWidget {
  const _EmotePreviewSheet({required this.item, required this.store, required this.online});
  final CosmeticEmote item;
  final GameStore store;
  final LunoOnlineService online;
  @override
  State<_EmotePreviewSheet> createState() => _EmotePreviewSheetState();
}

class _EmotePreviewSheetState extends State<_EmotePreviewSheet> {
  int _replay = 0;
  int? _pieces;
  bool _loading = false;
  bool _failed = false;
  bool _progressRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_progressRequested && widget.online.isOnline) {
      _progressRequested = true;
      unawaited(_readProgress());
    }
  }

  Future<void> _readProgress() async {
    if (_loading || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final guard = AccountOperationGuard(widget.store, widget.online);
    final epoch = widget.store.serverStateEpoch;
    setState(() { _loading = true; _failed = false; });
    try {
      final result = await widget.online.api('/getPlayerState', const {})
          .timeout(const Duration(seconds: 12));
      guard.check();
      if (widget.store.serverStateEpoch != epoch) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          setState(() { _pieces = null; _failed = true; });
        }
        return;
      }
      final state = result['state'];
      final inventory = state is Map ? state['inventory'] : null;
      final counts = inventory is Map ? inventory['emojiPieces'] : null;
      final count = counts is Map
          ? (counts.containsKey(widget.item.id) ? counts[widget.item.id] : 0)
          : null;
      if (result['ok'] != true || count is! int || count < 0) {
        throw const FormatException('Unconfirmed emote progress');
      }
      if (mounted && guard.isCurrent && widget.store.serverStateEpoch == epoch && ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _pieces = count.clamp(0, widget.item.piecesRequired));
      }
    } catch (_) {
      if (mounted && guard.isCurrent && ModalRoute.of(context)?.isCurrent == true) {
        setState(() {
          if (widget.store.serverStateEpoch != epoch) _pieces = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = LunoLocalizations.of(context).isEnglish;
    final owned = widget.store.data.ownedEmojis.contains(widget.item.id);
    final selected = widget.store.data.emojiLoadout.contains(widget.item.id);
    return SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.item.title(en), textAlign: TextAlign.center,
          style: LunoType.sectionTitle),
        const SizedBox(height: 6),
        Text(widget.item.rarity.title(en),
          style: TextStyle(color: widget.item.rarity.color, fontWeight: FontWeight.w700)),
        CosmeticEmoteArt(key: ValueKey(_replay), id: widget.item.id, size: 160),
        IconButton(tooltip: en ? 'Replay expression' : 'İfadeyi yeniden oynat',
          onPressed: () => setState(() => _replay++), icon: const Icon(Icons.replay_rounded)),
        Text(owned ? (en ? 'Owned · available in matches' : 'Sahipsin · maçlarda kullanabilirsin')
            : widget.item.source(en), textAlign: TextAlign.center,
          style: LunoType.bodyMuted),
        if (owned) Text(widget.item.source(en), textAlign: TextAlign.center,
          style: LunoType.bodyMuted),
        if (!owned && _pieces != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _pieces! / widget.item.piecesRequired,
            color: widget.item.rarity.color, minHeight: 6),
          const SizedBox(height: 6),
          Text('$_pieces / ${widget.item.piecesRequired} ${en ? 'pieces' : 'parça'}'),
        ],
        if (!owned && _loading) const Padding(padding: EdgeInsets.all(12),
          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        if (!owned && _failed) TextButton.icon(
          onPressed: _readProgress, icon: const Icon(Icons.refresh_rounded),
          label: Text(en ? 'Retry progress' : 'İlerlemeyi tekrar yükle')),
        const SizedBox(height: 16),
        if (owned) LunoButton(
          label: selected ? (en ? 'REMOVE FROM QUICK EMOTES' : 'HIZLI İFADELERDEN ÇIKAR')
              : (en ? 'ADD TO QUICK EMOTES' : 'HIZLI İFADELERE EKLE'),
          onPressed: () => dismissLunoAccountModal(context, true)),
        TextButton(onPressed: () => dismissLunoAccountModal(context),
          child: Text(en ? 'CLOSE' : 'KAPAT')),
      ]),
    ));
  }
}
