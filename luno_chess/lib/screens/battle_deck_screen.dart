import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter/material.dart';

import '../battle_ui/cards.dart';
import '../battle_v1/deck_account.dart';
import '../battle_v1/deck_metrics.dart';
import '../battle_v1/model.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_account_modal.dart';
import '../services/account_operation_guard.dart';
import '../services/luno_feedback.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../theme/luno_visual_assets.dart';
import '../widgets/luno_polish.dart';
import '../widgets/luno_surface.dart';
import '../widgets/battle_deck_mana.dart';
import '../widgets/battle_collection_progress.dart';
import '../services/battle_v1_deck_result.dart';
import '../services/first_session_telemetry.dart';

enum _DeckLeaveAction { save, discard, cancel }

/// Online V1 deck editor; the legacy six-slot collection never owns this deck.
class BattleDeckScreen extends StatefulWidget implements LunoAccountScopedPage {
  final bool catalogOnly;
  final LunoOnlineService? online;
  final CardId? focusCard;
  @visibleForTesting
  final Future<Map<String, dynamic>> Function()? loadOverride;
  @visibleForTesting
  final Future<Map<String, dynamic>> Function(List<String>)? saveOverride;
  const BattleDeckScreen({
    super.key,
    this.catalogOnly = false,
    this.online,
    this.focusCard,
    this.loadOverride,
    this.saveOverride,
  });

  @override
  State<BattleDeckScreen> createState() => _BattleDeckScreenState();
}

class _BattleDeckScreenState extends State<BattleDeckScreen> {
  BattleDeckAccount? account;
  List<CardId> selected = [...starterDeck];
  bool loading = false, saving = false;
  bool _saveConfirmed = false;
  bool _replacementOpen = false;
  bool _leavePromptOpen = false;
  String? error;
  int generation = 0;
  final Completer<void> _closed = Completer<void>();
  late final (String?, int) _owner;
  AccountOperationGuard? _loadedOwner;
  bool _sessionInvalidated = false;

  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsAccount => _owner == (online.user?.uid, online.accountRevision);
  bool get _canAct =>
      mounted &&
      !_sessionInvalidated &&
      _ownsAccount &&
      !online.authTransitioning &&
      (_loadedOwner?.isCurrent ?? true) &&
      ModalRoute.of(context)?.isCurrent == true;
  bool get _dirty =>
      !widget.catalogOnly &&
      account != null &&
      !listEquals(selected, account!.deck);

  String? get _draftProblem {
    final l = LunoLocalizations.of(context);
    if (selected.length != 10) {
      return l.learning(
        'Tam 10 kart seç (${selected.length}/10).',
        'Choose exactly 10 cards (${selected.length}/10).',
      );
    }
    if (selected.toSet().length != 10) {
      return l.learning(
        'Destede 10 farklı kart olmalı.',
        'Your deck must contain 10 different cards.',
      );
    }
    if (account == null || !account!.owned.containsAll(selected)) {
      return l.learning(
        'Yalnızca sahip olduğun kartları seç.',
        'Choose only cards you own.',
      );
    }
    if (!account!.available) {
      return l.learning(
        'Çevrimiçi deste kaydı şu anda kullanılamıyor.',
        'Online deck saving is currently unavailable.',
      );
    }
    return null;
  }

  Future<void> _requestLeave() async {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        _leavePromptOpen ||
        saving) {
      return;
    }
    if (!_dirty) {
      await Navigator.of(context).maybePop();
      return;
    }
    if (!_canAct) return;
    _leavePromptOpen = true;
    final l = LunoLocalizations.of(context);
    final problem = _draftProblem;
    try {
      final action = await showLunoAccountDialog<_DeckLeaveAction>(
        context: context,
        service: online,
        playerStore: GameStore.instance,
        builder:
            (ctx) => AlertDialog(
              key: const ValueKey('battle-deck-leave-dialog'),
              scrollable: true,
              title: Text(l.learning('Kaydedilmemiş deste', 'Unsaved deck')),
              content: Text(
                [
                  l.learning(
                    'Ayrılmadan önce değişikliklerini kaydetmek ister misin?',
                    'Save your changes before leaving?',
                  ),
                  if (problem != null) problem,
                ].join('\n\n'),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('battle-deck-leave-cancel'),
                  onPressed:
                      () =>
                          dismissLunoAccountModal(ctx, _DeckLeaveAction.cancel),
                  child: Text(l.learning('Düzenlemeye dön', 'Keep editing')),
                ),
                TextButton(
                  key: const ValueKey('battle-deck-leave-discard'),
                  onPressed:
                      () => dismissLunoAccountModal(
                        ctx,
                        _DeckLeaveAction.discard,
                      ),
                  child: Text(
                    l.learning('Değişiklikleri bırak', 'Discard changes'),
                  ),
                ),
                TextButton(
                  key: const ValueKey('battle-deck-leave-save'),
                  onPressed:
                      problem == null
                          ? () => dismissLunoAccountModal(
                            ctx,
                            _DeckLeaveAction.save,
                          )
                          : null,
                  child: Text(l.learning('Kaydet', 'Save')),
                ),
              ],
            ),
      );
      if (!mounted || !_canAct) return;
      if (action == _DeckLeaveAction.discard) {
        Navigator.of(context).pop();
      } else if (action == _DeckLeaveAction.save) {
        final confirmed = await _save();
        if (!mounted) return;
        if (confirmed && _canAct && !_dirty) Navigator.of(context).pop();
      }
    } finally {
      _leavePromptOpen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _owner = (online.user?.uid, online.accountRevision);
    online.addListener(_privateStateChanged);
    GameStore.instance.addListener(_privateStateChanged);
    FirstSessionTelemetry.forStore(GameStore.instance).record(
      FirstSessionEvent.deckOpened,
      GameStore.instance.accountBindingRevision,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    online.removeListener(_privateStateChanged);
    GameStore.instance.removeListener(_privateStateChanged);
    generation++;
    _closed.complete();
    super.dispose();
  }

  void _privateStateChanged() {
    if (!mounted ||
        _sessionInvalidated ||
        (_ownsAccount && (_loadedOwner?.isCurrent ?? true))) {
      return;
    }
    // A new operation must never rebind previously loaded rights to a new owner.
    setState(() {
      _sessionInvalidated = true;
      generation++;
      account = null;
      selected = [...starterDeck];
      loading = false;
      saving = false;
      _saveConfirmed = false;
      error = 'session';
    });
  }

  Future<T> _withLoadDeadline<T>(Future<T> operation) async {
    final timeout = Completer<T>();
    final timer = Timer(const Duration(seconds: 15), () {
      timeout.completeError(TimeoutException('Battle deck load timed out'));
    });
    try {
      return await Future.any<T>([
        operation,
        timeout.future,
        _closed.future.then<T>((_) => throw StateError('Deck screen closed')),
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _load() async {
    if (!_canAct || loading || saving) return;
    final request = ++generation;
    final guard = AccountOperationGuard(GameStore.instance, online);
    setState(() {
      _loadedOwner = guard;
      loading = true;
      _saveConfirmed = false;
      error = null;
    });
    try {
      if (widget.loadOverride == null) {
        await _withLoadDeadline(online.start());
      }
      if (!mounted ||
          !_ownsAccount ||
          request != generation ||
          !guard.isCurrent) {
        return;
      }
      final result = await _withLoadDeadline(
        widget.loadOverride?.call() ?? online.getBattleV1Deck(),
      );
      if (!mounted ||
          !_ownsAccount ||
          request != generation ||
          !guard.isCurrent) {
        return;
      }
      final parsed = BattleDeckAccount.fromResponse(result);
      setState(() {
        _loadedOwner = guard;
        account = parsed;
        selected = [...parsed.deck];
        error = null;
      });
      final focus = widget.focusCard;
      if (!widget.catalogOnly &&
          focus != null &&
          parsed.available &&
          parsed.owned.contains(focus) &&
          !selected.contains(focus)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_canAct && !loading && request == generation) _toggle(focus);
        });
      }
    } catch (_) {
      if (!mounted || !_ownsAccount || request != generation) return;
      setState(() {
        _loadedOwner = null;
        account = null;
        selected = [...starterDeck];
        error = 'load';
      });
    } finally {
      if (mounted && _ownsAccount && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  void _toggle(CardId card) {
    if (!_canAct) return;
    final current = account;
    if (widget.catalogOnly ||
        loading ||
        saving ||
        current == null ||
        !current.available) {
      _inspect(card);
      return;
    }
    if (!current.owned.contains(card) && !selected.contains(card)) {
      _inspect(card);
      return;
    }
    LunoFeedback.tap();
    if (selected.contains(card)) {
      setState(() {
        selected.remove(card);
        _saveConfirmed = false;
      });
    } else if (selected.length < 10) {
      setState(() {
        selected.add(card);
        _saveConfirmed = false;
      });
    } else {
      unawaited(_replace(card));
    }
  }

  String? _unlockCondition(CardId card) {
    if (account == null) return null;
    if (account!.owned.contains(card)) return null;
    final l = LunoLocalizations.of(context);
    final entries = account!.progression?.path.where(
      (entry) => entry.card == card,
    );
    final milestone = entries?.firstOrNull;
    return milestone == null
        ? l.learning(
          'Açılma koşulu için bağlantını yenile.',
          'Refresh your connection to see the unlock condition.',
        )
        : milestone.conditionLabel(english: l.isEnglish);
  }

  void _inspect(CardId card) {
    if (!_canAct) return;
    showBattleCatalogDetail(
      context,
      card,
      unlockCondition: _unlockCondition(card),
      unlockMilestone:
          account?.progression?.path
              .where((entry) => entry.card == card)
              .firstOrNull,
      owned: account?.owned.contains(card),
      online: online,
      playerStore: GameStore.instance,
      onAddToDeck:
          widget.catalogOnly &&
                  account?.available == true &&
                  account!.owned.contains(card)
              ? () async {
                if (!_canAct) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => LunoAccountScope(
                          page: BattleDeckScreen(
                            online: online,
                            focusCard: card,
                            loadOverride: widget.loadOverride,
                            saveOverride: widget.saveOverride,
                          ),
                          service: online,
                        ),
                  ),
                );
                if (_canAct) unawaited(_load());
              }
              : null,
    );
  }

  Future<void> _replace(CardId incoming) async {
    if (!_canAct ||
        _replacementOpen ||
        loading ||
        saving ||
        account?.available != true ||
        !account!.owned.contains(incoming) ||
        selected.length != 10 ||
        selected.contains(incoming)) {
      return;
    }
    _replacementOpen = true;
    final before = List<CardId>.of(selected);
    final request = generation;
    final l = LunoLocalizations.of(context);
    try {
      final outgoing = await showLunoAccountBottomSheet<CardId>(
        context: context,
        service: online,
        playerStore: GameStore.instance,
        backgroundColor: LunoColors.bgPanel,
        builder:
            (ctx) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * .85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.learning(
                                'HANGİ KART DEĞİŞSİN?',
                                'WHICH CARD TO REPLACE?',
                              ),
                              style: LunoType.sectionTitle,
                            ),
                          ),
                          IconButton(
                            tooltip: l.learning('Kapat', 'Close'),
                            onPressed: () => dismissLunoAccountModal(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.learning(
                          '${l.battleCardName(incoming)} destene girecek. Yerine çıkacak bir kart seç; sonra desteni kaydet.',
                          '${l.battleCardName(incoming)} will join your deck. Choose one card to remove, then save your deck.',
                        ),
                        style: LunoType.bodyMuted,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: SizedBox.square(
                          dimension: 100,
                          child: BattleCardArt(card: incoming),
                        ),
                      ),
                      BattleSelectedDeckGrid(
                        cards: before,
                        onTap: (card) => dismissLunoAccountModal(ctx, card),
                      ),
                      TextButton(
                        onPressed: () => dismissLunoAccountModal(ctx),
                        child: Text(l.learning('Vazgeç', 'Cancel')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
      if (!_canAct ||
          outgoing == null ||
          request != generation ||
          saving ||
          !listEquals(before, selected) ||
          !account!.owned.contains(incoming)) {
        return;
      }
      final index = selected.indexOf(outgoing);
      if (index < 0) return;
      setState(() {
        selected[index] = incoming;
        _saveConfirmed = false;
      });
      LunoFeedback.tap();
    } finally {
      _replacementOpen = false;
    }
  }

  bool _saveIsCurrent(int request, AccountOperationGuard guard) =>
      mounted &&
      !_sessionInvalidated &&
      _ownsAccount &&
      request == generation &&
      guard.isCurrent;

  void _recordConfirmedSave(
    BattleDeckAccount previous,
    List<CardId> submitted,
  ) {
    FirstSessionTelemetry.forStore(GameStore.instance).record(
      FirstSessionEvent.deckSaved,
      GameStore.instance.accountBindingRevision,
    );
    if (submitted.any((card) => !previous.deck.contains(card))) {
      FirstSessionTelemetry.forStore(GameStore.instance).record(
        FirstSessionEvent.cardAddedToDeck,
        GameStore.instance.accountBindingRevision,
      );
    }
  }

  Future<bool> _reconcileSave(
    List<CardId> submitted,
    BattleDeckAccount previous,
    AccountOperationGuard guard,
    int request,
  ) async {
    if (!_saveIsCurrent(request, guard)) return false;
    try {
      final result = await _withLoadDeadline(
        widget.loadOverride?.call() ?? online.getBattleV1Deck(),
      );
      if (!_saveIsCurrent(request, guard)) return false;
      final confirmed = BattleDeckAccount.fromResponse(result);
      final matches = listEquals(confirmed.deck, submitted);
      setState(() {
        // A read may refresh rights or the server baseline, never the draft.
        account = confirmed;
        _saveConfirmed = matches;
        error = matches ? null : 'save';
      });
      if (matches) _recordConfirmedSave(previous, submitted);
      return matches;
    } catch (_) {
      if (_saveIsCurrent(request, guard)) setState(() => error = 'save');
      return false;
    }
  }

  Future<void> _checkSave() async {
    final current = account;
    if (!_canAct || loading || saving || current == null || !_dirty) return;
    final guard = AccountOperationGuard(GameStore.instance, online);
    final request = generation;
    final submitted = List<CardId>.unmodifiable(selected);
    setState(() => saving = true);
    try {
      await _reconcileSave(submitted, current, guard, request);
    } finally {
      if (_saveIsCurrent(request, guard)) setState(() => saving = false);
    }
  }

  Future<bool> _save() async {
    if (!_canAct) return false;
    final current = account;
    if (current == null ||
        !current.available ||
        loading ||
        saving ||
        listEquals(selected, current.deck) ||
        selected.length != 10 ||
        selected.toSet().length != 10 ||
        !current.owned.containsAll(selected)) {
      return false;
    }
    final submitted = List<CardId>.unmodifiable(selected);
    final deck = submitted.map((card) => card.wire).toList();
    final guard = AccountOperationGuard(GameStore.instance, online);
    final request = generation;
    setState(() {
      saving = true;
      _saveConfirmed = false;
      error = null;
    });
    try {
      final result = await _withLoadDeadline(
        widget.saveOverride?.call(deck) ?? online.setBattleV1Deck(deck),
      );
      if (!_saveIsCurrent(request, guard)) return false;
      final saved = result['deck'];
      if (result['ok'] != true ||
          saved is! List ||
          saved.length != 10 ||
          !saved.every((value) => value is String) ||
          !List<String>.from(
            saved,
          ).asMap().entries.every((entry) => entry.value == deck[entry.key])) {
        throw const FormatException('Unconfirmed battle deck save');
      }
      setState(() {
        _saveConfirmed = true;
        account = BattleDeckAccount(
          deck: submitted,
          owned: current.owned,
          available: current.available,
          progression: current.progression,
        );
      });
      _recordConfirmedSave(current, submitted);
      return true;
    } catch (_) {
      // A failed response is not proof of a failed write. Re-read without
      // replacing the local selection before allowing a retry or navigation.
      return await _reconcileSave(submitted, current, guard, request);
    } finally {
      if (_saveIsCurrent(request, guard)) setState(() => saving = false);
    }
  }

  Widget _draftAnalysis() {
    final l = LunoLocalizations.of(context);
    final stats = BattleDeckMetrics.fromCards(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BattleDeckMana(cards: selected),
        const SizedBox(height: 8),
        Text(
          l.learning(
            'İlk kart aşamasında 2 mana: ${stats.openingAffordableCount}/${stats.count} kartın maliyeti karşılanır. 3+ mana: ${stats.aboveOpeningManaCount}; 4+ mana: ${stats.highCostCount}.',
            'At the first card phase, 2 mana covers ${stats.openingAffordableCount}/${stats.count} cards. 3+ mana: ${stats.aboveOpeningManaCount}; 4+ mana: ${stats.highCostCount}.',
          ),
          style: LunoType.bodyMuted,
        ),
        if (stats.reactiveRemovalCount > 0 ||
            stats.sacrificeRequiredCount > 0 ||
            stats.pieceSpecificCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            l.learning(
              'Kaldırılacak etki gerekir: ${stats.reactiveRemovalCount}. Başka kart feda edilir: ${stats.sacrificeRequiredCount}. Belirli taş gerekir: ${stats.pieceSpecificCount}.',
              'Needs an effect to remove: ${stats.reactiveRemovalCount}. Sacrifices another card: ${stats.sacrificeRequiredCount}. Needs a specific piece: ${stats.pieceSpecificCount}.',
            ),
            style: LunoType.bodyMuted,
          ),
        ],
        const SizedBox(height: 6),
        Text(
          l.learning(
            stats.isCompleteDeck
                ? 'Maliyet tek başına oynanabilirlik değildir; geçerli hedef ve kart koşulları da gerekir.'
                : 'Taslak analizi. Deste değerlendirmesi için 10 farklı kart seç; geçerli hedef ve kart koşulları yine gerekir.',
            stats.isCompleteDeck
                ? 'Affordability is not playability; valid targets and card conditions still apply.'
                : 'Draft analysis. Choose 10 different cards for deck evaluation; valid targets and card conditions still apply.',
          ),
          style: LunoType.bodyMuted,
        ),
      ],
    );
  }

  Widget _progressPanel(BattleDeckProgression progress) {
    final l = LunoLocalizations.of(context);
    final next = progress.nextUnlock;
    final nextProgress = next?.requirements
        .map((requirement) {
          final label = switch (requirement.kind) {
            BattleUnlockKind.rankedMatches => l.learning(
              'Sıralı maç',
              'Ranked matches',
            ),
            BattleUnlockKind.welcomeClaim => l.learning(
              'Karşılama ödülü',
              'Welcome reward',
            ),
            BattleUnlockKind.dailyClaimDays => l.learning(
              'Günlük ödül günü',
              'Daily reward days',
            ),
          };
          final current = requirement.current.clamp(0, requirement.target);
          return '$label $current/${requirement.target}';
        })
        .join(l.learning(' VEYA ', ' OR '));
    return LunoSurface(
      key: const ValueKey('battle-unlock-progress'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          if (next != null) ...[
            SizedBox.square(
              dimension: 46,
              child: BattleCardArt(card: next.card),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  next == null
                      ? l.learning(
                        'Koleksiyon tamamlandı',
                        'Collection complete',
                      )
                      : l.learning(
                        'Sıradaki: ${l.battleCardName(next.card)}',
                        'Next: ${l.battleCardName(next.card)}',
                      ),
                  style: LunoType.bodyMuted.copyWith(
                    color: LunoColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nextProgress ?? progress.progressLabel(english: l.isEnglish),
                  style: LunoType.bodyMuted.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.learning(
              'Kart açma koşulları',
              'Card unlock conditions',
            ),
            icon: const Icon(Icons.info_outline_rounded),
            onPressed:
                !_canAct
                    ? null
                    : () => showLunoAccountDialog<void>(
                      context: context,
                      service: online,
                      playerStore: GameStore.instance,
                      builder:
                          (ctx) => AlertDialog(
                            title: Text(
                              l.learning('Savaş kartları', 'Battle cards'),
                            ),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.learning(
                                      'Arena kupan rekabet seviyeni gösterir; kartlar aşağıdaki koşullarla tüm arenalarda açılır.',
                                      'Arena trophies show your competitive rank; cards unlock through these conditions in every arena.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    progress.qualificationLabel(
                                      english: l.isEnglish,
                                    ),
                                  ),
                                  if (next != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      l.battleCardName(next.card),
                                      style: LunoType.sectionTitle,
                                    ),
                                    const SizedBox(height: 10),
                                    BattleUnlockProgress(milestone: next),
                                  ],
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => dismissLunoAccountModal(ctx),
                                child: Text(l.learning('Anladım', 'Got it')),
                              ),
                            ],
                          ),
                    ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final cards = widget.catalogOnly ? CardId.values : selected;
    final current = account;
    final canEdit =
        _canAct && current != null && current.available && !loading && !saving;
    final dirty = _dirty;
    final problem = current == null ? null : _draftProblem;
    final content = Scaffold(
      appBar: AppBar(
        leading: BackButton(
          key: const ValueKey('battle-deck-back'),
          onPressed: () => unawaited(_requestLeave()),
        ),
        title: Text(
          l.learning(
            widget.catalogOnly ? 'KARTLAR' : 'DESTE',
            widget.catalogOnly ? 'CARDS' : 'DECK',
          ),
        ),
      ),
      body: LunoBackdrop(
        art: LunoAssets.collectionSceneV28,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            LunoSurface(
              surfaceArt: LunoVisualAssets.collection,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.learning(
                      widget.catalogOnly ? 'Kart kütüphanesi' : 'Savaş destesi',
                      widget.catalogOnly ? 'Card library' : 'Battle deck',
                    ),
                    style: LunoType.screenTitle,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.learning(
                      widget.catalogOnly
                          ? '24 yetenek. Açık kartlarını ve sıradaki hedefini keşfet.'
                          : error == 'session'
                          ? 'Başlangıç destesi önizlemesi. Hesap desten bu ekranı yeniden açana kadar gizli.'
                          : current == null
                          ? 'Başlangıç destesi önizlemesi. Çevrimiçi deste yüklenince burada düzenleyebilirsin.'
                          : current.available
                          ? 'AI ve sıralı maçlar için 10 farklı kart. Yüz yüze maçlarda başlangıç destesi kullanılır.'
                          : 'Çevrimiçi savaş şu anda kapalı. Kayıtlı desteni inceleyebilirsin.',
                      widget.catalogOnly
                          ? '24 abilities. Explore your collection and your next unlock.'
                          : error == 'session'
                          ? 'Starter deck preview. Your account deck is hidden until you reopen this screen.'
                          : current == null
                          ? 'Starter deck preview. You can edit your online deck after it loads.'
                          : current.available
                          ? '10 different cards for AI and ranked matches. Face-to-face uses the starter deck.'
                          : 'Online battle is currently unavailable. You can view your saved deck.',
                    ),
                    style: LunoType.bodyMuted,
                  ),
                  if (current != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.learning(
                        '${current.owned.length}/24 kart açık',
                        '${current.owned.length}/24 cards owned',
                      ),
                      key: const ValueKey('battle-owned-count'),
                      style: LunoType.bodyMuted.copyWith(
                        color: LunoColors.cyan,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (widget.catalogOnly && current?.progression != null) ...[
              const SizedBox(height: 12),
              _progressPanel(current!.progression!),
            ],
            if (error == 'load' || error == 'session')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LunoSurface(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: LunoColors.gold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error == 'session'
                              ? l.learning(
                                'Oturumun değişti. Desteni yüklemek için bu ekranı yeniden aç.',
                                'Your session changed. Reopen this screen to load your deck.',
                              )
                              : widget.catalogOnly
                              ? l.learning(
                                'Sahiplik yüklenemedi. Kartlar yalnızca önizleme.',
                                'Ownership unavailable. Cards are preview only.',
                              )
                              : l.learning(
                                'Deste yüklenemedi. Başlangıç destesi yalnızca önizleme.',
                                'Deck unavailable. Starter deck is only a preview.',
                              ),
                          style: LunoType.bodyMuted,
                        ),
                      ),
                      if (error == 'load')
                        IconButton(
                          tooltip: l.learning('Yeniden dene', 'Retry'),
                          onPressed: loading || saving ? null : _load,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            if (!widget.catalogOnly && current != null) ...[
              const SizedBox(height: 14),
              Text(
                l.learning(
                  'SEÇİLİ KARTLAR ${selected.length}/10',
                  'SELECTED CARDS ${selected.length}/10',
                ),
                style: LunoType.sectionTitle,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            if (widget.catalogOnly)
              BattleCatalogGrid(
                cards: cards,
                onTap: _inspect,
                onInspect: _inspect,
                ownershipKnown: current != null,
                selected: current?.deck.toSet() ?? const {},
                milestones: {
                  for (final entry
                      in current?.progression?.path ??
                          <BattleUnlockMilestone>[])
                    entry.card: entry,
                },
                unlockLabels: {
                  for (final card in cards)
                    if (_unlockCondition(card) case final condition?)
                      card: condition,
                },
                locked:
                    current == null
                        ? const {}
                        : CardId.values
                            .where((c) => !current.owned.contains(c))
                            .toSet(),
              )
            else
              BattleSelectedDeckGrid(cards: selected, onTap: _toggle),
            if (!widget.catalogOnly && current != null) ...[
              const SizedBox(height: 14),
              _draftAnalysis(),
              if (problem != null) ...[
                const SizedBox(height: 8),
                Text(
                  problem,
                  key: const ValueKey('battle-deck-validation'),
                  style: LunoType.bodyMuted.copyWith(color: LunoColors.gold),
                ),
              ],
              const SizedBox(height: 14),
              LunoButton(
                label: l.learning('DESTENİ KAYDET', 'SAVE DECK'),
                icon: Icons.save_rounded,
                loading: saving,
                onPressed: canEdit && dirty && problem == null ? _save : null,
              ),
              if (dirty || _saveConfirmed) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l.learning(
                      dirty
                          ? 'Kaydedilmemiş değişiklikler'
                          : 'Deste kaydedildi',
                      dirty ? 'Unsaved changes' : 'Deck saved',
                    ),
                    key: const ValueKey('battle-deck-save-status'),
                    style: LunoType.bodyMuted.copyWith(
                      color: dirty ? LunoColors.gold : LunoColors.teal,
                    ),
                  ),
                ),
              ],
              if (error == 'save') ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l.learning(
                      'Deste kaydı doğrulanamadı. Taslağın korundu; kaydı kontrol et veya yeniden dene.',
                      'Deck save could not be confirmed. Your draft is kept; check the save or retry.',
                    ),
                    key: const ValueKey('battle-deck-save-error'),
                    style: LunoType.bodyMuted.copyWith(color: LunoColors.gold),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('battle-deck-check-save'),
                  onPressed: _canAct && !loading && !saving ? _checkSave : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(l.learning('Kaydı kontrol et', 'Check save')),
                ),
              ],
              if (current.progression != null) ...[
                const SizedBox(height: 16),
                _progressPanel(current.progression!),
              ],
            ],
            if (!widget.catalogOnly) ...[
              const SizedBox(height: 20),
              Text(
                l.learning('DİĞER SAVAŞ KARTLARI', 'OTHER BATTLE CARDS'),
                style: LunoType.sectionTitle,
              ),
              const SizedBox(height: 10),
              BattleCatalogGrid(
                ownershipKnown: current != null,
                milestones: {
                  for (final entry
                      in current?.progression?.path ??
                          <BattleUnlockMilestone>[])
                    entry.card: entry,
                },
                cards:
                    CardId.values.where((c) => !selected.contains(c)).toList(),
                unlockLabels: {
                  for (final card in CardId.values)
                    if (_unlockCondition(card) case final condition?)
                      card: condition,
                },
                locked:
                    current == null
                        ? const {}
                        : CardId.values
                            .where((card) => !current.owned.contains(card))
                            .toSet(),
                onTap: _toggle,
                onInspect: _inspect,
              ),
            ],
          ],
        ),
      ),
    );
    return PopScope<void>(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestLeave());
      },
      child: content,
    );
  }
}

class BattleSelectedDeckGrid extends StatelessWidget {
  final List<CardId> cards;
  final ValueChanged<CardId>? onTap;
  const BattleSelectedDeckGrid({super.key, required this.cards, this.onTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final l = LunoLocalizations.of(context);
      const labelStyle = TextStyle(
        fontSize: 11,
        height: 1.12,
        fontWeight: FontWeight.w800,
      );
      final scaler = MediaQuery.textScalerOf(context);
      final style = DefaultTextStyle.of(context).style.merge(labelStyle);
      var minimumWidth = 52.0;
      for (final card in cards) {
        for (final word in l.battleCardName(card).split(RegExp(r'\s+'))) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          minimumWidth = math.max(minimumWidth, painter.width + 2);
          painter.dispose();
        }
      }
      final columns = ((box.maxWidth + 6) / (minimumWidth + 6)).floor().clamp(
        1,
        5,
      );
      final width = (box.maxWidth - 6 * (columns - 1)) / columns;
      return Wrap(
        key: const ValueKey('selected-deck-grid'),
        spacing: 6,
        runSpacing: 10,
        children: [
          for (final card in cards)
            SizedBox(
              width: width,
              child: LunoPressFeedback(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('deck-slot-${card.wire}'),
                    onTap:
                        () =>
                            onTap == null
                                ? showBattleCatalogDetail(context, card)
                                : onTap!(card),
                    onLongPress: () => showBattleCatalogDetail(context, card),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: .75,
                          child: Container(
                            decoration: BoxDecoration(
                              image: const DecorationImage(
                                image: AssetImage(
                                  'assets/native_art/v205-card-face.png',
                                ),
                                fit: BoxFit.fill,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: battleRarityColor(
                                  cardDefinitions[card]!.rarity,
                                ),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      17,
                                      4,
                                      4,
                                    ),
                                    child: BattleCardArt(card: card),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  left: 5,
                                  child: Text(
                                    '${cardDefinitions[card]!.cost}',
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: LunoColors.cyan,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: IconButton(
                                    tooltip: l.learning(
                                      '${l.battleCardName(card)} bilgisi',
                                      '${l.battleCardName(card)} info',
                                    ),
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFF07141A),
                                      foregroundColor: LunoColors.ivory,
                                      side: const BorderSide(
                                        color: LunoColors.gold,
                                      ),
                                      minimumSize: const Size(48, 48),
                                      padding: const EdgeInsets.all(10),
                                    ),
                                    onPressed:
                                        () => showBattleCatalogDetail(
                                          context,
                                          card,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: scaler.scale(11) * 1.12 * 2,
                          child: Text(
                            l.battleCardName(card),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: labelStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class BattleCatalogGrid extends StatelessWidget {
  final List<CardId> cards;
  final Set<CardId> selected;
  final Set<CardId> locked;
  final Map<CardId, String> unlockLabels;
  final Map<CardId, BattleUnlockMilestone> milestones;
  final bool ownershipKnown;
  final void Function(CardId)? onTap;
  final ValueChanged<CardId>? onInspect;
  const BattleCatalogGrid({
    super.key,
    required this.cards,
    this.selected = const {},
    this.locked = const {},
    this.unlockLabels = const {},
    this.milestones = const {},
    this.ownershipKnown = true,
    this.onTap,
    this.onInspect,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns =
          box.maxWidth >= 680
              ? 4
              : box.maxWidth >= 450
              ? 3
              : 2;
      final width = (box.maxWidth - 10 * (columns - 1)) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final card in cards)
            SizedBox(
              width: width,
              child: BattleCatalogCard(
                card: card,
                selected: selected.contains(card),
                locked: locked.contains(card),
                unlockCondition: unlockLabels[card],
                unlockMilestone: milestones[card],
                ownershipKnown: ownershipKnown,
                onTap: onTap == null ? null : () => onTap!(card),
                onInspect: onInspect == null ? null : () => onInspect!(card),
              ),
            ),
        ],
      );
    },
  );
}

class BattleCatalogCard extends StatelessWidget {
  final CardId card;
  final VoidCallback? onTap;
  final VoidCallback? onInspect;
  final bool selected;
  final bool locked;
  final String? unlockCondition;
  final BattleUnlockMilestone? unlockMilestone;
  final bool ownershipKnown;
  const BattleCatalogCard({
    super.key,
    required this.card,
    this.onTap,
    this.onInspect,
    this.selected = false,
    this.locked = false,
    this.unlockCondition,
    this.unlockMilestone,
    this.ownershipKnown = true,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final def = cardDefinitions[card]!;
    void inspect() {
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (onInspect != null) {
        onInspect!();
      } else {
        showBattleCatalogDetail(
          context,
          card,
          unlockCondition: unlockCondition,
          unlockMilestone: ownershipKnown ? unlockMilestone : null,
          owned: ownershipKnown ? !locked : null,
        );
      }
    }

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${l.battleCardName(card)}, ${l.battle(BattleCopy.mana)} ${def.cost}, ${!ownershipKnown
              ? l.learning('sahiplik doğrulanmadı', 'ownership unconfirmed')
              : locked
              ? l.learning('kilitli', 'locked')
              : selected
              ? l.learning('destede', 'in deck')
              : l.learning('açık', 'owned')}',
      child: LunoPressFeedback(
        child: LunoSurface(
          padding: EdgeInsets.zero,
          surfaceArt: 'assets/native_art/v205-card-face.png',
          nineSlice: false,
          color: battleRarityColor(def.rarity).withValues(alpha: .18),
          border: Border.all(
            color: selected ? LunoColors.cyan : battleRarityColor(def.rarity),
            width: selected ? 2 : 1,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (ModalRoute.of(context)?.isCurrent != true) return;
              LunoFeedback.tap();
              if (onTap != null) {
                onTap!();
              } else {
                inspect();
              }
            },
            onLongPress: inspect,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.water_drop_rounded,
                          color: LunoColors.cyan,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${def.cost}',
                          style: LunoType.screenTitle.copyWith(
                            color: LunoColors.cyan,
                          ),
                        ),
                        const Spacer(),
                        if (selected && !locked)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: LunoColors.teal,
                            size: 18,
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 96,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Opacity(
                            opacity: locked ? .4 : 1,
                            child: BattleCardArt(card: card),
                          ),
                          if (locked)
                            const Center(
                              child: LunoArt(
                                'assets/native_art/v205-lock-common.png',
                                width: 42,
                                height: 46,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.battleCardName(card),
                      textAlign: TextAlign.center,
                      style: LunoType.bodyMuted.copyWith(
                        color: LunoColors.ivory,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !ownershipKnown
                          ? l.learning('Önizleme', 'Preview')
                          : locked
                          ? l.learning('Kilitli', 'Locked')
                          : selected
                          ? l.learning('Destede', 'In deck')
                          : l.learning('Açık', 'Owned'),
                      style: LunoType.bodyMuted.copyWith(
                        fontSize: 11,
                        color: selected ? LunoColors.cyan : LunoColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.battleRarity(def.rarity),
                      textAlign: TextAlign.center,
                      style: LunoType.bodyMuted.copyWith(
                        fontSize: 12,
                        color: battleRarityColor(def.rarity),
                      ),
                    ),
                    if (locked && unlockMilestone != null) ...[
                      const SizedBox(height: 10),
                      BattleUnlockProgress(
                        milestone: unlockMilestone!,
                        compact: true,
                      ),
                    ] else if (locked && unlockCondition != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        unlockCondition!,
                        textAlign: TextAlign.center,
                        style: LunoType.bodyMuted.copyWith(fontSize: 12),
                      ),
                    ],
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

Future<void> showBattleCatalogDetail(
  BuildContext context,
  CardId card, {
  String? unlockCondition,
  BattleUnlockMilestone? unlockMilestone,
  bool? owned,
  LunoOnlineService? online,
  GameStore? playerStore,
  VoidCallback? onAddToDeck,
}) async {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) {
    return;
  }
  final l = LunoLocalizations.of(context);
  final definition = cardDefinitions[card]!;
  Widget builder(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.battleCardName(card),
                    style: LunoType.screenTitle,
                  ),
                ),
                IconButton(
                  tooltip: l.battle(BattleCopy.close),
                  onPressed: () {
                    if (context.mounted &&
                        ModalRoute.of(context)?.isCurrent == true) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Center(
              child: SizedBox(
                height: 144,
                width: 144,
                child: BattleCardArt(card: card),
              ),
            ),
            Text(
              '${l.battle(BattleCopy.mana)} ${definition.cost}  ·  ${l.battleRarity(definition.rarity)}',
              style: LunoType.bodyMuted.copyWith(color: LunoColors.cyan),
            ),
            const SizedBox(height: 14),
            if (owned != null) ...[
              Text(
                l.learning(
                  owned ? 'Koleksiyonunda' : 'Henüz açılmadı',
                  owned ? 'In your collection' : 'Not unlocked yet',
                ),
                style: LunoType.sectionTitle,
              ),
              const SizedBox(height: 10),
            ],
            if (unlockCondition != null) ...[
              Text(
                unlockMilestone == null
                    ? unlockCondition
                    : l.learning('Açılma koşulları', 'Unlock requirements'),
                key: const ValueKey('card-unlock-condition'),
                style: LunoType.bodyMuted.copyWith(color: LunoColors.gold),
              ),
              const SizedBox(height: 14),
            ],
            if (owned != true && unlockMilestone != null) ...[
              BattleUnlockProgress(milestone: unlockMilestone),
              const SizedBox(height: 14),
            ],
            Text(
              l.battleCardDetail(card),
              style: LunoType.bodyMuted.copyWith(
                fontSize: 16,
                color: LunoColors.ivory,
                height: 1.5,
              ),
            ),
            if (owned == true && onAddToDeck != null) ...[
              const SizedBox(height: 20),
              LunoButton(
                key: const ValueKey('catalog-open-deck'),
                label: l.learning('DESTEDE DÜZENLE', 'EDIT IN DECK'),
                icon: Icons.style_rounded,
                onPressed: () {
                  if (context.mounted &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
  final add =
      online == null &&
              owned == null &&
              unlockMilestone == null &&
              unlockCondition == null
          ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: LunoColors.bgPanel,
            sheetAnimationStyle: AnimationStyle(
              duration: LunoMotion.adaptive(context, LunoMotion.panelEnter),
              reverseDuration: LunoMotion.adaptive(
                context,
                LunoMotion.panelEnter,
              ),
            ),
            builder: builder,
          )
          : await showLunoAccountBottomSheet<bool>(
            context: context,
            service: online,
            playerStore: playerStore ?? GameStore.instance,
            backgroundColor: LunoColors.bgPanel,
            builder: builder,
          );
  if (add == true && context.mounted) onAddToDeck?.call();
}
