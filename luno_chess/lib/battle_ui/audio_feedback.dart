import 'dart:async';
import 'package:flutter/widgets.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../engine/move_gen.dart';
import '../services/luno_audio_service.dart';
import '../models/app_settings.dart';
import 'feedback.dart';
import 'draw_flow.dart';
import 'effect_timing.dart';
import 'accepted_frames.dart';

typedef BattleSoundCue = ({LunoSound sound, int delayMs});

LunoSound battleImpactSound(CardId card) => switch (card) {
  CardId.radar => LunoSound.cardRadar,
  CardId.prophecy => LunoSound.cardProphecy,
  CardId.shelter => LunoSound.cardShelter,
  CardId.chain => LunoSound.cardChain,
  CardId.slow => LunoSound.cardSlow,
  CardId.pawnDeviation => LunoSound.cardPawnDeviation,
  CardId.pawnAdvance => LunoSound.cardPawnAdvance,
  CardId.lockedSquare => LunoSound.cardLockedSquare,
  CardId.freeze => LunoSound.cardFreeze,
  CardId.purify => LunoSound.cardPurify,
  CardId.mine => LunoSound.cardMine,
  CardId.breakSeal => LunoSound.cardBreakSeal,
  CardId.fog => LunoSound.cardFog,
  CardId.manaSabotage => LunoSound.cardManaSabotage,
  CardId.cardBlock => LunoSound.cardBlock,
  CardId.rookBend => LunoSound.cardRookBend,
  CardId.angryN => LunoSound.cardAngryN,
  CardId.shadowPass => LunoSound.cardShadowPass,
  CardId.huntVow => LunoSound.cardHuntVow,
  CardId.watchVow => LunoSound.cardWatchVow,
  CardId.echo => LunoSound.cardEcho,
  CardId.fateExchange => LunoSound.cardFateExchange,
  CardId.shadowContract => LunoSound.cardShadowContract,
  CardId.boardSeal => LunoSound.cardBoardSeal,
};

List<BattleSoundCue> battleSoundCues(
  PlayerView before,
  PlayerView after, {
  TerminalState? beforeTerminal,
  TerminalState? afterTerminal,
  bool reducedMotion = false,
}) {
  if (before.viewer != after.viewer ||
      after.rules.ply < before.rules.ply ||
      after.rules.effectSequence < before.rules.effectSequence) {
    return const [];
  }
  if ((beforeTerminal ?? before.rules.terminal) != null) return const [];
  final terminal = afterTerminal ?? after.rules.terminal;
  if (terminal != null) {
    final moved = after.rules.ply > before.rules.ply;
    final captured =
        after.rules.pieceIds.whereType<String>().length <
        before.rules.pieceIds.whereType<String>().length;
    return [
      if (moved)
        (sound: captured ? LunoSound.capture : LunoSound.move, delayMs: 0),
      (
        sound:
            terminal.winner == null
                ? LunoSound.draw
                : terminal.winner == after.viewer
                ? LunoSound.victory
                : LunoSound.defeat,
        delayMs: 400,
      ),
    ];
  }
  final casts = acceptedBattleCasts(before, after);
  final discard = PieceColor.values.any(
    (side) => after.rules.discarded[side]!.any(
      (card) => !before.rules.discarded[side]!.contains(card),
    ),
  );
  final arrival =
      BattleDrawTracker()
        ..observe(before, 0)
        ..observe(after, 1);
  final drawn =
      arrival.notice?.kind == BattleArrivalKind.draw &&
      arrival.notice?.opponent == false;
  final exchanged = arrival.notice?.kind == BattleArrivalKind.exchange;
  final moved = after.rules.ply > before.rules.ply;
  final captured =
      after.rules.pieceIds.whereType<String>().length <
      before.rules.pieceIds.whereType<String>().length;
  final mineTriggered = after.rules.pieceEffects.any(
    (effect) =>
        effect.type == PieceEffectType.mineDebuff &&
        !before.rules.pieceEffects.any((old) => old.id == effect.id),
  );
  final check =
      moved &&
      terminal == null &&
      MoveGen.inCheck(after.rules.board, after.rules.board.turn);
  final echoedCast =
      casts
          .where(
            (cast) => before.rules.modifiers.any(
              (modifier) =>
                  modifier.type == ModifierType.echo &&
                  !after.rules.modifiers.any(
                    (next) => next.id == modifier.id,
                  ) &&
                  cast.side == modifier.responseSide &&
                  cast.card == modifier.targetCard,
            ),
          )
          .firstOrNull;
  return [
    if (casts.isNotEmpty && !reducedMotion)
      (sound: LunoSound.cardCast, delayMs: 0),
    for (final cast in casts.take(2))
      (
        sound: battleImpactSound(cast.card),
        delayMs: reducedMotion ? 0 : battleImpactDelay(cast.card),
      ),
    if (discard) (sound: LunoSound.cardDiscard, delayMs: 0),
    if (moved)
      (sound: captured ? LunoSound.capture : LunoSound.move, delayMs: 0),
    if (drawn)
      (
        sound: LunoSound.cardDraw,
        delayMs:
            reducedMotion
                ? 0
                : moved
                ? 160
                : 100,
      ),
    if (exchanged) (sound: LunoSound.cardFateExchange, delayMs: 0),
    if (mineTriggered) (sound: LunoSound.mineTriggered, delayMs: 80),
    if (echoedCast != null)
      (
        sound: LunoSound.cardEcho,
        delayMs: reducedMotion ? 0 : battleImpactDelay(echoedCast.card),
      ),
    for (final payoff in acceptedBattleVowPayoffs(before, after).take(2))
      (
        sound: battleImpactSound(payoff.card),
        delayMs: reducedMotion ? 0 : battleImpactDelay(payoff.card),
      ),
    if (check) (sound: LunoSound.check, delayMs: 120),
  ];
}

class BattleAudioFeedback extends StatefulWidget {
  final PlayerView view;
  final List<BattleAcceptedFrame>? acceptedFrames;
  final TerminalState? terminal;
  final Widget child;
  final int synchronizationEpoch;
  final int? selectedPiece;
  final CardId? selectedCard;
  @visibleForTesting
  final void Function(LunoSound)? play;
  const BattleAudioFeedback({
    super.key,
    required this.view,
    this.acceptedFrames,
    this.terminal,
    required this.child,
    this.synchronizationEpoch = 0,
    this.selectedPiece,
    this.selectedCard,
    this.play,
  });
  @override
  State<BattleAudioFeedback> createState() => _BattleAudioFeedbackState();
}

class _BattleAudioFeedbackState extends State<BattleAudioFeedback>
    with WidgetsBindingObserver {
  final _timers = <Timer>[];
  int _presentationEpoch = 0;
  bool _foreground = true;
  bool? _visible;
  int _lastAcceptedSequence = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LunoSettings.instance.addListener(_settingsChanged);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lastAcceptedSequence = widget.acceptedFrames?.lastOrNull?.sequence ?? 0;
  }

  void _clear() {
    _presentationEpoch++;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _settingsChanged() {
    if (!LunoSettings.instance.soundEnabled) _clear();
  }

  void _hide() {
    _clear();
    if (widget.play == null) LunoAudioService.instance.cancelEffects();
  }

  bool _current(int epoch) =>
      mounted &&
      epoch == _presentationEpoch &&
      _foreground &&
      _visible != false &&
      LunoSettings.instance.soundEnabled;

  void _play(LunoSound sound) {
    final epoch = _presentationEpoch;
    if (!_current(epoch) || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    if (widget.play != null) {
      widget.play!(sound);
    } else {
      unawaited(
        LunoAudioService.instance.playEffect(
          sound,
          isCurrent: () => _current(epoch),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(BattleAudioFeedback old) {
    super.didUpdateWidget(old);
    if (old.synchronizationEpoch != widget.synchronizationEpoch ||
        battleAcceptedHistoryReset(old.acceptedFrames, widget.acceptedFrames) ||
        !_foreground ||
        !LunoSettings.instance.soundEnabled ||
        !TickerMode.valuesOf(context).enabled ||
        old.view.viewer != widget.view.viewer ||
        widget.view.rules.ply < old.view.rules.ply ||
        widget.view.rules.effectSequence < old.view.rules.effectSequence) {
      _hide();
      _lastAcceptedSequence =
          widget.acceptedFrames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
      return;
    }
    _timers.removeWhere((timer) => !timer.isActive);
    if ((old.terminal ?? old.view.rules.terminal) == null &&
        (widget.terminal ?? widget.view.rules.terminal) != null) {
      _hide();
    }
    if ((widget.terminal ?? widget.view.rules.terminal) == null) {
      if (widget.selectedCard != null &&
          old.selectedCard != widget.selectedCard) {
        _play(LunoSound.cardSelect);
      } else if (widget.selectedPiece != null &&
          old.selectedPiece != widget.selectedPiece) {
        _play(LunoSound.pieceSelect);
      }
    }
    final frames = widget.acceptedFrames;
    final newFrames =
        frames
            ?.where((frame) => frame.sequence > _lastAcceptedSequence)
            .toList();
    _lastAcceptedSequence =
        frames?.lastOrNull?.sequence ?? _lastAcceptedSequence;
    final cues =
        frames == null
            ? battleSoundCues(
              old.view,
              widget.view,
              beforeTerminal: old.terminal,
              afterTerminal: widget.terminal,
              reducedMotion: MediaQuery.disableAnimationsOf(context),
            )
            : [
              for (final frame in newFrames!)
                if (frame.before.viewer == widget.view.viewer &&
                    frame.after.viewer == widget.view.viewer)
                  ...battleSoundCues(
                    frame.before,
                    frame.after,
                    reducedMotion: MediaQuery.disableAnimationsOf(context),
                  ),
              if (old.terminal == null &&
                  widget.terminal != null &&
                  widget.view.rules.terminal == null)
                ...battleSoundCues(
                  old.view,
                  widget.view,
                  beforeTerminal: old.terminal,
                  afterTerminal: widget.terminal,
                  reducedMotion: MediaQuery.disableAnimationsOf(context),
                ),
            ];
    for (final cue in cues) {
      if (cue.delayMs == 0) {
        _play(cue.sound);
      } else {
        if (_timers.length >= 12) _timers.removeAt(0).cancel();
        _timers.add(
          Timer(Duration(milliseconds: cue.delayMs), () => _play(cue.sound)),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible == true && !visible) _hide();
    _visible = visible;
    if (MediaQuery.disableAnimationsOf(context)) _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _hide();
  }

  @override
  void dispose() {
    _hide();
    LunoSettings.instance.removeListener(_settingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
