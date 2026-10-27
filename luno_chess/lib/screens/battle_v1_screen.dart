import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../battle_v1/core.dart';
import '../battle_v1/local_session.dart';
import '../battle_v1/model.dart';
import '../battle_v1/online.dart';
import '../battle_v1/pending_store.dart';
import '../battle_v1/emotes.dart';
import '../battle_v1/practice.dart';
import '../battle_ui/emotes.dart';
import '../battle_ui/cast_stage.dart';
import '../battle_ui/audio_feedback.dart';
import '../battle_ui/effect_timing.dart';
import '../battle_ui/practice_coach.dart';
import '../engine/ai.dart';
import '../models/game_store.dart';
import '../theme/luno_assets.dart';
import '../battle_ui/art.dart';
import '../battle_ui/action_guide.dart';
import '../battle_ui/board.dart';
import '../battle_ui/cards.dart';
import '../battle_ui/draw_flow.dart';
import '../battle_ui/accepted_frames.dart';
import '../battle_ui/draw_motion.dart';
import '../battle_ui/interaction.dart';
import '../battle_ui/hotseat_privacy.dart';
import '../battle_ui/legal_actions.dart';
import '../battle_ui/feedback.dart';
import '../battle_ui/layout.dart';
import '../battle_ui/primitives.dart';
import '../battle_ui/private.dart';
import '../battle_ui/sheets.dart';
import '../battle_ui/tokens.dart';
import '../engine/piece.dart';
import '../engine/move_gen.dart';
import '../engine/square.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_route.dart';
import '../services/luno_feedback.dart';
import '../services/luno_audio_service.dart';
import '../services/luno_online_service.dart';
import '../services/first_session_telemetry.dart';
import '../services/account_operation_guard.dart';
import '../services/battle_welcome_reward.dart';
import '../services/screen_request_timeouts.dart';
import '../battle_v1/deck_account.dart';
import 'online_hub_screen.dart';
import 'battle_deck_screen.dart';

class BattleV1Screen extends StatefulWidget implements LunoAccountScopedPage {
  final String? matchId;
  final Map<String, dynamic>? initialView;
  final int? initialServerNow;
  final bool local;
  final int timeControlMinutes;
  final Object? level;
  final int? practiceStage;
  final bool practiceCanExit;
  final bool practiceOnboarding;
  final bool guidedFirstMatch;
  final Future<void> Function()? onPracticeComplete;
  final Future<void> Function()? onPracticeSkip;
  final Future<void> Function(BattleLearningCheckpoint)? onPracticeProgress;
  final BattleLearningCheckpoint? practiceCheckpoint;
  final BattleV1Request? requestOverride;
  final BattleV1Controller? controllerOverride;
  @visibleForTesting
  final BattleV1LocalSession? localSessionOverride;
  @visibleForTesting
  final int Function(PieceColor)? clockOverride;
  @visibleForTesting
  final LunoOnlineService? rewardOnline;
  final LunoOnlineService? deckOnline;
  const BattleV1Screen({
    super.key,
    this.matchId,
    this.initialView,
    this.initialServerNow,
    this.local = false,
    this.timeControlMinutes = 5,
    this.level,
    this.practiceStage,
    this.practiceCanExit = false,
    this.practiceOnboarding = false,
    this.guidedFirstMatch = false,
    this.onPracticeComplete,
    this.onPracticeSkip,
    this.onPracticeProgress,
    this.practiceCheckpoint,
    this.requestOverride,
    this.controllerOverride,
    this.localSessionOverride,
    this.clockOverride,
    this.rewardOnline,
    this.deckOnline,
  });
  @override
  State<BattleV1Screen> createState() => _BattleV1ScreenState();
}

class _BattleV1ScreenState extends State<BattleV1Screen>
    with WidgetsBindingObserver {
  BattleV1Controller? controller;
  BattleV1LocalSession? localSession;
  BattlePracticeProgress? practice;
  BattleEmoteChannel? emotes;
  final Set<int> _heardEmotes = {};
  final selection = BattleInteraction();
  final _legalActionCache = BattleLegalActionCache();
  final _drawSource = GlobalKey();
  final _opponentDeckSource = GlobalKey();
  final _opponentHandTarget = GlobalKey();
  Offset? _exchangeOrigin;
  final _drawTracker = BattleDrawTracker();
  final _presentationTracker = BattlePresentationTracker();
  final _hotseatPrivacy = BattleHotseatPrivacy();
  int _resumeEpoch = 0;
  final _battleBoard = GlobalKey();
  final _ownSource = GlobalKey();
  final _opponentSource = GlobalKey();
  final _cardSources = {for (final card in CardId.values) card: GlobalKey()};
  late final Object _musicLease;
  Timer? poll;
  final Stopwatch _pollClock = Stopwatch()..start();
  bool _pollRunning = false;
  int _pollEpoch = 0, _pollFailures = 0, _pollNotBefore = 0;
  ModalRoute<dynamic>? sheetRoute;
  Object? sheetToken;
  int? sheetVersion;
  bool initializing = true,
      sending = false,
      sheetOpen = false,
      allowExit = false;
  bool resultAcknowledged = false, resultBusy = false, resultError = false;
  Future<bool>? resultAck;
  Object? loadError;
  bool _localDeckError = false;
  late final int _ownerRevision;
  int _journeyMatch = 0;
  bool _resultTracked = false;
  final _resultTimeouts = ScreenRequestTimeouts();
  bool _welcomeBusy = false, _welcomeConfirmed = false, _welcomeError = false;
  int _welcomeEpoch = 0;
  bool _rankedStartedTracked = false, _rankedCompletedTracked = false;
  int _lastDrawTrackedVersion = -1;
  bool _foreground = true;
  bool _progressionRefreshed = false;
  bool _sessionObserved = true;
  bool _ownerInvalidated = false;
  bool get isServer =>
      widget.matchId != null || widget.controllerOverride != null;
  bool get _isHotseat => widget.local && !isServer;
  bool get _hotseatConcealed =>
      _isHotseat && !terminal && !_hotseatPrivacy.revealed;
  bool _hotseatInputCurrent(int epoch) =>
      !_isHotseat ||
      (_hotseatPrivacy.revealed && _hotseatPrivacy.epoch == epoch);
  PlayerView? get view =>
      _ownerInvalidated
          ? null
          : isServer
          ? controller?.view
          : localSession?.view;
  int get version =>
      isServer
          ? controller?.snapshot?.stateVersion ?? -1
          : localSession?.version ?? -1;
  bool get terminal =>
      controller?.snapshot?.result != null ||
      localSession?.terminal != null ||
      view?.rules.phase == BattlePhase.terminal;
  bool get ready =>
      !_ownerInvalidated &&
      !_hotseatConcealed &&
      practice?.stopsPlay != true &&
      !initializing &&
      !sending &&
      !terminal &&
      loadError == null &&
      controller?.busy != true &&
      controller?.error == null &&
      controller?.hasPendingIntent != true &&
      localSession?.busy != true;
  bool get _canInteract =>
      mounted &&
      _foreground &&
      !_hotseatConcealed &&
      _ownerRevision == GameStore.instance.accountBindingRevision &&
      ModalRoute.of(context)?.isCurrent == true;
  SessionMatchMode get _mode =>
      isServer
          ? SessionMatchMode.online
          : widget.local
          ? SessionMatchMode.local
          : SessionMatchMode.ai;
  bool get _focusedLessonCard =>
      widget.practiceOnboarding &&
      practice?.guidedMatch != true &&
      practice?.freePlay != true &&
      practice?.cast != true &&
      selection.card != null;
  List<BattleAction> get actions {
    final current = view;
    final legal =
        terminal || current == null
            ? const <BattleAction>[]
            : _legalActionCache.forView(current);
    if (current == null) return legal;
    return practice?.lessonActions(current, legal) ?? legal;
  }

  String get _pieceSet {
    final data = GameStore.instance.data;
    return data.ownedPieceSets.contains(data.pieceSet) ? data.pieceSet : 'luno';
  }

  int _remaining(PieceColor side) =>
      widget.clockOverride?.call(side) ??
      (isServer
          ? controller!.remainingMillis(sideWire(side))
          : localSession!.remaining(side));
  @override
  void initState() {
    super.initState();
    _ownerRevision = GameStore.instance.accountBindingRevision;
    GameStore.instance.addListener(_accountChanged);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _musicLease = LunoAudioService.instance.holdScene(LunoMusicScene.battle);
    WidgetsBinding.instance.addObserver(this);
    if (widget.practiceStage case final int stage) {
      if (stage < 0 ||
          stage >= (widget.practiceOnboarding ? 3 : 4) ||
          widget.matchId != null ||
          widget.local ||
          (widget.guidedFirstMatch &&
              (!widget.practiceOnboarding || stage != 0))) {
        throw ArgumentError('Invalid practice configuration');
      }
      practice = BattlePracticeProgress(
        stage,
        onboarding: widget.practiceOnboarding,
        guidedMatch: widget.guidedFirstMatch,
        checkpoint:
            widget.practiceCheckpoint ?? const BattleLearningCheckpoint(),
      );
    } else if (widget.guidedFirstMatch) {
      throw ArgumentError(
        'A guided first match requires onboarding stage zero',
      );
    }
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      if (isServer) {
        controller = widget.controllerOverride;
        if (controller == null) {
          final online = LunoOnlineService.instance,
              uid = LunoOnlineService.instance.user?.uid;
          if (uid == null) throw StateError('Account required');
          final ownerRevision = online.accountRevision;
          bool ownsSession() =>
              mounted &&
              !_ownerInvalidated &&
              _ownerRevision == GameStore.instance.accountBindingRevision &&
              online.user?.uid == uid &&
              online.accountRevision == ownerRevision;
          final prefs = await SharedPreferences.getInstance();
          if (!ownsSession()) return;
          final pendingStore = BattleV1PendingStore(
            prefs,
            uid: uid,
            matchId: widget.matchId!,
          );
          final initialServerNow =
              widget.initialServerNow ??
              online.battleV1ServerNow(widget.matchId!);
          controller = BattleV1Controller(
            uid: uid,
            matchId: widget.matchId!,
            isSessionCurrent: ownsSession,
            request: (path, body) async {
              if (!ownsSession()) {
                throw const BattleV1Rejection('session-changed');
              }
              final response =
                  widget.requestOverride != null
                      ? await widget.requestOverride!(path, body)
                      : await online.battleV1Api(
                        path,
                        body,
                        ownerUid: uid,
                        ownerRevision: ownerRevision,
                      );
              if (!ownsSession()) {
                throw const BattleV1Rejection('session-changed');
              }
              return response;
            },
            persistPending: pendingStore.persist,
            pendingJson: pendingStore.pendingJson,
            pendingPersisted: pendingStore.pendingPersisted,
            initialResponse:
                widget.initialView == null || initialServerNow == null
                    ? null
                    : {
                      'ok': true,
                      'matchId': widget.matchId,
                      'status':
                          (widget.initialView!['public'] as Map)['result'] ==
                                  null
                              ? 'active'
                              : 'finished',
                      'view': widget.initialView,
                      'serverNow': initialServerNow,
                    },
          );
        }
        controller!.addListener(_changed);
        if (widget.controllerOverride == null) {
          await controller!.reconnect();
          if (!mounted || _ownerInvalidated) return;
          if (controller!.hasPendingIntent) await controller!.retryPending();
        }
        if (!mounted || _ownerInvalidated) return;
        _startPolling();
      } else {
        final activeDeck = await _resolveLocalDeck();
        if (!mounted || _ownerInvalidated) return;
        localSession =
            widget.localSessionOverride ??
            BattleV1LocalSession(
              hotseat: widget.local,
              minutes: widget.timeControlMinutes,
              level:
                  practice?.level ??
                  (widget.level is AiLevel
                      ? widget.level as AiLevel
                      : aiLevels.first),
              practice: practice != null,
              practiceDeck: practice?.deck,
              activeDeck: activeDeck,
              cardFeedbackDelay: battleCardFeedbackPacingDuration,
            );
        localSession!.addListener(_changed);
      }
      if (!mounted || _ownerInvalidated) return;
      emotes = BattleEmoteChannel(
        request: isServer ? controller!.request : null,
        matchId: controller?.matchId,
      )..addListener(_emoteChanged);
      if (widget.controllerOverride == null) unawaited(emotes!.fetch());
    } catch (cause) {
      loadError = cause;
    }
    if (mounted && !_ownerInvalidated) {
      setState(() {
        initializing = false;
        if (view != null) {
          _syncHotseatViewer();
          selection.synchronize(view!, version);
          if (!_hotseatConcealed) {
            _drawTracker.observe(
              view!,
              version,
              epoch: _resumeEpoch + (controller?.synchronizationEpoch ?? 0),
            );
            _presentationTracker.observe(
              view!,
              version,
              epoch: _resumeEpoch + (controller?.synchronizationEpoch ?? 0),
            );
          }
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncLocalVisibility();
        _recordMatchStart();
        _trackRankedState();
      });
      _refreshSettledDeck();
    }
  }

  Future<List<CardId>?> _resolveLocalDeck() async {
    if (widget.local || practice != null) return null;
    final account = await _resultTimeouts.run(
      (widget.deckOnline ?? LunoOnlineService.instance).resolveAiBattleDeck(),
      const Duration(seconds: 15),
    );
    if (_ownerInvalidated ||
        _ownerRevision != GameStore.instance.accountBindingRevision) {
      throw const LunoApiException('session-changed', 409);
    }
    return account.deck;
  }

  String _deckUnavailable(LunoLocalizations l) => l.learning(
    'Aktif desten doğrulanamadı. Bağlantını kontrol edip yeniden dene. '
        'Başka bir desteyle maç başlatılmadı.',
    'Your active deck could not be confirmed. Check your connection and retry. '
        'No match was started with a different deck.',
  );

  Future<void> _retryStart() async {
    if (!_canInteract || initializing || localSession != null) return;
    setState(() {
      initializing = true;
      loadError = null;
    });
    await _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route visibility may change while this battle stays mounted underneath.
    ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncLocalVisibility();
        if (!_emotePresentationCurrent) {
          emotes?.clear();
          LunoAudioService.instance.cancelEmotes();
        }
      }
    });
  }

  void _syncLocalVisibility() {
    if (localSession == null) return;
    final visible =
        _foreground &&
        _ownerRevision == GameStore.instance.accountBindingRevision &&
        (ModalRoute.of(context)?.isCurrent == true ||
            sheetRoute?.isCurrent == true) &&
        practice?.stopsPlay != true;
    if (_sessionObserved == visible) return;
    _sessionObserved = visible;
    localSession!.observe(visible);
  }

  void _syncHotseatViewer() {
    if (_isHotseat && view != null && _hotseatPrivacy.observe(view!.viewer)) {
      _clearHotseatPresentation();
    }
  }

  void _clearHotseatPresentation() {
    selection.cancel();
    _exchangeOrigin = null;
    _drawTracker.reset();
    _presentationTracker.reset();
    _resumeEpoch++;
    Tooltip.dismissAllToolTips();
    FocusManager.instance.primaryFocus?.unfocus();
    emotes?.clear();
    LunoAudioService.instance.cancelEmotes();
    final route = sheetRoute;
    sheetToken = null;
    sheetRoute = null;
    sheetVersion = null;
    sheetOpen = false;
    // No reverse transition: a departing private sheet must never linger.
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
  }

  void _acknowledgeHotseat(PieceColor side, int epoch) {
    if (!mounted ||
        !_isHotseat ||
        !_foreground ||
        terminal ||
        _ownerInvalidated ||
        _ownerRevision != GameStore.instance.accountBindingRevision ||
        ModalRoute.of(context)?.isCurrent != true ||
        view?.viewer != side) {
      return;
    }
    // Admission checks the clock too, including time spent behind the curtain.
    localSession?.checkTimeout();
    if (terminal || !_hotseatPrivacy.acknowledge(side, epoch)) return;
    setState(() {
      selection.synchronize(view!, version);
      final presentationEpoch = _resumeEpoch;
      _drawTracker.observe(view!, version, epoch: presentationEpoch);
      _presentationTracker.observe(view!, version, epoch: presentationEpoch);
    });
  }

  void _leaveHotseat() {
    if (!mounted ||
        !_foreground ||
        _ownerInvalidated ||
        _ownerRevision != GameStore.instance.accountBindingRevision ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => allowExit = true);
    Navigator.pop(context);
  }

  void _accountChanged() {
    if (!mounted ||
        _ownerInvalidated ||
        _ownerRevision == GameStore.instance.accountBindingRevision) {
      return;
    }
    _stopPolling();
    localSession?.observe(false);
    emotes?.clear();
    LunoAudioService.instance.releaseScene(_musicLease);
    final route = sheetRoute;
    setState(() {
      _ownerInvalidated = true;
      initializing = false;
      if (_isHotseat) {
        _hotseatPrivacy.conceal();
        _clearHotseatPresentation();
      }
      selection.cancel();
      _drawTracker.reset();
      _presentationTracker.reset();
      _resumeEpoch++;
      _welcomeEpoch++;
    });
    controller?.invalidateSession();
    if (route?.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && route!.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  void _recordMatchStart() {
    if (!mounted ||
        _ownerInvalidated ||
        _ownerRevision != GameStore.instance.accountBindingRevision ||
        practice != null ||
        view == null ||
        loadError != null) {
      return;
    }
    if (terminal) {
      _recordMatchCompletion();
      return;
    }
    if (_journeyMatch != 0) return;
    final store = GameStore.instance;
    _journeyMatch = store.recordFirstSessionMatchStart(_ownerRevision);
    if (_journeyMatch != 0) {
      FirstSessionTelemetry.forStore(store).record(
        _journeyMatch == 1
            ? FirstSessionEvent.firstMatchStarted
            : FirstSessionEvent.secondMatchStarted,
        _ownerRevision,
        mode: _mode,
      );
    }
  }

  void _changed() {
    if (!mounted || _ownerInvalidated) return;
    _recordMatchStart();
    setState(() {
      if (view != null) {
        _syncHotseatViewer();
        selection.synchronize(view!, version);
        if (!_hotseatConcealed) {
          _drawTracker.observe(
            view!,
            version,
            epoch: _resumeEpoch + (controller?.synchronizationEpoch ?? 0),
          );
          _presentationTracker.observe(
            view!,
            version,
            epoch: _resumeEpoch + (controller?.synchronizationEpoch ?? 0),
          );
        }
      }
    });
    _trackDraw();
    _trackRankedState();
    _refreshSettledDeck();
    if ((terminal || sheetVersion != version) && sheetRoute?.isActive == true) {
      final route = sheetRoute!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  void _recordMatchCompletion() {
    if (!mounted ||
        _ownerInvalidated ||
        practice != null ||
        !terminal ||
        view == null ||
        _ownerRevision != GameStore.instance.accountBindingRevision) {
      return;
    }
    final store = GameStore.instance;
    // Recovered finished matches need not have had a visible start in this
    // screen (or process). Never turn a duplicate terminal view into match two.
    if (_journeyMatch == 0 && store.needsFirstSessionMatch) {
      setState(() {
        _journeyMatch = store.recordFirstSessionMatchStart(_ownerRevision);
      });
    }
    if (_journeyMatch != 1 ||
        !store.recordFirstSessionMatchCompletion(_ownerRevision)) {
      return;
    }
    final result = controller?.snapshot?.result;
    final winner =
        localSession?.terminal?.winner ??
        (result?['winner'] == 'w'
            ? PieceColor.white
            : result?['winner'] == 'b'
            ? PieceColor.black
            : view!.rules.terminal?.winner);
    FirstSessionTelemetry.forStore(store).record(
      FirstSessionEvent.firstMatchFinished,
      _ownerRevision,
      mode: _mode,
      result:
          winner == null
              ? SessionMatchResult.draw
              : winner == view!.viewer
              ? SessionMatchResult.win
              : SessionMatchResult.loss,
    );
  }

  void _trackDraw() {
    final notice = _drawTracker.notice;
    if (practice != null ||
        notice?.ownCard == null ||
        notice!.version == _lastDrawTrackedVersion ||
        _ownerRevision != GameStore.instance.accountBindingRevision) {
      return;
    }
    _lastDrawTrackedVersion = notice.version;
    FirstSessionTelemetry.forStore(
      GameStore.instance,
    ).record(FirstSessionEvent.cardDrawn, _ownerRevision, mode: _mode);
  }

  void _trackRankedState() {
    if (!_canInteract ||
        practice != null ||
        controller?.snapshot?.public['rated'] != true) {
      return;
    }
    final event =
        terminal
            ? FirstSessionEvent.rankedCompleted
            : FirstSessionEvent.rankedStarted;
    if (terminal ? _rankedCompletedTracked : _rankedStartedTracked) return;
    if (terminal) {
      _rankedCompletedTracked = true;
    } else {
      _rankedStartedTracked = true;
    }
    FirstSessionTelemetry.forStore(
      GameStore.instance,
    ).record(event, _ownerRevision, mode: SessionMatchMode.online);
  }

  void _trackAcceptedCard(BattleAction action) {
    if (practice != null ||
        _ownerRevision != GameStore.instance.accountBindingRevision) {
      return;
    }
    final event = switch (action) {
      PlayCardAction() => FirstSessionEvent.cardPlayed,
      DiscardAction() => FirstSessionEvent.cardDiscarded,
      _ => null,
    };
    if (event != null) {
      FirstSessionTelemetry.forStore(
        GameStore.instance,
      ).record(event, _ownerRevision, mode: _mode);
    }
  }

  void _refreshSettledDeck() {
    final online = LunoOnlineService.instance;
    if (_progressionRefreshed ||
        !isServer ||
        !online.ready ||
        online.user?.uid != controller?.uid ||
        controller?.snapshot?.settlement?.rated != true ||
        _ownerRevision != GameStore.instance.accountBindingRevision) {
      return;
    }
    _progressionRefreshed = true;
    unawaited(
      Future.wait([online.getBattleV1Deck(), online.refreshState()]).catchError(
        (Object _) {
          if (mounted &&
              _ownerRevision == GameStore.instance.accountBindingRevision) {
            _progressionRefreshed = false;
          }
          return <dynamic>[];
        },
      ),
    );
  }

  bool get _emotePresentationCurrent =>
      mounted &&
      _foreground &&
      !_ownerInvalidated &&
      !terminal &&
      _ownerRevision == GameStore.instance.accountBindingRevision &&
      (ModalRoute.of(context)?.isCurrent == true ||
          sheetRoute?.isCurrent == true);

  void _emoteChanged() {
    if (!mounted) return;
    final channel = emotes;
    if (channel == null ||
        channel.muted ||
        channel.visible.isEmpty ||
        !_emotePresentationCurrent) {
      LunoAudioService.instance.cancelEmotes();
      if (channel != null) {
        for (final event in channel.visible.values) {
          _heardEmotes.add(event.sequence);
        }
        while (_heardEmotes.length > 32) {
          _heardEmotes.remove(_heardEmotes.first);
        }
      }
    } else {
      for (final event in channel.visible.values) {
        if (!_heardEmotes.add(event.sequence)) continue;
        if (_heardEmotes.length > 32) _heardEmotes.remove(_heardEmotes.first);
        unawaited(
          LunoAudioService.instance.playEmote(
            event.emojiId,
            isCurrent:
                () =>
                    _emotePresentationCurrent &&
                    identical(emotes, channel) &&
                    !channel.muted &&
                    channel.visible[event.side]?.sequence == event.sequence,
          ),
        );
      }
    }
    setState(() {});
  }

  Future<void> _emoji() async {
    final channel = emotes;
    if (!_canInteract || channel == null || terminal || sheetOpen) return;
    final data = GameStore.instance.data;
    final ids =
        [
          ...data.emojiLoadout.where(data.ownedEmojis.contains),
          ...data.ownedEmojis.where((id) => !data.emojiLoadout.contains(id)),
        ].take(4).toList();
    await _sheet<void>(
      BattleSheet(
        title: LunoLocalizations.of(context).learning('İfadeler', 'Emotes'),
        child: BattleEmotePicker(
          channel: channel,
          ids: ids,
          onSend: (id) async {
            if (!mounted || terminal || sheetRoute?.isCurrent != true) return;
            final sent = await channel.send(id, view!.viewer, data.ownedEmojis);
            if (sent && mounted && sheetRoute?.isCurrent == true) {
              sheetRoute?.navigator?.pop();
            }
          },
        ),
      ),
    );
  }

  Widget _coach(BattleCoachFocus target, Widget child) {
    if (practice == null) return child;
    final focused =
        practiceFocus(
          practice!,
          view!,
          selection.card,
          selection.play != null &&
              (!movementCards.contains(selection.card) ||
                  selection.specialDestination != null),
        ) ==
        target;
    final position =
        focused && target == BattleCoachFocus.board
            ? _boardCoachPosition()
            : null;
    return BattleCoachTarget(
      active: focused && (target != BattleCoachFocus.board || position != null),
      arrowPosition: position,
      child: child,
    );
  }

  Alignment? _boardCoachPosition() {
    final square = battlePracticeBoardSquare(view!, selection, actions);
    if (square == null) return null;
    return Alignment(
      (Square.fileOf(square) + .5) / 4 - 1,
      ((7 - Square.rankOf(square) + .5) / 4 - 1 - .14).clamp(-.95, .95),
    );
  }

  Future<void> _completePractice() async {
    if (!_canInteract ||
        view == null ||
        practice?.canFinish(view!) != true ||
        view!.rules.pending != null ||
        (!terminal && selection.card != null) ||
        resultBusy ||
        widget.onPracticeComplete == null) {
      return;
    }
    setState(() {
      resultBusy = true;
      resultError = false;
    });
    localSession?.observe(false);
    _sessionObserved = false;
    try {
      await widget.onPracticeComplete!();
    } catch (_) {
      if (mounted) setState(() => resultError = true);
    } finally {
      if (mounted) {
        setState(() => resultBusy = false);
        _syncLocalVisibility();
      }
    }
  }

  void _startPolling() {
    _stopPolling();
    if (!mounted ||
        !_foreground ||
        _ownerInvalidated ||
        !isServer ||
        widget.controllerOverride != null) {
      return;
    }
    _pollFailures = 0;
    _pollNotBefore = 0;
    poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted &&
          _foreground &&
          !_ownerInvalidated &&
          _ownerRevision == GameStore.instance.accountBindingRevision &&
          !_pollRunning &&
          _pollClock.elapsedMilliseconds >= _pollNotBefore &&
          (ModalRoute.of(context)?.isCurrent == true || sheetOpen) &&
          (!terminal ||
              controller?.snapshot?.public['settlementStatus'] == 'pending')) {
        unawaited(_pollOnce(_pollEpoch));
      }
    });
  }

  void _stopPolling() {
    _pollEpoch++;
    poll?.cancel();
    poll = null;
  }

  Future<void> _pollOnce(int epoch) async {
    _pollRunning = true;
    try {
      await controller?.reconnect(synchronization: false);
      if (!mounted ||
          !_foreground ||
          _ownerInvalidated ||
          epoch != _pollEpoch) {
        return;
      }
      if (controller?.error == null) {
        _pollFailures = 0;
        _pollNotBefore = 0;
      } else {
        if (_pollFailures < 4) _pollFailures++;
        _pollNotBefore =
            _pollClock.elapsedMilliseconds + (2000 << _pollFailures);
      }
      if (!terminal) await emotes?.fetch();
    } finally {
      _pollRunning = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_ownerInvalidated) return;
    if (_isHotseat && state != AppLifecycleState.resumed) {
      _hotseatPrivacy.conceal();
      _clearHotseatPresentation();
    }
    if (state == AppLifecycleState.resumed) {
      _syncLocalVisibility();
      _startPolling();
      unawaited(controller?.reconnect());
      unawaited(emotes?.fetch());
    } else {
      _resumeEpoch++;
      _drawTracker.reset();
      _presentationTracker.reset();
      _stopPolling();
      localSession?.observe(false);
      _sessionObserved = false;
      emotes?.clear();
    }
    if (mounted && _isHotseat) setState(() {});
  }

  @override
  void dispose() {
    if (practice == null && _journeyMatch == 1 && !terminal) {
      FirstSessionTelemetry.forStore(GameStore.instance).record(
        FirstSessionEvent.firstMatchAbandoned,
        _ownerRevision,
        mode: _mode,
      );
    }
    LunoAudioService.instance.releaseScene(_musicLease);
    _resultTimeouts.dispose();
    _welcomeEpoch++;
    _stopPolling();
    _pollClock.stop();
    WidgetsBinding.instance.removeObserver(this);
    GameStore.instance.removeListener(_accountChanged);
    controller?.removeListener(_changed);
    if (widget.controllerOverride == null) controller?.dispose();
    localSession?.removeListener(_changed);
    if (!identical(localSession, widget.localSessionOverride)) {
      localSession?.dispose();
    }
    emotes?.removeListener(_emoteChanged);
    LunoAudioService.instance.cancelEmotes();
    emotes?.dispose();
    _hotseatPrivacy.dispose();
    super.dispose();
  }

  Future<bool> _sendOne(
    BattleAction action, {
    bool explicitCardPass = true,
  }) async {
    final privacyEpoch = _hotseatPrivacy.epoch;
    if (!_canInteract ||
        terminal ||
        view == null ||
        !BattleRulesCore.isLegalAction(view!, action) ||
        !actions.any((a) => a.key == action.key)) {
      return false;
    }
    if (!isServer) {
      final session = localSession!;
      final before = view!;
      final accepted = await session.submit(action);
      if (!accepted ||
          !mounted ||
          _ownerInvalidated ||
          !identical(localSession, session) ||
          _ownerRevision != GameStore.instance.accountBindingRevision) {
        return false;
      }
      // Visibility can change after authority acceptance, before this resumes.
      if (practice != null) {
        final wasComplete = practice!.complete;
        setState(
          () => practice!.accepted(
            action,
            before,
            session.view,
            explicitCardPass: explicitCardPass,
          ),
        );
        if (widget.onPracticeProgress case final save?) {
          unawaited(save(practice!.checkpoint));
        }
        if (practice!.complete) {
          if (practice!.stopsPlay) session.observe(false);
          if (!wasComplete && _canInteract) {
            unawaited(
              LunoAudioService.instance.playEffect(LunoSound.lessonComplete),
            );
          }
        }
      }
      if (_canInteract && _hotseatInputCurrent(privacyEpoch)) {
        _trackAcceptedCard(action);
      }
      return _canInteract && _hotseatInputCurrent(privacyEpoch);
    }
    if (controller!.busy ||
        controller!.error != null ||
        controller!.hasPendingIntent) {
      return false;
    }
    final previous = version;
    final submitted = await controller!.submit(action);
    final accepted =
        submitted &&
        _canInteract &&
        controller!.error == null &&
        !controller!.hasPendingIntent &&
        version > previous;
    if (accepted) _trackAcceptedCard(action);
    return accepted;
  }

  Future<void> _apply(
    BattleAction action, {
    ChessMoveAction? boundDestination,
    int? hotseatEpoch,
  }) async {
    if (!_canInteract ||
        !ready ||
        (hotseatEpoch != null && !_hotseatInputCurrent(hotseatEpoch)) ||
        practice?.stopsPlay == true) {
      return;
    }
    setState(() => sending = true);
    LunoFeedback.tap();
    try {
      if (action is ChessMoveAction && view!.rules.phase == BattlePhase.card) {
        if (selection.card != null || !actions.any((a) => a is PassAction)) {
          return;
        }
        if (!await _sendOne(const PassAction(), explicitCardPass: false) ||
            !_canInteract) {
          return;
        }
      }
      if (!await _sendOne(action) || !_canInteract) return;
      if (boundDestination != null &&
          view?.rules.special != null &&
          view!.rules.board.turn == view!.viewer) {
        await _sendOne(boundDestination);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<T?> _sheet<T>(Widget child, {int? hotseatEpoch}) async {
    if (sheetOpen ||
        !_canInteract ||
        (hotseatEpoch != null && !_hotseatInputCurrent(hotseatEpoch))) {
      return null;
    }
    final privacyEpoch = _hotseatPrivacy.epoch;
    final token = Object();
    sheetToken = token;
    sheetOpen = true;
    sheetVersion = version;
    try {
      final result = await showModalBottomSheet<T>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: BattleTokens.background,
        sheetAnimationStyle: AnimationStyle(
          duration: LunoMotion.adaptive(context, LunoMotion.panelEnter),
          reverseDuration: LunoMotion.adaptive(context, LunoMotion.panelExit),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        builder: (ctx) {
          final route = ModalRoute.of(ctx);
          if (sheetToken == token) {
            sheetRoute = route;
          } else if (_isHotseat && route?.isActive == true) {
            // The app can hide before this route's first builder invocation.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && route!.isActive) {
                route.navigator?.removeRoute(route);
              }
            });
          }
          if (!_isHotseat) return child;
          return AnimatedBuilder(
            animation: _hotseatPrivacy,
            builder:
                (_, _) =>
                    _foreground &&
                            _hotseatPrivacy.revealed &&
                            _hotseatPrivacy.epoch == privacyEpoch
                        ? child
                        : const SizedBox.shrink(),
          );
        },
      );
      return _canInteract &&
              (!_isHotseat || _hotseatPrivacy.epoch == privacyEpoch)
          ? result
          : null;
    } finally {
      if (sheetToken == token) {
        sheetOpen = false;
        sheetRoute = null;
        sheetVersion = null;
        sheetToken = null;
      }
    }
  }

  Future<void> _detail(CardId card) async {
    final v = view;
    if (v != null) await _sheet<void>(CardDetailSheet(card: card, view: v));
  }

  Future<void> _privateChoice() async {
    if (!ready || view?.rules.pending?.owner != view?.viewer) return;
    final capturedVersion = version;
    final privacyEpoch = _hotseatPrivacy.epoch;
    final picked = await _sheet<ResolveAction>(
      PrivateChoiceSheet(
        view: view!,
        actions: actions.whereType<ResolveAction>().toList(),
        onTakeOrigin: (_, bounds) {
          if (_canInteract &&
              version == capturedVersion &&
              _hotseatInputCurrent(privacyEpoch)) {
            _exchangeOrigin = bounds.center;
          }
        },
      ),
    );
    if (mounted && picked != null && ready && version == capturedVersion) {
      await _apply(picked);
    }
  }

  Future<void> _arsenal({bool target = false}) async {
    final v = view;
    if (v == null) return;
    final capturedVersion = version;
    final eligible =
        target
            ? selection
                .options(actions)
                .map((a) => a.target)
                .whereType<String>()
                .map(CardId.parse)
                .toSet()
            : <CardId>{};
    final picked = await _sheet<CardId>(
      OpponentArsenalSheet(
        rules: v.rules,
        opponent: v.viewer.opposite,
        eligible: eligible,
      ),
    );
    if (!mounted || picked == null || !ready || version != capturedVersion) {
      return;
    }
    final candidates = selection
        .options(actions)
        .where((a) => a.target == picked.wire);
    if (candidates.length == 1) {
      setState(() => selection.play = candidates.single);
    }
  }

  Future<void> _select(CardId card) async {
    if (!_canInteract || !ready) return;
    setState(() => selection.select(card, actions));
    LunoFeedback.tap();
    if (selection.card == null) return;
    // Discard-only selections have no play target or sacrifice dialog.
    final choices = selection.options(actions);
    if (choices.isEmpty) return;
    final target = cardDefinitions[card]!.target;
    if (target == CardTargetType.opponentCard) await _arsenal(target: true);
    if (target == CardTargetType.sacrifice) {
      await _choices(choices, selectionOnly: true);
    }
  }

  String _label(BattleAction action) {
    final l = LunoLocalizations.of(context), v = view!;
    if (action is ChessMoveAction) {
      return l.battlePiece(switch (action.uci.length > 4 ? action.uci[4] : '') {
        'n' => PieceType.knight,
        'r' => PieceType.rook,
        'b' => PieceType.bishop,
        _ => PieceType.queen,
      });
    }
    if (action is PlayCardAction) {
      if (action.sacrifice != null) {
        return '${l.battle(BattleCopy.discard)}: ${l.battleCardName(action.sacrifice!)}';
      }
      for (final effect in v.rules.boardEffects) {
        if (effect.id == action.target) {
          return '${l.battleCardName(switch (effect.type) {
            BoardEffectType.mine => CardId.mine,
            BoardEffectType.lockedSquare => CardId.lockedSquare,
            BoardEffectType.fog => CardId.fog,
            BoardEffectType.boardSeal => CardId.boardSeal,
          })} · ${effect.squares.map(Square.algebraic).join(', ')}';
        }
      }
      for (final effect in v.rules.pieceEffects) {
        if (effect.id == action.target) {
          return l.battleCardName(switch (effect.type) {
            PieceEffectType.shelter => CardId.shelter,
            PieceEffectType.chain => CardId.chain,
            PieceEffectType.slow => CardId.slow,
            PieceEffectType.freeze => CardId.freeze,
            PieceEffectType.mineDebuff => CardId.mine,
          });
        }
      }
    }
    return l.battle(BattleCopy.confirm);
  }

  Future<void> _choices(
    List<BattleAction> options, {
    bool selectionOnly = false,
  }) async {
    if (options.isEmpty || !ready) return;
    final capturedVersion = version;
    BattleAction? picked;
    if (options.length == 1) {
      picked = options.single;
    } else {
      picked = await _sheet<BattleAction>(
        BattleActionChoices(
          pieceSet: _pieceSet,
          pieceSide: view!.viewer,
          title: LunoLocalizations.of(context).battle(
            options.first is ChessMoveAction
                ? BattleCopy.promotion
                : selection.card == CardId.fateExchange ||
                    selection.card == CardId.shadowContract
                ? BattleCopy.chooseSacrifice
                : BattleCopy.chooseEffect,
          ),
          actions: options,
          label: _label,
        ),
      );
    }
    if (!mounted || picked == null || !ready || version != capturedVersion) {
      return;
    }
    if (selectionOnly && picked is PlayCardAction) {
      final choice = picked;
      setState(() => selection.play = choice);
    } else {
      await _apply(picked);
    }
  }

  void _tap(int square) {
    if (!_canInteract || !ready || view == null) return;
    final options = selection.tap(square, view!, actions);
    LunoFeedback.tap();
    setState(() {});
    if (options.isNotEmpty) {
      unawaited(
        _choices(options, selectionOnly: options.first is PlayCardAction),
      );
    }
  }

  Future<void> _retry() async {
    if (!_canInteract || controller == null || controller!.busy) return;
    if (controller!.hasPendingIntent) {
      await controller!.retryPending();
      if (!_canInteract || controller!.hasPendingIntent) return;
    }
    await controller!.reconnect();
  }

  Future<void> _menu() async {
    if (!_canInteract || sheetOpen) return;
    final l = LunoLocalizations.of(context);
    final command = await _sheet<String>(
      Builder(
        builder:
            (sheetContext) => BattleSheet(
              title: l.battle(BattleCopy.menu),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!terminal && (practice == null || practice!.guidedMatch))
                    BattleCommand(
                      key: const ValueKey('resign-menu'),
                      label: l.battle(BattleCopy.resign),
                      icon: Icons.flag,
                      art: 'discard',
                      danger: true,
                      onPressed:
                          ready
                              ? () => dismissBattleSheet(sheetContext, 'resign')
                              : null,
                    ),
                  const SizedBox(height: 8),
                  BattleCommand(
                    label:
                        practice != null
                            ? l.learning(
                              'Antrenmanı yeniden başlat',
                              'Restart practice',
                            )
                            : l.battle(BattleCopy.leave),
                    icon: Icons.home,
                    art: 'close',
                    onPressed:
                        () => dismissBattleSheet(
                          sheetContext,
                          'restart-or-leave',
                        ),
                  ),
                  if (practice != null && widget.practiceCanExit)
                    BattleCommand(
                      key: const ValueKey('leave-practice'),
                      label: l.battle(BattleCopy.leave),
                      icon: Icons.home,
                      art: 'close',
                      onPressed:
                          () => dismissBattleSheet(sheetContext, 'leave'),
                    ),
                  if (practice != null && widget.onPracticeSkip != null)
                    BattleCommand(
                      key: const ValueKey('skip-learning-menu'),
                      label: l.learning(
                        'Eğitimi şimdilik geç',
                        'Skip training for now',
                      ),
                      icon: Icons.skip_next_rounded,
                      art: 'close',
                      onPressed:
                          () =>
                              dismissBattleSheet(sheetContext, 'skip-learning'),
                    ),
                ],
              ),
            ),
      ),
    );
    if (!mounted || command == null) return;
    if (command == 'skip-learning') {
      final confirmed = await _sheet<bool>(
        Builder(
          builder:
              (sheetContext) => BattleSheet(
                title: l.learning(
                  'Eğitimi şimdilik geç?',
                  'Skip training for now?',
                ),
                child: BattleCommand(
                  label: l.learning(
                    'Rehberden tekrar açabilirim',
                    'I can replay it from the Guide',
                  ),
                  icon: Icons.school_rounded,
                  art: 'confirm',
                  onPressed: () => dismissBattleSheet(sheetContext, true),
                ),
              ),
        ),
      );
      if (confirmed == true && _canInteract && widget.onPracticeSkip != null) {
        localSession?.observe(false);
        await widget.onPracticeSkip!();
      }
      return;
    }
    if (command != 'resign') {
      if (practice != null && command != 'leave') {
        _restartLocal(allowActive: true);
        return;
      }
      setState(() => allowExit = true);
      Navigator.pop(context);
      return;
    }
    final confirm = await _sheet<bool>(
      Builder(
        builder:
            (sheetContext) => BattleSheet(
              title: l.battle(BattleCopy.resignQuestion),
              child: BattleCommand(
                label: l.battle(BattleCopy.resign),
                icon: Icons.flag,
                art: 'confirm',
                danger: true,
                onPressed: () => dismissBattleSheet(sheetContext, true),
              ),
            ),
      ),
    );
    if (!mounted || confirm != true || !ready) return;
    if (isServer) {
      await controller!.resign();
    } else {
      localSession!.resign();
    }
  }

  Future<void> _restartLocal({bool allowActive = false}) async {
    if (!_canInteract ||
        resultBusy ||
        isServer ||
        (!allowActive && !terminal)) {
      return;
    }
    setState(() {
      resultBusy = true;
      _localDeckError = false;
    });
    List<CardId>? activeDeck;
    try {
      activeDeck = await _resolveLocalDeck();
    } catch (_) {
      if (mounted && !_ownerInvalidated) {
        setState(() {
          resultBusy = false;
          _localDeckError = true;
        });
      }
      return;
    }
    if (!mounted || _ownerInvalidated || !_canInteract) {
      if (mounted) setState(() => resultBusy = false);
      return;
    }
    if (practice == null && _journeyMatch == 1) {
      FirstSessionTelemetry.forStore(GameStore.instance).record(
        FirstSessionEvent.secondMatchPressed,
        _ownerRevision,
        mode: _mode,
      );
    }
    emotes?.clear();
    _welcomeEpoch++;
    _resultTimeouts.cancelPending();
    localSession?.removeListener(_changed);
    if (!identical(localSession, widget.localSessionOverride)) {
      localSession?.dispose();
    }
    setState(() {
      resultBusy = false;
      resultError = false;
      _journeyMatch = 0;
      _resultTracked = false;
      _welcomeConfirmed = false;
      _welcomeError = false;
      _welcomeBusy = false;
      _lastDrawTrackedVersion = -1;
      _drawTracker.reset();
      _presentationTracker.reset();
      if (_isHotseat) {
        _hotseatPrivacy.reset();
        _clearHotseatPresentation();
      }
      if (widget.practiceStage case final int stage) {
        practice = BattlePracticeProgress(
          stage,
          onboarding: widget.practiceOnboarding,
          guidedMatch: widget.guidedFirstMatch,
          checkpoint:
              widget.practiceCheckpoint ?? const BattleLearningCheckpoint(),
        );
      }
      selection.cancel();
      localSession = BattleV1LocalSession(
        hotseat: widget.local,
        minutes: widget.timeControlMinutes,
        level:
            practice?.level ??
            (widget.level is AiLevel
                ? widget.level as AiLevel
                : aiLevels.first),
        practice: practice != null,
        practiceDeck: practice?.deck,
        activeDeck: activeDeck,
        cardFeedbackDelay: battleCardFeedbackPacingDuration,
      )..addListener(_changed);
      _syncHotseatViewer();
      selection.synchronize(localSession!.view, localSession!.version);
    });
    _recordMatchStart();
  }

  Future<bool> _ackResult() =>
      resultAck ??= _ackResultOnce().then((ok) {
        if (!ok) resultAck = null;
        return ok;
      });

  Future<bool> _ackResultOnce() async {
    if (!isServer || resultAcknowledged) return true;
    final owned =
        widget.controllerOverride != null ||
        LunoOnlineService.instance.user?.uid == controller?.uid;
    if (!owned || !terminal || controller == null) return false;
    try {
      if (controller!.hasPendingIntent) {
        await controller!.retryPending();
        if (controller!.hasPendingIntent) return false;
      }
      final response = await _resultTimeouts.run(
        controller!.request('/ackBattleV1Result', {
          'matchId': controller!.matchId,
          'protocolVersion': battleV1Protocol,
        }),
        const Duration(seconds: 15),
      );
      final stillOwned =
          widget.controllerOverride != null ||
          LunoOnlineService.instance.user?.uid == controller?.uid;
      if (response['ok'] != true || !stillOwned) return false;
      resultAcknowledged = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _newOnlineMatch() async {
    if (resultBusy || !terminal || !_canInteract) {
      return;
    }
    setState(() {
      resultBusy = true;
      resultError = false;
    });
    if (_journeyMatch == 1) {
      FirstSessionTelemetry.forStore(GameStore.instance).record(
        FirstSessionEvent.secondMatchPressed,
        _ownerRevision,
        mode: _mode,
      );
    }
    final acknowledged = await _ackResult();
    if (!mounted) return;
    if (!_canInteract) {
      setState(() {
        resultBusy = false;
        resultError = !acknowledged;
      });
      return;
    }
    if (!acknowledged) {
      setState(() {
        resultBusy = false;
        resultError = true;
      });
      return;
    }
    await Navigator.of(context).pushReplacement(
      lunoRoute(OnlineHubScreen(requestOverride: widget.requestOverride)),
    );
  }

  Future<void> _claimWelcome() async {
    if (!_canInteract ||
        !terminal ||
        _welcomeBusy ||
        _welcomeConfirmed ||
        _journeyMatch != 1) {
      return;
    }
    final store = GameStore.instance,
        online = widget.rewardOnline ?? LunoOnlineService.instance;
    final guard = AccountOperationGuard(store, online);
    final epoch = ++_welcomeEpoch;
    bool active() =>
        mounted &&
        guard.isCurrent &&
        _canInteract &&
        terminal &&
        _welcomeEpoch == epoch &&
        _journeyMatch == 1;
    final uid = online.user?.uid;
    if (uid == null || store.accountUid != uid) {
      setState(() => _welcomeError = true);
      return;
    }
    setState(() {
      _welcomeBusy = true;
      _welcomeError = false;
    });
    try {
      final response = await _resultTimeouts.run(
        online.claimOnboardingReward(),
        const Duration(seconds: 15),
      );
      if (!active()) return;
      BattleWelcomeReward.fromResponse(response);
      store.applyServerState(
        Map<String, dynamic>.from(response['state'] as Map),
      );
      final deckResponse = await _resultTimeouts.run(
        online.getBattleV1Deck(),
        const Duration(seconds: 15),
      );
      if (!active()) return;
      final account = BattleDeckAccount.fromResponse(deckResponse);
      if (!account.owned.contains(CardId.mine)) {
        throw const FormatException('Unconfirmed Mine ownership');
      }
      setState(() => _welcomeConfirmed = true);
      FirstSessionTelemetry.forStore(
        store,
      ).record(FirstSessionEvent.cardUnlocked, _ownerRevision);
      LunoFeedback.tap();
    } catch (_) {
      if (active()) setState(() => _welcomeError = true);
    } finally {
      if (mounted && guard.isCurrent && _welcomeEpoch == epoch) {
        setState(() => _welcomeBusy = false);
      }
    }
  }

  Widget _resultScreen(PlayerView playerView) {
    final l = LunoLocalizations.of(context);
    return Scaffold(
      backgroundColor: BattleTokens.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: BattleArt('background', fit: BoxFit.cover),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  key: const ValueKey('battle-controls-scroll'),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _result(),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        key: const ValueKey('result-review-board'),
                        title: Text(
                          l.learning('Tahtayı incele', 'Review the board'),
                          style: BattleTokens.body,
                        ),
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: BattleBoard(
                              view: playerView,
                              pieceSet: _pieceSet,
                              finish: GameStore.instance.data.activeSkin,
                              enabled: false,
                              onTap: (_) {},
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcomeRewardPanel() {
    final l = LunoLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_welcomeConfirmed) ...[
          SizedBox(height: 96, child: BattleCardArt(card: CardId.mine)),
          Text(
            l.learning(
              'Mayın koleksiyonunda! Destenle denemeye hazır.',
              'Mine is in your collection! Try it in your deck.',
            ),
            style: BattleTokens.body,
            textAlign: TextAlign.center,
          ),
        ] else
          BattleCommand(
            key: const ValueKey('claim-welcome-reward'),
            label: l.learning(
              'Karşılama ödülü · 500 altın + Mayın',
              'Welcome reward · 500 gold + Mine',
            ),
            icon: Icons.card_giftcard_rounded,
            art: 'mine',
            loading: _welcomeBusy,
            onPressed: _welcomeBusy ? null : _claimWelcome,
          ),
        Text(
          l.learning(
            'Hesabına bir kez verilir; maç sonucundan bağımsızdır.',
            'One welcome gift per account, independent of the match result.',
          ),
          style: BattleTokens.caption,
          textAlign: TextAlign.center,
        ),
        if (_welcomeError)
          Text(
            l.learning(
              'Bağlanınca tekrar deneyebilirsin. Tekrar oynama etkilenmez.',
              'Retry when connected. You can still play again.',
            ),
            style: BattleTokens.body,
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _result() {
    final l = LunoLocalizations.of(context),
        result = controller?.snapshot?.result;
    final own = view!.viewer;
    final winner =
        localSession?.terminal?.winner ??
        (result?['winner'] == 'w'
            ? PieceColor.white
            : result?['winner'] == 'b'
            ? PieceColor.black
            : view!.rules.terminal?.winner);
    final reason =
        localSession?.terminal?.reason ??
        result?['reason'] as String? ??
        view!.rules.terminal?.reason ??
        '';
    if (_canInteract && practice == null && !_resultTracked) {
      _resultTracked = true;
      final telemetry = FirstSessionTelemetry.forStore(GameStore.instance);
      telemetry.record(
        FirstSessionEvent.resultSeen,
        _ownerRevision,
        mode: _mode,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BattleResultHeading(
            key: ValueKey('battle-result-$reason-$winner'),
            winner: winner,
            own: own,
            pieceSet: _pieceSet,
            title: l.battle(
              winner == null
                  ? BattleCopy.draw
                  : winner == own
                  ? BattleCopy.victory
                  : BattleCopy.defeat,
            ),
            reason: l.battleReason(reason),
          ),
          if (practice?.guidedMatch == true)
            BattlePracticeCoach(progress: practice!, view: view!),
          if (!isServer && practice == null)
            Text(
              l.learning(
                'Bu antrenman maçı kupa veya harcanabilir ödül vermez. Sıralı maçlarda ilerleyebilirsin.',
                'Training does not award trophies or spendable rewards. Play ranked to progress.',
              ),
              key: const ValueKey('training-result-policy'),
              style: BattleTokens.caption,
              textAlign: TextAlign.center,
            ),
          if (controller?.snapshot?.settlement case final receipt?)
            Text(
              '${l.battle(BattleCopy.trophyChange)} ${receipt.trophyDelta > 0 ? '+' : ''}${receipt.trophyDelta}',
              style: BattleTokens.body,
              textAlign: TextAlign.center,
            ),
          if (controller?.snapshot?.public['settlementStatus'] == 'pending')
            Text(
              l.battle(BattleCopy.settlementPending),
              style: BattleTokens.body,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          if (isServer) ...[
            if (controller?.error != null ||
                controller?.hasPendingIntent == true) ...[
              BattleCommand(
                key: const ValueKey('terminal-pending-retry'),
                label: l.battle(BattleCopy.retry),
                icon: Icons.sync,
                art: 'sync',
                onPressed: controller!.busy ? null : _retry,
              ),
              const SizedBox(height: 8),
            ],
            BattleCommand(
              key: const ValueKey('new-online-match'),
              label: l.battle(BattleCopy.newMatch),
              icon: Icons.refresh,
              art: 'sync',
              primary: true,
              onPressed:
                  resultBusy ||
                          controller?.busy == true ||
                          controller?.hasPendingIntent == true
                      ? null
                      : _newOnlineMatch,
            ),
            if (resultError)
              Text(l.battle(BattleCopy.unavailable), style: BattleTokens.body),
            const SizedBox(height: 8),
          ],
          if (!isServer && practice?.guidedMatch != true) ...[
            BattleCommand(
              key: const ValueKey('local-rematch'),
              label: l.battle(BattleCopy.rematch),
              icon: Icons.refresh,
              art: 'sync',
              primary: true,
              loading: resultBusy,
              onPressed: resultBusy ? null : () => _restartLocal(),
            ),
            if (_localDeckError)
              Text(_deckUnavailable(l), style: BattleTokens.body),
            const SizedBox(height: 8),
          ],
          if (practice?.canFinish(view!) == true) _practiceContinue(),
          if (practice != null && resultError)
            Text(
              l.learning(
                'İlerlemen kaydedilemedi. Yeniden dene.',
                'Progress could not be saved. Try again.',
              ),
              style: BattleTokens.body,
            ),
          if (practice == null && _journeyMatch == 1) _welcomeRewardPanel(),
          if (practice == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BattleCommand(
                key: const ValueKey('result-deck'),
                label: l.learning('Desteni düzenle', 'Edit your deck'),
                icon: Icons.style,
                art: 'arsenal',
                onPressed:
                    resultBusy
                        ? null
                        : () {
                          if (_canInteract) {
                            Navigator.of(context).push(
                              lunoRoute(
                                BattleDeckScreen(
                                  focusCard:
                                      _welcomeConfirmed ? CardId.mine : null,
                                ),
                              ),
                            );
                          }
                        },
              ),
            ),
          if (practice == null)
            BattleCommand(
              key: const ValueKey('result-home'),
              label: l.battle(BattleCopy.home),
              icon: Icons.home,
              art: 'confirm',
              onPressed: () {
                if (_canInteract) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
        ],
      ),
    );
  }

  String _status() {
    final v = view!, l = LunoLocalizations.of(context);
    if (terminal) return l.battle(BattleCopy.ended);
    if (controller?.error != null) return l.battle(BattleCopy.unavailable);
    if (sending || controller?.hasPendingIntent == true) {
      return l.battle(BattleCopy.pending);
    }
    if (controller?.busy == true) return l.battle(BattleCopy.syncing);
    if (v.rules.pending?.owner == v.viewer) {
      return l.battlePendingChoiceInstruction(v.rules.pending!.card);
    }
    if (v.rules.special != null) return l.battle(BattleCopy.boundMove);
    if (selection.card != null) {
      if (selection.invalidTarget) {
        return l.learning(
          'Bu hedef uygun değil. İşaretli bir hedef seç; eski hedef kaldırıldı.',
          'That target is not valid. Choose a marked target; the old target was cleared.',
        );
      }
      if (!actions.whereType<PlayCardAction>().any(
        (a) => a.card == selection.card,
      )) {
        final cost = BattleRulesCore.effectiveCost(
          v.rules,
          v.viewer,
          selection.card!,
        );
        return cost > v.rules.mana[v.viewer]!
            ? l.learning(
              'Mana yetmiyor: $cost gerekli. Başka kart seç veya feda et.',
              'Not enough mana: $cost needed. Choose another card or discard.',
            )
            : l.learning(
              'Bu kart bu tur oynanamıyor. Başka kart seç veya feda et.',
              'This card cannot be played now. Choose another card or discard.',
            );
      }
      if (selection.play != null &&
          (!movementCards.contains(selection.card) ||
              selection.specialDestination != null)) {
        final action = selection.play!;
        final target = action.target;
        final destination = selection.specialDestination?.uci;
        final targetLabel =
            destination != null
                ? '${destination.substring(0, 2)} → ${destination.substring(2, 4)}'
                : target is int
                ? cardDefinitions[action.card]!.target == CardTargetType.zone
                    ? boardZone(target).map(Square.algebraic).join(', ')
                    : Square.algebraic(target)
                : cardDefinitions[action.card]!.target ==
                    CardTargetType.opponentCard
                ? l.battleCardName(CardId.parse(target as String))
                : target != null || action.sacrifice != null
                ? _label(action)
                : '';
        final choice =
            '${l.battleCardName(action.card)}${targetLabel.isEmpty ? '' : ' · $targetLabel'}';
        return l.learning(
          '$choice hazır. Kartı Oyna ile onayla.',
          '$choice ready. Confirm with Play Card.',
        );
      }
      if (movementCards.contains(selection.card) && selection.piece != null) {
        return l.learning(
          'Şimdi işaretli hedef kareyi seç.',
          'Now choose a marked destination.',
        );
      }
      final target = cardDefinitions[selection.card]!.target;
      if (target == CardTargetType.opponentPiece ||
          target == CardTargetType.opponentSlider) {
        return l.learning(
          'Rakibin işaretli taşına dokun.',
          'Tap a marked opponent piece.',
        );
      }
      if (target == CardTargetType.ownPiece ||
          target == CardTargetType.ownPawn ||
          target == CardTargetType.ownRook ||
          target == CardTargetType.ownKnight ||
          target == CardTargetType.ownBishopRook) {
        return l.learning(
          'Kendi işaretli taşına dokun.',
          'Tap one of your marked pieces.',
        );
      }
      return l.battle(switch (cardDefinitions[selection.card]!.target) {
        CardTargetType.emptySquare => BattleCopy.chooseSquare,
        CardTargetType.zone => BattleCopy.chooseZone,
        CardTargetType.opponentCard => BattleCopy.chooseCard,
        CardTargetType.ownPieceEffect ||
        CardTargetType.opponentBoardEffect => BattleCopy.chooseEffect,
        CardTargetType.none => BattleCopy.play,
        CardTargetType.sacrifice => BattleCopy.chooseSacrifice,
        _ => BattleCopy.choosePiece,
      });
    }
    if (v.rules.board.turn != v.viewer) {
      return l.learning(
        'Rakibin oynuyor. Kartlarını inceleyebilirsin.',
        'Opponent is playing. You can inspect your cards.',
      );
    }
    if (selection.piece case final int square) {
      final effects = v.rules.pieceEffects.where(
        (effect) => effect.pieceId == v.rules.pieceIds[square],
      );
      if (effects.any((effect) => effect.type == PieceEffectType.freeze)) {
        return l.learning(
          'Dondurma: bu taş bu hamlede oynayamaz. Başka taşını seç.',
          'Freeze: this piece cannot move this turn. Choose another piece.',
        );
      }
      final restrictions = <String>[
        if (effects.any((effect) => effect.type == PieceEffectType.chain))
          l.learning(
            'Zincir: bu taş taş yiyemez.',
            'Chain: this piece cannot capture.',
          ),
        if (effects.any((effect) => effect.type == PieceEffectType.mineDebuff))
          l.learning(
            'Mayın: bu taş kendi sonraki hamlesinde taş yiyemez.',
            'Mine: this piece cannot capture on its next move.',
          ),
        if (effects.any((effect) => effect.type == PieceEffectType.slow))
          l.learning(
            'Yavaşlatma: en fazla 2 kare gidebilir.',
            'Slow: it can travel at most 2 squares.',
          ),
      ];
      if (v.rules.phase == BattlePhase.chess &&
          !selection
              .moves(v, actions)
              .any((move) => move.uci.startsWith(Square.algebraic(square)))) {
        return [
          ...restrictions,
          l.learning(
            'Bu taşın şu anda yasal hamlesi yok. Başka taşını seç; hamle hakkın duruyor.',
            'This piece has no legal move right now. Choose another piece; you still have your move.',
          ),
        ].join(' ');
      }
      if (restrictions.isNotEmpty || selection.invalidTarget) {
        return [
          ...restrictions,
          l.learning(
            selection.invalidTarget
                ? 'Bu hedefe gidemezsin. İşaretli karelerden birini veya başka taşını seç.'
                : 'İşaretli karelerden birini veya başka taşını seç.',
            selection.invalidTarget
                ? 'That destination is not legal. Choose a marked square or another piece.'
                : 'Choose a marked square or another piece.',
          ),
        ].join(' ');
      }
    }
    if (v.rules.ownTurns[v.viewer] == 1) {
      return l.battle(BattleCopy.firstTurn);
    }
    if (v.ownHand.isEmpty && v.rules.phase == BattlePhase.card) {
      return l.learning(
        'Elinde kart kalmadı. Taş hamleni yap.',
        'Your hand is empty. Make your chess move.',
      );
    }
    final turn =
        v.rules.phase == BattlePhase.card
            ? l.learning(
              'Kart seç veya doğrudan bir taşını oynat.',
              'Choose a card or move a piece directly.',
            )
            : selection.piece == null
            ? l.learning(
              'Bir taşına dokun, sonra işaretli kareye git.',
              'Tap your piece, then a marked square.',
            )
            : l.learning(
              'İşaretli karelerden birine dokun.',
              'Tap one of the marked squares.',
            );
    return MoveGen.inCheck(v.rules.board, v.rules.board.turn)
        ? '${l.battle(BattleCopy.check)} · $turn'
        : turn;
  }

  @override
  Widget build(BuildContext context) {
    final v = view, l = LunoLocalizations.of(context);
    final hotseatEpoch = _hotseatPrivacy.epoch;
    final selectedPlay = selection.play;
    final selectedCard = selection.card;
    final selectedDestination = selection.specialDestination;
    final compact = MediaQuery.sizeOf(context).width < 450;
    final compactSkip =
        v != null &&
        practice == null &&
        MediaQuery.sizeOf(context).width <= 360 &&
        MediaQuery.sizeOf(context).height < 600 &&
        !BattleTokens.compactText(context) &&
        selection.card == null &&
        controller?.error == null &&
        controller?.hasPendingIntent != true &&
        v.knowledge.knownUpcomingCards.isEmpty &&
        v.knowledge.radarObservations.isEmpty &&
        actions.any((action) => action is PassAction);
    return PopScope(
      canPop: terminal || allowExit || _hotseatConcealed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_menu());
          return;
        }
        if (terminal &&
            isServer &&
            LunoOnlineService.instance.user?.uid == controller?.uid) {
          unawaited(_ackResult().then<void>((_) {}));
        }
      },
      child:
          v == null
              ? BattleLoadingStage(
                message: l.battle(
                  initializing ? BattleCopy.loading : BattleCopy.unavailable,
                ),
                action:
                    initializing
                        ? null
                        : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_ownerInvalidated &&
                                !isServer &&
                                !widget.local &&
                                practice == null) ...[
                              Text(
                                _deckUnavailable(l),
                                key: const ValueKey('ai-deck-unavailable'),
                                style: BattleTokens.body,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              BattleCommand(
                                key: const ValueKey('ai-deck-retry'),
                                label: l.learning('Yeniden dene', 'Retry'),
                                icon: Icons.refresh,
                                art: 'sync',
                                onPressed: _retryStart,
                              ),
                              const SizedBox(height: 8),
                            ],
                            BattleCommand(
                              label: l.battle(BattleCopy.home),
                              icon: Icons.home,
                              art: 'close',
                              onPressed: () {
                                if (!mounted ||
                                    !_foreground ||
                                    ModalRoute.of(context)?.isCurrent != true) {
                                  return;
                                }
                                setState(() => allowExit = true);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
              )
              : _hotseatConcealed
              ? BattleHotseatCurtain(
                side: v.viewer,
                remaining: () => _remaining(v.viewer),
                onReady:
                    _foreground
                        ? () => _acknowledgeHotseat(v.viewer, hotseatEpoch)
                        : null,
                onLeave: _foreground ? _leaveHotseat : null,
              )
              : BattleOpponentDraw(
                trigger:
                    _drawTracker.notice?.opponent == true
                        ? _drawTracker.notice?.version
                        : null,
                source: _opponentDeckSource,
                target: _opponentHandTarget,
                child: BattleAudioFeedback(
                  acceptedFrames: _presentationTracker.frames,
                  synchronizationEpoch:
                      _resumeEpoch + (controller?.synchronizationEpoch ?? 0),
                  view: v,
                  terminal: localSession?.terminal,
                  selectedPiece: selection.piece,
                  selectedCard: selection.card,
                  child: BattleCastStage(
                    acceptedFrames: _presentationTracker.frames,
                    synchronizationEpoch:
                        _resumeEpoch + (controller?.synchronizationEpoch ?? 0),
                    view: v,
                    board: _battleBoard,
                    own: _ownSource,
                    opponent: _opponentSource,
                    cards: _cardSources,
                    child:
                        terminal
                            ? _resultScreen(v)
                            : BattleV1Scaffold(
                              compactBoardDock: practice == null,
                              lessonDock: widget.practiceOnboarding,
                              lessonBoardFocus: _focusedLessonCard,
                              controlsDockedAside: compactSkip,
                              opponent: Row(
                                key: _opponentSource,
                                children: [
                                  Expanded(
                                    child:
                                        widget.practiceOnboarding
                                            ? Row(
                                              children: [
                                                Image.asset(
                                                  LunoAssets.aiPortrait(
                                                    localSession!.level.id,
                                                  ),
                                                  width: 28,
                                                  height: 36,
                                                  cacheWidth: 96,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    l.translate(
                                                      localSession!.level.name,
                                                    ),
                                                    style: BattleTokens.card,
                                                  ),
                                                ),
                                              ],
                                            )
                                            : BattlePlayerHeader(
                                              compact: compact,
                                              portrait:
                                                  !isServer && !widget.local
                                                      ? LunoAssets.aiPortrait(
                                                        localSession!.level.id,
                                                      )
                                                      : null,
                                              name:
                                                  (controller
                                                              ?.snapshot
                                                              ?.public['players']
                                                          as Map?)?[sideWire(
                                                        v.viewer.opposite,
                                                      )]?['name']
                                                      as String? ??
                                                  (widget.local
                                                      ? l.battle(
                                                        BattleCopy.opponent,
                                                      )
                                                      : (localSession == null
                                                              ? null
                                                              : l.translate(
                                                                localSession!
                                                                    .level
                                                                    .name,
                                                              )) ??
                                                          l.battle(
                                                            BattleCopy.opponent,
                                                          )),
                                              side: v.viewer.opposite,
                                              view: v,
                                              deckSource: _opponentDeckSource,
                                              handTarget: _opponentHandTarget,
                                              deck:
                                                  widget.practiceOnboarding
                                                      ? null
                                                      : BattleDeckAccess(
                                                        key: const ValueKey(
                                                          'open-arsenal',
                                                        ),
                                                        compact: true,
                                                        cardCount:
                                                            v
                                                                .rules
                                                                .arsenals[v
                                                                    .viewer
                                                                    .opposite]!
                                                                .length,
                                                        onPressed:
                                                            () => _arsenal(),
                                                      ),
                                              clock:
                                                  practice != null
                                                      ? const SizedBox.shrink()
                                                      : BattleClock(
                                                        compact: compact,
                                                        label: l.battle(
                                                          BattleCopy.opponent,
                                                        ),
                                                        terminal: terminal,
                                                        active:
                                                            v
                                                                .rules
                                                                .board
                                                                .turn ==
                                                            v.viewer.opposite,
                                                        remaining:
                                                            () => _remaining(
                                                              v.viewer.opposite,
                                                            ),
                                                      ),
                                            ),
                                  ),
                                  BattleIconControl(
                                    key: const ValueKey('open-menu'),
                                    icon: Icons.menu,
                                    art: 'menu',
                                    label: l.battle(BattleCopy.menu),
                                    onPressed: _menu,
                                  ),
                                ],
                              ),
                              arsenal:
                                  widget.practiceOnboarding
                                      ? const SizedBox.shrink()
                                      : _handHeader(v),
                              board: KeyedSubtree(
                                key: _battleBoard,
                                child: _coach(
                                  BattleCoachFocus.board,
                                  Opacity(
                                    opacity:
                                        controller?.error != null ? .55 : 1,
                                    child: BattleBoard(
                                      acceptedFrames:
                                          _presentationTracker.frames,
                                      synchronizationEpoch:
                                          _resumeEpoch +
                                          (controller?.synchronizationEpoch ??
                                              0),
                                      pieceSet: _pieceSet,
                                      externalCastAnimation: true,
                                      finish:
                                          GameStore.instance.data.activeSkin,
                                      view: v,
                                      selected: selection.piece,
                                      targets: selection.targets(v, actions),
                                      preview: selection.preview(),
                                      enabled: ready,
                                      onTap: (square) {
                                        if (_hotseatInputCurrent(
                                          hotseatEpoch,
                                        )) {
                                          _tap(square);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              status:
                                  practice != null
                                      ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          BattlePracticeCoach(
                                            progress: practice!,
                                            view: v,
                                            selected: selection.card,
                                            selectedPiece: selection.piece,
                                            invalidTarget:
                                                selection.invalidTarget,
                                            freeInstruction: _status(),
                                            targetReady:
                                                selection.play != null &&
                                                (!movementCards.contains(
                                                      selection.card,
                                                    ) ||
                                                    selection
                                                            .specialDestination !=
                                                        null),
                                            onComplete:
                                                resultBusy
                                                    ? null
                                                    : _completePractice,
                                          ),
                                          if (resultError)
                                            Text(
                                              l.learning(
                                                'İlerlemen kaydedilemedi. Devam düğmesiyle yeniden dene.',
                                                'Progress could not be saved. Use Continue to retry.',
                                              ),
                                              key: const ValueKey(
                                                'practice-save-error',
                                              ),
                                              style: BattleTokens.body,
                                            ),
                                        ],
                                      )
                                      : BattleCastNotice(
                                        view: v,
                                        acceptedFrames:
                                            _presentationTracker.frames,
                                        synchronizationEpoch:
                                            controller?.synchronizationEpoch ??
                                            0,
                                        child: BattleActionGuide(
                                          phase: v.rules.phase,
                                          ownTurn:
                                              v.rules.board.turn == v.viewer,
                                          firstTurn:
                                              v.rules.ownTurns[v.viewer] == 1,
                                          instruction: _status(),
                                          selectedCard: selection.card,
                                          onInstruction: (instruction) {
                                            unawaited(
                                              _sheet<void>(
                                                BattleSheet(
                                                  title: l.learning(
                                                    'Sıradaki hamlen',
                                                    'Your next action',
                                                  ),
                                                  child: Text(
                                                    instruction,
                                                    key: const ValueKey(
                                                      'battle-next-action',
                                                    ),
                                                    style: BattleTokens.body,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                              own:
                                  widget.practiceOnboarding
                                      ? KeyedSubtree(
                                        key: _ownSource,
                                        child: _practiceHandHeader(v),
                                      )
                                      : Column(
                                        key: _ownSource,
                                        children: [
                                          BattlePlayerHeader(
                                            compact: compact,
                                            sidebar: false,
                                            name:
                                                (controller
                                                            ?.snapshot
                                                            ?.public['players']
                                                        as Map?)?[sideWire(
                                                      v.viewer,
                                                    )]?['name']
                                                    as String? ??
                                                l.battle(BattleCopy.you),
                                            side: v.viewer,
                                            view: v,
                                            own: true,
                                            selectedCost:
                                                selection.card == null
                                                    ? null
                                                    : BattleRulesCore.effectiveCost(
                                                      v.rules,
                                                      v.viewer,
                                                      selection.card!,
                                                    ),
                                            clock:
                                                practice != null
                                                    ? const SizedBox.shrink()
                                                    : BattleClock(
                                                      compact: compact,
                                                      label: l.battle(
                                                        BattleCopy.you,
                                                      ),
                                                      terminal: terminal,
                                                      active:
                                                          v.rules.board.turn ==
                                                          v.viewer,
                                                      remaining:
                                                          () => _remaining(
                                                            v.viewer,
                                                          ),
                                                    ),
                                          ),
                                          if (compactSkip)
                                            BattleIconControl(
                                              key: const ValueKey('pass-card'),
                                              icon: Icons.skip_next_rounded,
                                              art: 'pass',
                                              label: l.battle(BattleCopy.pass),
                                              onPressed:
                                                  ready
                                                      ? () => _apply(
                                                        const PassAction(),
                                                        hotseatEpoch:
                                                            hotseatEpoch,
                                                      )
                                                      : null,
                                            ),
                                          if (v
                                                  .knowledge
                                                  .knownUpcomingCards
                                                  .isNotEmpty ||
                                              v
                                                  .knowledge
                                                  .radarObservations
                                                  .isNotEmpty)
                                            BattleIconControl(
                                              icon: Icons.visibility,
                                              art: 'knowledge',
                                              label: l.battle(
                                                BattleCopy.privateKnowledge,
                                              ),
                                              onPressed:
                                                  () => _sheet<void>(
                                                    PrivateKnowledgeSheet(
                                                      knowledge: v.knowledge,
                                                    ),
                                                    hotseatEpoch: hotseatEpoch,
                                                  ),
                                            ),
                                        ],
                                      ),
                              hand:
                                  _focusedLessonCard
                                      ? const SizedBox.shrink()
                                      : _coach(
                                        BattleCoachFocus.hand,
                                        BattleHand(
                                          acceptedFrames:
                                              _presentationTracker.frames,
                                          synchronizationEpoch:
                                              _resumeEpoch +
                                              (controller
                                                      ?.synchronizationEpoch ??
                                                  0),
                                          cardSources: _cardSources,
                                          drawSource: _drawSource,
                                          exchangeOrigin: _exchangeOrigin,
                                          arrival: _drawTracker.notice,
                                          compact: compact,
                                          view: v,
                                          selected: selection.card,
                                          enabled: ready,
                                          cost:
                                              (card) =>
                                                  BattleRulesCore.effectiveCost(
                                                    v.rules,
                                                    v.viewer,
                                                    card,
                                                  ),
                                          selectable:
                                              (card) => actions.any(
                                                (a) =>
                                                    a is DiscardAction &&
                                                        a.card == card ||
                                                    a is PlayCardAction &&
                                                        a.card == card,
                                              ),
                                          onSelect: (card) {
                                            if (_hotseatInputCurrent(
                                              hotseatEpoch,
                                            )) {
                                              unawaited(_select(card));
                                            }
                                          },
                                          onDetail: (card) {
                                            if (_hotseatInputCurrent(
                                              hotseatEpoch,
                                            )) {
                                              unawaited(_detail(card));
                                            }
                                          },
                                        ),
                                      ),
                              controls:
                                  widget.practiceOnboarding &&
                                          practice?.canFinish(v) == true &&
                                          v.rules.pending == null &&
                                          selection.card == null
                                      ? _practiceContinue()
                                      : compactSkip
                                      ? const SizedBox.shrink()
                                      : _coach(
                                        BattleCoachFocus.controls,
                                        terminal
                                            ? _result()
                                            : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                if (v.rules.pending?.owner ==
                                                        v.viewer &&
                                                    actions.any(
                                                      (a) => a is ResolveAction,
                                                    ))
                                                  BattleKnowledgePreview(
                                                    commandKey: const ValueKey(
                                                      'open-private',
                                                    ),
                                                    knowledge: v.knowledge,
                                                    pending: true,
                                                    onOpen:
                                                        ready
                                                            ? () {
                                                              if (_hotseatInputCurrent(
                                                                hotseatEpoch,
                                                              )) {
                                                                unawaited(
                                                                  _privateChoice(),
                                                                );
                                                              }
                                                            }
                                                            : null,
                                                  )
                                                else if (v
                                                    .knowledge
                                                    .knownUpcomingCards
                                                    .isNotEmpty)
                                                  BattleKnowledgePreview(
                                                    knowledge: v.knowledge,
                                                    pending: false,
                                                    onOpen:
                                                        () => _sheet<void>(
                                                          PrivateKnowledgeSheet(
                                                            knowledge:
                                                                v.knowledge,
                                                          ),
                                                          hotseatEpoch:
                                                              hotseatEpoch,
                                                        ),
                                                  ),
                                                if (v
                                                    .knowledge
                                                    .radarObservations
                                                    .isNotEmpty)
                                                  BattleRadarPreview(
                                                    observation:
                                                        v
                                                            .knowledge
                                                            .radarObservations
                                                            .last,
                                                    onOpen:
                                                        () => _sheet<void>(
                                                          PrivateKnowledgeSheet(
                                                            knowledge:
                                                                v.knowledge,
                                                          ),
                                                          hotseatEpoch:
                                                              hotseatEpoch,
                                                        ),
                                                  ),
                                                if (controller?.error != null ||
                                                    controller
                                                            ?.hasPendingIntent ==
                                                        true)
                                                  BattleCommand(
                                                    label: l.battle(
                                                      BattleCopy.retry,
                                                    ),
                                                    icon: Icons.sync,
                                                    art: 'sync',
                                                    onPressed:
                                                        controller!.busy
                                                            ? null
                                                            : _retry,
                                                  ),
                                                if (selection.card != null)
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          BattleIconControl(
                                                            key: const ValueKey(
                                                              'cancel-card',
                                                            ),
                                                            icon: Icons.close,
                                                            art: 'close',
                                                            label: l.battle(
                                                              BattleCopy.cancel,
                                                            ),
                                                            onPressed:
                                                                ready
                                                                    ? () {
                                                                      if (!_canInteract ||
                                                                          !ready) {
                                                                        return;
                                                                      }
                                                                      setState(
                                                                        selection
                                                                            .cancel,
                                                                      );
                                                                      if (practice ==
                                                                          null) {
                                                                        FirstSessionTelemetry.forStore(
                                                                          GameStore
                                                                              .instance,
                                                                        ).record(
                                                                          FirstSessionEvent
                                                                              .cardCancelled,
                                                                          _ownerRevision,
                                                                          mode:
                                                                              _mode,
                                                                        );
                                                                      }
                                                                    }
                                                                    : null,
                                                          ),
                                                          Expanded(
                                                            child: BattleCommand(
                                                              key:
                                                                  const ValueKey(
                                                                    'play-card',
                                                                  ),
                                                              primary: true,
                                                              label: l.learning(
                                                                'Kartı Oyna',
                                                                'Play Card',
                                                              ),
                                                              icon: Icons.check,
                                                              art: 'confirm',
                                                              onPressed:
                                                                  ready &&
                                                                          selection.play !=
                                                                              null &&
                                                                          (!movementCards.contains(
                                                                                selection.card,
                                                                              ) ||
                                                                              selection.specialDestination !=
                                                                                  null)
                                                                      ? () => _apply(
                                                                        selectedPlay!,
                                                                        hotseatEpoch:
                                                                            hotseatEpoch,
                                                                        boundDestination:
                                                                            selectedDestination,
                                                                      )
                                                                      : null,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          TextButton.icon(
                                                            key: const ValueKey(
                                                              'discard-card',
                                                            ),
                                                            style: TextButton.styleFrom(
                                                              textStyle:
                                                                  BattleTokens
                                                                      .body
                                                                      .copyWith(
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                              minimumSize:
                                                                  const Size(
                                                                    76,
                                                                    48,
                                                                  ),
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        4,
                                                                  ),
                                                              foregroundColor:
                                                                  BattleTokens
                                                                      .secondary,
                                                            ),
                                                            label: Text(
                                                              l.battle(
                                                                BattleCopy
                                                                    .discard,
                                                              ),
                                                            ),
                                                            icon:
                                                                const BattleArt(
                                                                  'discard',
                                                                  size: 18,
                                                                ),
                                                            onPressed:
                                                                ready &&
                                                                        actions.any(
                                                                          (a) =>
                                                                              a
                                                                                  is DiscardAction &&
                                                                              a.card ==
                                                                                  selection.card,
                                                                        )
                                                                    ? () => _apply(
                                                                      DiscardAction(
                                                                        selectedCard!,
                                                                      ),
                                                                      hotseatEpoch:
                                                                          hotseatEpoch,
                                                                    )
                                                                    : null,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  )
                                                else if (actions.any(
                                                  (a) => a is PassAction,
                                                ))
                                                  BattleCommand(
                                                    key: const ValueKey(
                                                      'pass-card',
                                                    ),
                                                    label: l.battle(
                                                      BattleCopy.pass,
                                                    ),
                                                    icon: Icons.skip_next,
                                                    art: 'pass',
                                                    onPressed:
                                                        ready
                                                            ? () => _apply(
                                                              const PassAction(),
                                                              hotseatEpoch:
                                                                  hotseatEpoch,
                                                            )
                                                            : null,
                                                  ),
                                              ],
                                            ),
                                      ),
                            ),
                  ),
                ),
              ),
    );
  }

  Widget _handHeader(PlayerView v) {
    final l = LunoLocalizations.of(context), channel = emotes;
    final hotseatEpoch = _hotseatPrivacy.epoch;
    final dense =
        BattleTokens.sideDock(context) && !BattleTokens.compactText(context);
    final latestEmote = channel?.visible.values.fold<BattleEmoteEvent?>(
      null,
      (latest, e) =>
          latest == null || e.sequence > latest.sequence ? e : latest,
    );
    return Row(
      children: [
        KeyedSubtree(
          key: _drawSource,
          child: SizedBox.square(
            dimension: BattleTokens.shortPortrait(context) ? 48 : 54,
            child: IconButton(
              key: const ValueKey('open-own-deck'),
              tooltip: l.learning(
                'Destem · ${v.rules.deckCounts[v.viewer]} kart sırada',
                'My deck · ${v.rules.deckCounts[v.viewer]} cards remaining',
              ),
              onPressed:
                  () => _sheet<void>(
                    OpponentArsenalSheet(
                      rules: v.rules,
                      opponent: v.viewer,
                      own: true,
                      ownHand: v.ownHand.toSet(),
                    ),
                    hotseatEpoch: hotseatEpoch,
                  ),
              padding: const EdgeInsets.all(2),
              icon: Image.asset(
                'assets/native_art/battle-draw-pile-v208.webp',
                cacheWidth: 144,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dense)
                Text(
                  l.learning(
                    'Deste ${v.rules.deckCounts[v.viewer]} · El ${v.ownHand.length}/4',
                    'Deck ${v.rules.deckCounts[v.viewer]} · Hand ${v.ownHand.length}/4',
                  ),
                  style: BattleTokens.card.copyWith(fontSize: 12),
                )
              else
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 3,
                  children: [
                    Text(
                      l.learning(
                        'Deste ${v.rules.deckCounts[v.viewer]}',
                        'Deck ${v.rules.deckCounts[v.viewer]}',
                      ),
                      style: BattleTokens.card.copyWith(fontSize: 13),
                    ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: BattleTokens.gold,
                    ),
                    Text(
                      l.learning(
                        'Elin · ${v.ownHand.length}/4',
                        'Hand · ${v.ownHand.length}/4',
                      ),
                      style: BattleTokens.card.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              Text(
                l.learning(
                  v.rules.deckCounts[v.viewer] == 0
                      ? 'Desten bitti · Eldeki kartlarını kullan'
                      : v.ownHand.length >= 4
                      ? dense
                          ? 'El dolu · Yer aç'
                          : 'Elin dolu · Yeni kart için yer aç'
                      : dense
                      ? 'Hamleden sonra +1'
                      : '${v.rules.deckCounts[v.viewer]} kart sırada · Hamleden sonra +1',
                  v.rules.deckCounts[v.viewer] == 0
                      ? 'Deck empty · Use your remaining hand'
                      : v.ownHand.length >= 4
                      ? dense
                          ? 'Hand full · Make space'
                          : 'Hand full · Make space for a new card'
                      : dense
                      ? '+1 after your move'
                      : '${v.rules.deckCounts[v.viewer]} remaining · +1 after your move',
                ),
                style: BattleTokens.caption.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        SizedBox.square(
          dimension: 64,
          child: IconButton(
            key: const ValueKey('open-emotes'),
            tooltip: l.learning('İfade gönder', 'Send emote'),
            onPressed: terminal ? null : _emoji,
            icon:
                latestEmote == null
                    ? Image.asset(
                      LunoAssets.matchEmoji,
                      cacheWidth: 96,
                      width: 32,
                      height: 32,
                    )
                    : BattleEmoteBubble(
                      event: latestEmote,
                      compact: true,
                      sender: l.battle(
                        latestEmote.side == v.viewer
                            ? BattleCopy.you
                            : BattleCopy.opponent,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  Widget _practiceHandHeader(PlayerView v) {
    final l = LunoLocalizations.of(context);
    final focusedCard = _focusedLessonCard ? selection.card : null;
    return Row(
      key: const ValueKey('practice-hand-strip'),
      children: [
        BattleMana(
          value: v.rules.mana[v.viewer]!,
          compact: true,
          label: l.battle(BattleCopy.mana),
          previewCost:
              selection.card == null
                  ? null
                  : BattleRulesCore.effectiveCost(
                    v.rules,
                    v.viewer,
                    selection.card!,
                  ),
        ),
        const SizedBox(width: 6),
        SizedBox.square(
          key: focusedCard == null ? _drawSource : _cardSources[focusedCard],
          dimension: 48,
          child: IconButton(
            key: ValueKey(
              focusedCard == null ? 'open-own-deck' : 'practice-selected-card',
            ),
            tooltip:
                focusedCard == null
                    ? l.learning('Destem', 'My deck')
                    : l.battleCardName(focusedCard),
            onPressed:
                focusedCard != null
                    ? () => _detail(focusedCard)
                    : () => _sheet<void>(
                      OpponentArsenalSheet(
                        rules: v.rules,
                        opponent: v.viewer,
                        own: true,
                        ownHand: v.ownHand.toSet(),
                      ),
                    ),
            padding: const EdgeInsets.all(2),
            icon:
                focusedCard == null
                    ? Image.asset(
                      'assets/native_art/battle-draw-pile-v208.webp',
                      cacheWidth: 144,
                    )
                    : BattleCardArt(card: focusedCard),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.learning(
                  'Elin ${v.ownHand.length}/4',
                  'Hand ${v.ownHand.length}/4',
                ),
                style: BattleTokens.card.copyWith(fontSize: 12),
              ),
              Text(
                l.learning(
                  'Deste ${v.rules.deckCounts[v.viewer]}',
                  'Deck ${v.rules.deckCounts[v.viewer]}',
                ),
                style: BattleTokens.caption.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: const ValueKey('open-emotes'),
            tooltip: l.learning('İfade gönder', 'Send emote'),
            onPressed: terminal ? null : _emoji,
            icon: Image.asset(
              LunoAssets.matchEmoji,
              cacheWidth: 96,
              width: 28,
              height: 28,
            ),
          ),
        ),
      ],
    );
  }

  Widget _practiceContinue() {
    final l = LunoLocalizations.of(context);
    return BattleCommand(
      key: const ValueKey('practice-next'),
      label: l.learning(
        practice!.guidedMatch
            ? practice!.complete
                ? 'Temeller tamam, devam et'
                : 'Şimdilik geç'
            : practice!.freePlay
            ? 'Hazırım, oyuna geç'
            : 'Sonraki antrenman',
        practice!.guidedMatch
            ? practice!.complete
                ? 'Basics complete, continue'
                : 'Skip for now'
            : practice!.freePlay
            ? 'Ready, let us play'
            : 'Next practice',
      ),
      icon: Icons.arrow_forward_rounded,
      art: 'confirm',
      primary: true,
      loading: resultBusy,
      onPressed: resultBusy ? null : _completePractice,
    );
  }
}
