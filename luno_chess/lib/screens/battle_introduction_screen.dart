import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../battle_ui/audio_feedback.dart';
import '../battle_ui/board.dart';
import '../battle_ui/cards.dart';
import '../battle_ui/cast_stage.dart';
import '../battle_ui/draw_flow.dart';
import '../battle_ui/draw_motion.dart';
import '../battle_ui/primitives.dart';
import '../battle_ui/sheets.dart';
import '../battle_ui/tokens.dart';
import '../battle_v1/introduction.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_account_modal.dart';
import '../theme/luno_assets.dart';
import '../widgets/luno_surface.dart';
import '../widgets/tutorial_coach.dart';
import '../services/first_session_telemetry.dart';

class BattleIntroductionScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  final GameStore? playerStore;
  const BattleIntroductionScreen({super.key, this.playerStore});
  @override
  State<BattleIntroductionScreen> createState() =>
      _BattleIntroductionScreenState();
}

class _BattleIntroductionScreenState extends State<BattleIntroductionScreen>
    with WidgetsBindingObserver {
  late final int _ownerRevision;
  late final GameStore _ownerStore;
  late final BattleIntroduction _lesson;
  final _draw = BattleDrawTracker();
  final _board = GlobalKey(), _own = GlobalKey(), _opponent = GlobalKey();
  final _deck = GlobalKey();
  final _cards = {for (final card in CardId.values) card: GlobalKey()};
  bool _finishing = false;
  bool _finished = false;
  bool _detailOpen = false;
  bool _foreground = true;
  Timer? _automaticStep;
  Timer? _feedbackTimer;
  bool _wrongTap = false;
  int _feedbackRevision = 0;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  bool get _active =>
      mounted &&
      !_finishing &&
      !_finished &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      identical(store, _ownerStore) &&
      _ownerRevision == store.accountBindingRevision &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ownerStore = store;
    _ownerRevision = store.accountBindingRevision;
    _lesson = BattleIntroduction(checkpoint: store.introductionStep);
    _draw.observe(_lesson.view, _lesson.version);
    final telemetry = FirstSessionTelemetry.forStore(store);
    unawaited(telemetry.recordFirstOpen(_ownerRevision));
    telemetry.record(FirstSessionEvent.introStarted, _ownerRevision);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scheduleAutomaticStep(),
    );
  }

  @override
  void didUpdateWidget(BattleIntroductionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(store, _ownerStore)) {
      _automaticStep?.cancel();
      _feedbackTimer?.cancel();
      _wrongTap = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_active) {
        _feedbackTimer?.cancel();
        if (_wrongTap) setState(() => _wrongTap = false);
      }
      _scheduleAutomaticStep();
    });
  }

  bool get _automatic => const {
    IntroductionStage.draw,
    IntroductionStage.opponent,
    IntroductionStage.mineTriggered,
  }.contains(_lesson.stage);

  void _scheduleAutomaticStep() {
    _automaticStep?.cancel();
    if (!mounted || !_active || !_automatic || _detailOpen) return;
    final checkpoint = _lesson.checkpoint;
    _automaticStep = Timer(
      Duration(
        milliseconds:
            _lesson.stage == IntroductionStage.mineTriggered ? 1600 : 1100,
      ),
      () => _act(checkpoint, _lesson.continueLesson),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {
        _foreground = state == AppLifecycleState.resumed;
        if (!_foreground) _wrongTap = false;
      });
      if (!_foreground) _feedbackTimer?.cancel();
      _scheduleAutomaticStep();
    }
  }

  @override
  void dispose() {
    _automaticStep?.cancel();
    _feedbackTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _act(int checkpoint, bool Function() action) {
    if (!_active || _lesson.checkpoint != checkpoint || !action()) return;
    _feedbackTimer?.cancel();
    _wrongTap = false;
    FirstSessionTelemetry.forStore(store).record(
      FirstSessionEvent.introStepCompleted,
      _ownerRevision,
      step: checkpoint,
    );
    _draw.observe(_lesson.view, _lesson.version);
    setState(() {});
    unawaited(store.setIntroductionStep(_lesson.checkpoint, _ownerRevision));
    _scheduleAutomaticStep();
  }

  void _tapSquare(int checkpoint, int square) {
    if (!_active ||
        checkpoint != _lesson.checkpoint ||
        _lesson.expectedSquare == null) {
      return;
    }
    if (square == _lesson.expectedSquare) {
      _act(checkpoint, () => _lesson.tapSquare(square));
      return;
    }
    _feedbackTimer?.cancel();
    setState(() {
      _wrongTap = true;
      _feedbackRevision++;
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 1400), () {
      if (_active && checkpoint == _lesson.checkpoint) {
        setState(() => _wrongTap = false);
      }
    });
  }

  Future<void> _detail(CardId card) async {
    if (!_active || _detailOpen || !_lesson.view.ownHand.contains(card)) return;
    _detailOpen = true;
    try {
      await showLunoAccountBottomSheet<void>(
        context: context,
        playerStore: store,
        backgroundColor: BattleTokens.background,
        builder: (_) => CardDetailSheet(card: card, view: _lesson.view),
      );
    } finally {
      _detailOpen = false;
      _scheduleAutomaticStep();
    }
  }

  Future<void> _finish() async {
    if (!_active) return;
    _automaticStep?.cancel();
    _feedbackTimer?.cancel();
    setState(() => _finishing = true);
    try {
      await store.completeIntroduction(_ownerRevision);
      if (mounted &&
          identical(store, _ownerStore) &&
          store.accountBindingRevision == _ownerRevision &&
          store.hasCompletedTutorial) {
        _finished = true;
        _wrongTap = false;
        FirstSessionTelemetry.forStore(store).record(
          _lesson.stage == IntroductionStage.victory
              ? FirstSessionEvent.introFinished
              : FirstSessionEvent.introSkipped,
          _ownerRevision,
        );
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  String _speech(LunoLocalizations l) =>
      _wrongTap
          ? l.learning('Parlayan kareyi dene.', 'Try the highlighted square.')
          : switch (_lesson.stage) {
            IntroductionStage.firstPiece => l.learning(
              'a2 karesindeki piyonuna dokun.',
              'Tap your pawn on a2.',
            ),
            IntroductionStage.firstDestination => l.learning(
              'a3 karesine ilerle.',
              'Move to a3.',
            ),
            IntroductionStage.draw => l.learning(
              'Siper desteden eline geldi.',
              'Shelter moved from deck to hand.',
            ),
            IntroductionStage.mana => l.learning(
              'Mayın kartına dokun.',
              'Tap Mine.',
            ),
            IntroductionStage.mineTarget => l.learning(
              'Mayın için c4 karesini seç.',
              'Choose c4 for your mine.',
            ),
            IntroductionStage.mineConfirm => l.learning(
              'c4 hazır. Mayını yerleştir.',
              'c4 is ready. Place Mine.',
            ),
            IntroductionStage.secondPiece => l.learning(
              'Kart tamam; taş hamlen sende. a3 piyonuna dokun.',
              'Card played; you still move. Tap your a3 pawn.',
            ),
            IntroductionStage.secondDestination => l.learning(
              'Piyonunu a4 karesine ilerlet.',
              'Move your pawn to a4.',
            ),
            IntroductionStage.opponent => l.learning(
              'Atım c4 karesindeki mayına geliyor.',
              'My knight is heading for your mine on c4.',
            ),
            IntroductionStage.mineTriggered => l.learning(
              'Mayın tetiklendi: atım sonraki hamlesinde taş alamaz.',
              'Mine triggered: my knight cannot capture on its next move.',
            ),
            IntroductionStage.finalTurn => l.learning(
              'Kart isteğe bağlı. Bu tur kart adımını geç.',
              'Cards are optional. Skip the card step this turn.',
            ),
            IntroductionStage.finalPiece => l.learning(
              'g6 karesindeki vezirine dokun.',
              'Tap your queen on g6.',
            ),
            IntroductionStage.finalDestination => l.learning(
              'g7 karesine git: şah mat!',
              'Move to g7: checkmate!',
            ),
            IntroductionStage.victory => l.learning(
              'Şimdi Bebek Luno ile gerçek maçın hazır.',
              'Your real match with Baby Luno is ready.',
            ),
          };

  String _command(LunoLocalizations l) => switch (_lesson.stage) {
    IntroductionStage.mineConfirm => l.learning(
      'MAYINI YERLEŞTİR',
      'PLACE MINE',
    ),
    IntroductionStage.opponent => l.learning('LUNO OYNASIN', 'LUNO\'S TURN'),
    IntroductionStage.finalTurn => l.learning(
      'KART ADIMINI GEÇ',
      'SKIP CARD STEP',
    ),
    IntroductionStage.victory => l.learning('OYUNA GEÇ', 'LET\'S PLAY'),
    _ => l.learning('DEVAM ET', 'CONTINUE'),
  };

  double _boardExtent(BuildContext context, BoxConstraints box, String speech) {
    final width = math.min(540.0, MediaQuery.sizeOf(context).width - 24);
    final speechHeight = TutorialCoach.heightFor(context, speech, width);
    var resultHeight = 0.0;
    if (_lesson.stage == IntroductionStage.victory) {
      final painter = TextPainter(
        text: TextSpan(
          text: LunoLocalizations.of(
            context,
          ).learning('ŞAH MAT!', 'CHECKMATE!'),
          style: BattleTokens.title.copyWith(
            color: BattleTokens.gold,
            height: 1.2,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width);
      resultHeight = painter.height + 8;
      painter.dispose();
    }
    return math.min(
      math.min(440, width),
      math.max(180, box.maxHeight - speechHeight - 34 - resultHeight),
    );
  }

  Widget _focusCard(LunoLocalizations l, int checkpoint) {
    final view = _lesson.view;
    final expanded =
        _lesson.stage == IntroductionStage.draw ||
        _lesson.stage == IntroductionStage.mana;
    final focus =
        _lesson.stage == IntroductionStage.draw ? CardId.shelter : CardId.mine;
    final mana = view.rules.mana[PieceColor.white]!;
    final spent =
        _lesson.stage == IntroductionStage.secondPiece ||
        _lesson.stage == IntroductionStage.secondDestination;
    return Padding(
      key: _own,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height:
            expanded
                ? 134
                : 64 +
                    (MediaQuery.textScalerOf(context).scale(12) / 12 - 1) * 24,
        child: Row(
          children: [
            SizedBox(
              width: expanded ? 106 : 48,
              height: expanded ? 130 : 58,
              child: BattleCardArrival(
                key: _cards[focus],
                card: focus,
                source: _deck,
                trigger:
                    _draw.notice?.ownCard == focus
                        ? _draw.notice?.version
                        : null,
                child:
                    expanded
                        ? BattleCardTile(
                          key: ValueKey('hand-${focus.wire}'),
                          card: focus,
                          cost: cardDefinitions[focus]!.cost,
                          compact: true,
                          enabled:
                              _active &&
                              _lesson.stage == IntroductionStage.mana,
                          onSelect:
                              () => _act(
                                checkpoint,
                                () => _lesson.selectCard(focus),
                              ),
                        )
                        : BattleCardArt(card: focus),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BattleMana(
                    label: l.learning('Mana', 'Mana'),
                    value: mana,
                    compact: true,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spent
                        ? l.learning(
                          '${cardDefinitions[CardId.mine]!.cost} mana harcandı',
                          '${cardDefinitions[CardId.mine]!.cost} mana spent',
                        )
                        : expanded
                        ? l.learning(
                          'Elin ${view.ownHand.length}/4',
                          'Hand ${view.ownHand.length}/4',
                        )
                        : l.learning(
                          '${cardDefinitions[focus]!.cost} mana',
                          '${cardDefinitions[focus]!.cost} mana',
                        ),
                    key: ValueKey(
                      spent
                          ? 'introduction-mana-result'
                          : 'introduction-hand-count',
                    ),
                    style: BattleTokens.caption,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    key: _deck,
                    width: 28,
                    height: 34,
                    child: const BattleClosedCard(),
                  ),
                  Text(
                    l.learning('Deste', 'Deck'),
                    style: BattleTokens.caption.copyWith(
                      fontSize: 10,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '${view.rules.deckCounts[PieceColor.white]}',
                    style: BattleTokens.caption.copyWith(height: 1.1),
                  ),
                ],
              ),
            ),
            if (expanded)
              IconButton(
                key: const ValueKey('introduction-card-information'),
                tooltip: l.learning('Kart bilgisi', 'Card details'),
                onPressed: () => _detail(focus),
                icon: const Icon(Icons.info_outline_rounded),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context), view = _lesson.view;
    final checkpoint = _lesson.checkpoint;
    final showHand = const {
      IntroductionStage.draw,
      IntroductionStage.mana,
      IntroductionStage.mineTarget,
      IntroductionStage.mineConfirm,
      IntroductionStage.secondPiece,
      IntroductionStage.secondDestination,
    }.contains(_lesson.stage);
    final victory = _lesson.stage == IntroductionStage.victory;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.learning('İLK HAMLE', 'FIRST MOVE'),
          style: BattleTokens.title,
        ),
        actions: [
          TextButton(
            key: const ValueKey('introduction-skip'),
            onPressed: _finishing || _finished ? null : _finish,
            child: Text(l.learning('ATLA', 'SKIP')),
          ),
        ],
      ),
      body: BattleAudioFeedback(
        view: view,
        child: BattleCastStage(
          view: view,
          board: _board,
          own: _own,
          opponent: _opponent,
          cards: _cards,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Opacity(
                opacity: .25,
                child: LunoArt(
                  LunoAssets.phase2TutorialAcademy,
                  fit: BoxFit.cover,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value:
                          (_lesson.checkpoint + 1) /
                          IntroductionStage.values.length,
                      minHeight: 3,
                      semanticsLabel: l.learning(
                        'İlk hamle ilerlemesi',
                        'First move progress',
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder:
                            (context, box) => SingleChildScrollView(
                              key: const ValueKey('introduction-body'),
                              padding: const EdgeInsets.all(12),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 540,
                                  ),
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        key: _opponent,
                                        width: double.infinity,
                                      ),
                                      TutorialCoach(
                                        text: _speech(l),
                                        cue:
                                            '${_lesson.stage}:$_feedbackRevision',
                                        feedback: _wrongTap,
                                      ),
                                      const SizedBox(height: 10),
                                      if (victory)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            l.learning(
                                              'ŞAH MAT!',
                                              'CHECKMATE!',
                                            ),
                                            style: BattleTokens.title.copyWith(
                                              color: BattleTokens.gold,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      SizedBox(
                                        key: _board,
                                        width: _boardExtent(
                                          context,
                                          box,
                                          _speech(l),
                                        ),
                                        child: BattleBoard(
                                          view: view,
                                          selected: _lesson.selected,
                                          targets: {
                                            if (_lesson.expectedSquare
                                                case final int square)
                                              square,
                                          },
                                          preview:
                                              _lesson.stage ==
                                                      IntroductionStage
                                                          .mineConfirm
                                                  ? {2 + 3 * 8}
                                                  : const {},
                                          enabled:
                                              _active &&
                                              _lesson.expectedSquare != null,
                                          externalCastAnimation: true,
                                          onTap:
                                              (square) => _tapSquare(
                                                checkpoint,
                                                square,
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
                    if (showHand)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: _focusCard(l, checkpoint),
                        ),
                      ),
                    if (victory || (_lesson.hasCommand && !_automatic))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: SizedBox(
                            width: double.infinity,
                            child: LunoButton(
                              key: ValueKey(
                                'introduction-command-${_lesson.stage.name}',
                              ),
                              label: _command(l),
                              icon:
                                  victory
                                      ? Icons.play_arrow_rounded
                                      : Icons.arrow_forward_rounded,
                              loading: _finishing,
                              onPressed:
                                  _finishing || _finished
                                      ? null
                                      : victory
                                      ? _finish
                                      : () => _act(
                                        checkpoint,
                                        _lesson.continueLesson,
                                      ),
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
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
