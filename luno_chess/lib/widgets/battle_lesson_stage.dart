import 'package:flutter/material.dart';
import '../battle_ui/action_guide.dart';
import '../battle_ui/audio_feedback.dart';
import '../battle_ui/art.dart';
import '../battle_ui/board.dart';
import '../battle_ui/cards.dart';
import '../battle_ui/interaction.dart';
import '../battle_ui/primitives.dart';
import '../battle_ui/tokens.dart';
import '../battle_v1/authoritative.dart';
import '../battle_v1/core.dart';
import '../battle_v1/model.dart';
import '../battle_v1/practice.dart';
import '../engine/piece.dart';
import '../engine/board.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../screens/battle_deck_screen.dart';
import 'luno_polish.dart';
import 'tutorial_coach.dart';

// Stable checkpoint indices; no account, reward, or live match mutations.
List<CardId> battleLessonCards(int step) => switch (step) {
  3 => const [CardId.manaSabotage, CardId.boardSeal],
  4 => const [CardId.chain, CardId.slow, CardId.pawnAdvance],
  5 => const [CardId.shelter, CardId.freeze, CardId.lockedSquare],
  7 => const [CardId.radar, CardId.prophecy],
  _ => const [],
};

class BattleLessonStage extends StatefulWidget {
  final int step;
  final ValueChanged<bool>? onCompletionChanged;
  const BattleLessonStage({
    super.key,
    required this.step,
    this.onCompletionChanged,
  });

  static bool requiresInteraction(int step) => step >= 1 && step <= 7;
  @override
  State<BattleLessonStage> createState() => _BattleLessonStageState();
}

class _BattleLessonStageState extends State<BattleLessonStage>
    with WidgetsBindingObserver {
  late AuthoritativeBattleState _practice;
  final _selection = BattleInteraction();
  final _drawSource = GlobalKey();
  bool _moved = false, _cast = false;
  CardId _card = CardId.shelter;
  int _mana = 6;
  List<CardId> _pendingOrder = [];
  bool _discarded = false;
  bool _wrongTap = false;
  int _progressRevision = 0;
  int _stateRevision = 0;
  late final int _ownerRevision;
  bool _foreground = true;

  bool get _active =>
      mounted &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent == true &&
      _ownerRevision == GameStore.instance.accountBindingRevision;

  void _update(int revision, VoidCallback change) {
    if (!_active || revision != _stateRevision) return;
    setState(change);
  }

  bool get _complete => switch (widget.step) {
    1 || 2 || 6 => _moved,
    3 || 4 || 5 => _cast && _moved,
    7 => _cast && _view.rules.phase != BattlePhase.pending,
    _ => true,
  };

  void _reportProgress() {
    final revision = ++_progressRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active && revision == _progressRevision) {
        widget.onCompletionChanged?.call(_complete);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownerRevision = GameStore.instance.accountBindingRevision;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context);
    TickerMode.valuesOf(context);
    _reportProgress();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) {
        _stateRevision++;
        _wrongTap = false;
      }
    });
    if (_foreground) _reportProgress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  PlayerView get _view => _practice.view(PieceColor.white);
  List<BattleAction> get _actions => BattleRulesCore.legalActions(_view);

  void _reset({CardId? card}) {
    _stateRevision++;
    final cards = battleLessonCards(widget.step);
    _card = card ?? (cards.isEmpty ? CardId.shelter : cards.first);
    final deck = <CardId>[
      ...cards,
      ...CardId.values.where((c) => !cards.contains(c)).take(10 - cards.length),
    ];
    final initial = DeckManager.newBattle(
      white: cards.isEmpty ? starterDeck : deck,
      board:
          widget.step == 1
              ? null
              : Board.fromFen('4k3/2r2p2/8/3p4/2P1P3/2N1B3/8/3R2K1 w - - 0 12'),
    );
    final draft = RuleDraft(initial.rules);
    _mana = widget.step == 3 ? 3 : 6;
    if (widget.step != 1) {
      // Staged second turn; demonstrations still use authoritative card legality.
      draft.phase = BattlePhase.card;
      draft.ownTurns[PieceColor.white] = 2;
      draft.mana[PieceColor.white] = _mana;
    }
    _practice = AuthoritativeBattleState(draft.freeze(), initial.hidden);
    _moved = false;
    _cast = false;
    _discarded = false;
    _wrongTap = false;
    _pendingOrder = [];
    _selection.cancel();
    if (cards.isNotEmpty) _selection.select(_card, _actions);
    _reportProgress();
  }

  void _apply(BattleAction action) {
    if (!_active || !_actions.any((legal) => legal.key == action.key)) return;
    _practice = DeckManager.apply(_practice, action);
    _stateRevision++;
    _wrongTap = false;
    _cast = _cast || action is PlayCardAction;
    _moved = _moved || action is ChessMoveAction;
    _discarded = _discarded || action is DiscardAction;
    _pendingOrder = [..._view.knowledge.pendingCards];
    _selection.cancel();
    _selection.piece = _view.rules.special?.from;
    _reportProgress();
  }

  void _tapSquare(int revision, int square) {
    if (_moved || square < 0 || square >= 64) return;
    _update(revision, () {
      final previous = (
        _selection.piece,
        _selection.play?.key,
        _selection.specialDestination?.key,
      );
      final choices = _selection.tap(square, _view, _actions);
      if (previous !=
          (
            _selection.piece,
            _selection.play?.key,
            _selection.specialDestination?.key,
          )) {
        _stateRevision++;
      }
      _wrongTap =
          choices.isEmpty &&
          previous ==
              (
                _selection.piece,
                _selection.play?.key,
                _selection.specialDestination?.key,
              );
      if (choices.isNotEmpty && choices.first is ChessMoveAction) {
        if (_view.rules.phase == BattlePhase.card) _apply(const PassAction());
        _apply(choices.first);
      }
    });
  }

  @override
  void didUpdateWidget(BattleLessonStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) _reset();
  }

  Widget _board() {
    final revision = _stateRevision;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              widget.step == 1
                  ? 360
                  : MediaQuery.sizeOf(context).width >= 600
                  ? 320
                  : 260,
        ),
        child: BattleBoard(
          view: _view,
          selected: _selection.piece,
          targets: _selection.targets(_view, _actions),
          preview: _selection.preview(),
          enabled: _active && !_moved,
          onTap: (square) => _tapSquare(revision, square),
        ),
      ),
    );
  }

  String _instruction(LunoLocalizations l) {
    if (_wrongTap) {
      return _selection.card == null && _selection.piece == null
          ? l.learning('Bir beyaz taşına dokun.', 'Tap a white piece.')
          : l.learning('İşaretli hedefi dene.', 'Try a highlighted target.');
    }
    if (_moved) {
      return l.learning(
        'Hamlen tamam! Şimdi sıra rakipte.',
        'Move complete! The opponent plays next.',
      );
    }
    if (_view.rules.phase == BattlePhase.pending) {
      return l.learning(
        'Sıradaki kartların aşağıda. Sırayı onayla.',
        'Your upcoming cards are below. Confirm their order.',
      );
    }
    if (widget.step == 7) {
      return _cast
          ? l.learning(
            'Bilgi açıldı. Sonucu incele; sonraki adıma geçebilirsin.',
            'Information revealed. Review the result, then continue.',
          )
          : l.learning(
            _selection.play == null
                ? 'Rakipte arayacağın kartı seç.'
                : 'Bilgi kartını oyna.',
            _selection.play == null
                ? 'Choose the card to look for.'
                : 'Play your information card.',
          );
    }
    if (_view.rules.phase == BattlePhase.chess) {
      return l.learning(
        _discarded
            ? 'Kart feda edildi. Beyaz taşına dokun.'
            : _selection.piece == null
            ? 'Bir beyaz taşına dokun.'
            : 'İşaretli kareye ilerle.',
        _discarded
            ? 'Card discarded. Tap your white piece.'
            : _selection.piece == null
            ? 'Tap a white piece.'
            : 'Move to a highlighted square.',
      );
    }
    if (battleLessonCards(widget.step).isNotEmpty) {
      if (_view.rules.mana[PieceColor.white]! < cardDefinitions[_card]!.cost) {
        return l.learning(
          'Deneme manasını kartın maliyetine yükselt.',
          'Raise practice mana to the card cost.',
        );
      }
      return _selection.play == null
          ? l.learning(
            cardDefinitions[_card]!.target == CardTargetType.opponentCard
                ? 'Etkileyeceğin rakip kartını seç.'
                : 'Parlayan hedeflerden birine dokun.',
            cardDefinitions[_card]!.target == CardTargetType.opponentCard
                ? 'Choose the opposing card to affect.'
                : 'Tap a highlighted target.',
          )
          : l.learning(
            'Hedef hazır. Kartı Oyna ile onayla.',
            'Target ready. Use Play Card to apply the effect.',
          );
    }
    if (_selection.card != null) {
      return _selection.play == null
          ? l.learning('İşaretli hedefi dene.', 'Try a highlighted target.')
          : l.learning('Kartı Oyna ile onayla.', 'Confirm with Play Card.');
    }
    return l.learning(
      'Bu tur kart adımını geç.',
      'Skip the card step this turn.',
    );
  }

  Widget _guide(LunoLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TutorialCoach(
        key: const ValueKey('lesson-information-instruction'),
        text: _instruction(l),
        cue:
            '${widget.step}:${_view.rules.phase}:${_selection.play?.key}:$_moved',
        portrait: false,
        feedback: _wrongTap,
      ),
      if (widget.step != 7)
        BattleActionGuide(
          phase: _view.rules.phase,
          ownTurn: !_moved,
          firstTurn: widget.step == 1,
          selectedCard: _selection.card,
          instruction: '',
        ),
    ],
  );

  Widget _goals(LunoLocalizations l) {
    final cardDone = _moved || _view.rules.phase != BattlePhase.card;
    final goals = <(String, String, bool)>[
      if (widget.step == 1)
        ('move', l.learning('Bir taş hamlesi yap', 'Make a chess move'), _moved)
      else if (widget.step == 2 || widget.step == 6) ...[
        (
          'card',
          l.learning('Kart adımını bitir', 'Finish the card step'),
          cardDone,
        ),
        if (widget.step == 2)
          (
            'move',
            l.learning('Taş hamleni tamamla', 'Complete your chess move'),
            _moved,
          )
        else
          (
            'draw',
            l.learning(
              'Hamle sonunda gelen kartı gör',
              'See the card drawn after your move',
            ),
            _moved && _view.ownHand.length >= 4,
          ),
      ] else ...[
        (
          'card',
          l.learning('Kartın etkisini dene', 'Try the card effect'),
          _cast,
        ),
        if (widget.step == 7)
          (
            'information',
            l.learning('Bilgi sonucunu aç', 'Reveal the information'),
            _cast && _view.rules.phase != BattlePhase.pending,
          )
        else
          (
            'move',
            l.learning('Taş hamleni tamamla', 'Complete your chess move'),
            _moved,
          ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (id, label, done) in goals)
            _LessonGoal(id: id, label: label, done: done),
        ],
      ),
    );
  }

  Widget _retry(LunoLocalizations l) {
    final revision = _stateRevision;
    return IconButton(
      tooltip: l.learning('Yeniden dene', 'Try again'),
      onPressed: () => _update(revision, () => _reset(card: _card)),
      icon: const Icon(Icons.replay_rounded, color: BattleTokens.moon),
    );
  }

  Widget _cardPractice(LunoLocalizations l) {
    final revision = _stateRevision;
    final selectedPlay = _selection.play;
    final pendingOrder = List<CardId>.unmodifiable(_pendingOrder);
    final options = battleLessonCards(widget.step);
    final playable = _actions.whereType<PlayCardAction>().any(
      (a) => a.card == _card,
    );
    final cost = cardDefinitions[_card]!.cost;
    final boardTarget =
        cardDefinitions[_card]!.target != CardTargetType.opponentCard;
    final boardFirst =
        widget.step == 3 &&
        !boardTarget &&
        MediaQuery.sizeOf(context).width > 350 &&
        BattleTokens.compactText(context);
    final actionBeforeCatalog = widget.step == 4 || widget.step == 5;
    Widget playCommand() => BattleCommand(
      key: const ValueKey('lesson-play-card'),
      label:
          playable
              ? _selection.play == null
                  ? l.learning('Hedef Seç', 'Choose Target')
                  : l.learning('Kartı Oyna', 'Play Card')
              : l.learning(
                '${(cost - _mana).clamp(0, 6)} mana eksik',
                'Need ${(cost - _mana).clamp(0, 6)} more mana',
              ),
      icon: Icons.auto_awesome,
      art: 'confirm',
      onPressed:
          _selection.play == null || !playable
              ? null
              : () => _update(revision, () => _apply(selectedPlay!)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _guide(l),
        const SizedBox(height: 8),
        Row(
          children: [
            BattleMana(
              value: _view.rules.mana[PieceColor.white]!,
              label: l.battle(BattleCopy.mana),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.learning('Maliyet: $cost mana', 'Cost: $cost mana'),
                style: BattleTokens.caption,
              ),
            ),
            _retry(l),
          ],
        ),
        if (widget.step == 3 && !_cast)
          Slider(
            key: const ValueKey('lesson-mana'),
            value: _mana.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            label: l.learning('Deneme manası: $_mana', 'Practice mana: $_mana'),
            onChanged: (value) {
              if (!value.isFinite || value < 1 || value > 6) return;
              _update(revision, () {
                _stateRevision++;
                _mana = value.round();
                final previous = _selection.play;
                final draft = RuleDraft(_practice.rules)
                  ..mana[PieceColor.white] = _mana;
                _practice = AuthoritativeBattleState(
                  draft.freeze(),
                  _practice.hidden,
                );
                _selection.cancel();
                _selection.select(_card, _actions);
                if (previous != null &&
                    _actions.any((a) => a.key == previous.key)) {
                  _selection.play = previous;
                }
                _wrongTap = false;
              });
            },
          ),
        if (boardFirst) ...[_board(), const SizedBox(height: 8)],
        const SizedBox(height: 8),
        if (widget.step == 4 ||
            widget.step == 5 ||
            widget.step == 3 && boardTarget) ...[
          _board(),
          const SizedBox(height: 12),
        ],
        if (actionBeforeCatalog && _view.rules.phase == BattlePhase.card) ...[
          playCommand(),
          const SizedBox(height: 8),
        ],
        if (!_cast)
          SizedBox(
            height:
                widget.step == 3 || widget.step == 7
                    ? 64 +
                        (MediaQuery.textScalerOf(context).scale(12) / 12 - 1) *
                            40
                    : 150 +
                        (MediaQuery.textScalerOf(context).scale(13) / 13 - 1) *
                            90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final card = options[index];
                return SizedBox(
                  width: widget.step == 3 || widget.step == 7 ? 140 : 108,
                  child:
                      widget.step == 3 || widget.step == 7
                          ? Semantics(
                            selected: _card == card,
                            child: OutlinedButton(
                              key: ValueKey('lesson-card-${card.wire}'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(6),
                                backgroundColor:
                                    _card == card
                                        ? const Color(0xFF2A5B53)
                                        : const Color(0xFF123638),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed:
                                  () => _update(
                                    revision,
                                    () => _reset(card: card),
                                  ),
                              child: Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 24,
                                    child: Stack(
                                      children: [
                                        BattleCardArt(card: card),
                                        if (_card == card)
                                          const Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Icon(
                                              Icons.check_circle_rounded,
                                              size: 12,
                                              color: BattleTokens.gold,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      l.battleCardName(card),
                                      style: BattleTokens.card.copyWith(
                                        fontSize: 12,
                                        height: 1.15,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          : BattleCardTile(
                            key: ValueKey('lesson-card-${card.wire}'),
                            card: card,
                            cost: cardDefinitions[card]!.cost,
                            selected: _card == card,
                            onSelect:
                                () =>
                                    _update(revision, () => _reset(card: card)),
                            onDetail: () {
                              if (_active) {
                                showBattleCatalogDetail(context, card);
                              }
                            },
                          ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        if (cardDefinitions[_card]!.target == CardTargetType.opponentCard &&
            _view.rules.phase == BattlePhase.card)
          SizedBox(
            height:
                100 +
                (MediaQuery.textScalerOf(context).scale(13) / 13 - 1) * 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final action in _actions.whereType<PlayCardAction>().where(
                  (a) => a.card == _card,
                ))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 140,
                      child: OutlinedButton(
                        key: ValueKey('lesson-opponent-${action.target}'),
                        onPressed:
                            () => _update(revision, () {
                              _stateRevision++;
                              _selection.play = action;
                              _wrongTap = false;
                            }),
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              _selection.play?.key == action.key
                                  ? const Color(0xFF2A5B53)
                                  : const Color(0xFF123638),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                        ).copyWith(
                          backgroundBuilder:
                              (_, _, child) => child ?? const SizedBox(),
                        ),
                        child: Column(
                          children: [
                            SizedBox.square(
                              dimension: 48,
                              child: BattleCardArt(
                                card: CardId.parse(action.target as String),
                              ),
                            ),
                            Text(
                              l.battleCardName(
                                CardId.parse(action.target as String),
                              ),
                              textAlign: TextAlign.center,
                              style: BattleTokens.card.copyWith(
                                fontSize: 13,
                                height: 1.15,
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
        if (!actionBeforeCatalog && _view.rules.phase == BattlePhase.card) ...[
          const SizedBox(height: 8),
          playCommand(),
        ],
        if (widget.step == 3 && !boardTarget && !boardFirst) ...[
          const SizedBox(height: 12),
          _board(),
        ],
        if (_view.rules.phase != BattlePhase.pending)
          ExpansionTile(
            key: const ValueKey('lesson-card-explanation'),
            tilePadding: EdgeInsets.zero,
            expansionAnimationStyle: AnimationStyle(
              duration: BattleTokens.duration(context),
              reverseDuration: BattleTokens.duration(context),
            ),
            title: Text(l.battleCardName(_card), style: BattleTokens.card),
            children: [
              Text(
                l.battleCardDescription(_card),
                style: BattleTokens.body.copyWith(fontSize: 15, height: 1.25),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_view.knowledge.radarObservations.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l.learning('Radar sonucu:', 'Radar result:'),
            style: BattleTokens.body,
          ),
          for (final observation in _view.knowledge.radarObservations)
            _KnowledgeCard(
              card: observation.queriedCardId,
              label:
                  '${l.battleCardName(observation.queriedCardId)} · ${l.battle(observation.inHand ? BattleCopy.inHand : BattleCopy.notInHand)}',
            ),
        ],
        if (_view.knowledge.pendingCards.isNotEmpty) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, card) in _pendingOrder.indexed)
                SizedBox(
                  width:
                      100 +
                      (MediaQuery.textScalerOf(context).scale(12) / 12 - 1) *
                          40,
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: 48,
                        child: BattleCardArt(card: card),
                      ),
                      Text(
                        '${index + 1}. ${l.battleCardName(card)}',
                        textAlign: TextAlign.center,
                        style: BattleTokens.caption.copyWith(height: 1.15),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_pendingOrder.length > 1)
            TextButton.icon(
              key: const ValueKey('lesson-swap-order'),
              onPressed:
                  () => _update(revision, () {
                    _stateRevision++;
                    _pendingOrder = pendingOrder.reversed.toList();
                  }),
              icon: const Icon(Icons.swap_vert_rounded),
              label: Text(
                l.learning('Kartların yerini değiştir', 'Swap the card order'),
              ),
            ),
          BattleCommand(
            key: const ValueKey('lesson-resolve'),
            label: l.learning('SIRAYI ONAYLA', 'CONFIRM ORDER'),
            icon: Icons.check,
            art: 'confirm',
            onPressed:
                () => _update(
                  revision,
                  () => _apply(ResolveAction(pendingOrder)),
                ),
          ),
        ],
        if (_view.knowledge.knownUpcomingCards.isNotEmpty) ...[
          Text(l.battle(BattleCopy.upcoming), style: BattleTokens.title),
          for (final card in _view.knowledge.knownUpcomingCards)
            _KnowledgeCard(card: card, label: l.battleCardName(card)),
        ],
        if (_cast)
          LunoEntrance(
            key: ValueKey('lesson-success-${_card.wire}'),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _moved
                    ? l.learning(
                      'Hamlen tamam. Eğitim adımına devam edebilirsin.',
                      'Move complete. You can continue to the next lesson.',
                    )
                    : _view.rules.phase == BattlePhase.pending
                    ? l.learning(
                      'Etki uygulandı. Önce kartların sırasını onayla.',
                      'Effect applied. Confirm the card order first.',
                    )
                    : widget.step == 7
                    ? l.learning(
                      'Bilgi kartı tamamlandı. Sonraki adıma geçebilirsin.',
                      'Information card complete. Continue to the next lesson.',
                    )
                    : l.learning(
                      'Etki uygulandı. Mana harcandı; şimdi hamleni tamamla.',
                      'Effect applied. Mana spent; now finish your move.',
                    ),
                style: BattleTokens.body.copyWith(color: BattleTokens.success),
              ),
            ),
          ),
        _goals(l),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BattleAudioFeedback(view: _view, child: _content(context));
  }

  Widget _content(BuildContext context) {
    final revision = _stateRevision;
    final l = LunoLocalizations.of(context);
    if (battleLessonCards(widget.step).isNotEmpty) return _cardPractice(l);
    switch (widget.step) {
      case 1:
        return Column(
          children: [
            _guide(l),
            const SizedBox(height: 8),
            _board(),
            const SizedBox(height: 8),
            _goals(l),
            if (_moved) _retry(l),
          ],
        );
      case 2:
      case 6:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _guide(l),
            const SizedBox(height: 10),
            _board(),
            const SizedBox(height: 10),
            if (widget.step == 6) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  KeyedSubtree(
                    key: _drawSource,
                    child: _Fact(
                      art: 'arsenal',
                      value: '${_view.rules.deckCounts[PieceColor.white]}',
                      label: l.learning('Destede kaldı', 'Left in deck'),
                    ),
                  ),
                  _Fact(
                    art: 'phase-card',
                    value: '${_view.ownHand.length}/4',
                    label: l.learning('Elindeki kartlar', 'Cards in hand'),
                  ),
                ],
              ),
            ],
            Text(
              l.learning('ELİNDEKİ KARTLAR', 'YOUR HAND'),
              style: BattleTokens.title,
            ),
            BattleHand(
              drawSource: _drawSource,
              compact: false,
              view: _view,
              selected: _selection.card,
              enabled: _view.rules.phase == BattlePhase.card,
              cost: (card) => cardDefinitions[card]!.cost,
              selectable: (_) => true,
              onSelect:
                  (card) => _update(revision, () {
                    _stateRevision++;
                    _selection.select(card, _actions);
                    _wrongTap = false;
                  }),
              onDetail: (card) {
                if (_active) showBattleCatalogDetail(context, card);
              },
            ),
            const SizedBox(height: 10),
            _goals(l),
            const SizedBox(height: 8),
            if (_view.rules.phase == BattlePhase.card) ...[
              BattleCommand(
                key: const ValueKey('lesson-pass'),
                label: l.battle(BattleCopy.pass),
                icon: Icons.skip_next,
                art: 'pass',
                onPressed:
                    () => _update(revision, () => _apply(const PassAction())),
              ),
              if (widget.step == 2)
                TextButton.icon(
                  key: const ValueKey('lesson-discard'),
                  onPressed:
                      () => _update(
                        revision,
                        () => _apply(
                          DiscardAction(_selection.card ?? _view.ownHand.first),
                        ),
                      ),
                  icon: const BattleArt('discard', size: 20),
                  label: Text(
                    l.learning(
                      'Bir kartı feda et · Mana vermez',
                      'Discard a card · No mana gained',
                    ),
                  ),
                ),
            ],
            if (_moved) _retry(l),
          ],
        );
      case 8:
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 12,
          children: [
            _Fact(
              art: 'phase-card',
              value: '',
              label: l.learning('Sıralı: kupa kazan', 'Ranked: earn trophies'),
            ),
            _Fact(
              art: 'phase-move',
              value: '',
              label: l.learning('Antrenman: öğren', 'Practice: learn'),
            ),
          ],
        );
      case 9:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, card) in battlePracticeCards.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 42,
                      child: BattleCardArt(card: card),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${index + 1}. ${l.battleCardName(card)}',
                        style: BattleTokens.card,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: BattleTokens.gold,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l.learning(
                'Dört kısa antrenmanda kart oynamayı, hedef seçmeyi, özel hamleyi ve kart feda etmeyi uygula.',
                'Try playing cards, choosing targets, special moves and discarding in four short practices.',
              ),
              style: BattleTokens.body,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const ValueKey('lesson-card-library'),
              expansionAnimationStyle: AnimationStyle(
                duration: BattleTokens.duration(context),
                reverseDuration: BattleTokens.duration(context),
              ),
              tilePadding: EdgeInsets.zero,
              title: Text(
                l.learning('24 kartın tamamını tanı', 'Meet all 24 cards'),
                style: BattleTokens.card,
              ),
              children: [
                for (final card in CardId.values)
                  ListTile(
                    key: ValueKey('lesson-library-${card.wire}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: SizedBox.square(
                      dimension: 38,
                      child: BattleCardArt(card: card),
                    ),
                    title: Text(
                      l.battleCardName(card),
                      style: BattleTokens.card,
                    ),
                    subtitle: Text(
                      '${cardDefinitions[card]!.cost} mana',
                      style: BattleTokens.caption,
                    ),
                    trailing: const BattleArt('info', size: 20),
                    onTap: () {
                      if (_active) showBattleCatalogDetail(context, card);
                    },
                  ),
              ],
            ),
          ],
        );
      default:
        return const Center(
          child: LunoEntrance(
            child: LunoArt(LunoAssets.lunoPortrait, width: 185, height: 205),
          ),
        );
    }
  }
}

class _LessonGoal extends StatelessWidget {
  final String id, label;
  final bool done;
  const _LessonGoal({
    required this.id,
    required this.label,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return Semantics(
      key: ValueKey('lesson-goal-$id'),
      label: label,
      value:
          done
              ? l.learning('Tamamlandı', 'Complete')
              : l.learning('Bekliyor', 'Pending'),
      liveRegion: done,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 22,
                child: AnimatedSwitcher(
                  duration: BattleTokens.duration(context),
                  child:
                      done
                          ? const BattleArt(
                            'confirm',
                            key: ValueKey(true),
                            size: 22,
                          )
                          : Icon(
                            Icons.radio_button_unchecked_rounded,
                            key: const ValueKey(false),
                            size: 18,
                            color: BattleTokens.secondary,
                          ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: BattleTokens.duration(context),
                  style: BattleTokens.caption.copyWith(
                    color: done ? BattleTokens.success : BattleTokens.secondary,
                  ),
                  child: Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KnowledgeCard extends StatelessWidget {
  final CardId card;
  final String label;
  const _KnowledgeCard({required this.card, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox.square(dimension: 72, child: BattleCardArt(card: card)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: BattleTokens.card)),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  final String art, value, label;
  const _Fact({required this.art, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Column(
      children: [
        BattleArt(art, size: 42),
        if (value.isNotEmpty)
          Text(
            value,
            style: LunoType.sectionTitle.copyWith(
              fontFamily: 'Nunito',
              fontSize: 22,
              color: LunoColors.cyan,
            ),
          ),
        Text(label, textAlign: TextAlign.center, style: LunoType.bodyMuted),
      ],
    ),
  );
}
