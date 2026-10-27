import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/introduction.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'battle_ui/fixtures.dart';

void main() {
  for (final reason in ['resign', 'timeout']) {
    test('$reason outside chess core still emits one result cue', () {
      final view = battleFixture().view(PieceColor.white);
      final terminal = TerminalState(reason, winner: PieceColor.black);
      expect(battleSoundCues(view, view, afterTerminal: terminal), [
        (sound: LunoSound.defeat, delayMs: 400),
      ]);
      expect(
        battleSoundCues(
          view,
          view,
          beforeTerminal: terminal,
          afterTerminal: terminal,
        ),
        isEmpty,
      );
    });
  }
  for (final card in CardId.values) {
    test('${card.wire} readable presentation has synchronized impact', () {
      final duration = battleEffectDuration(card).inMilliseconds;
      expect(duration, inInclusiveRange(1400, 2200));
      expect(
        battleEffectTiming(card).impact.inMilliseconds,
        greaterThanOrEqualTo(700),
      );
      expect(
        battleImpactDelay(card),
        (duration * battleCastArrivalFraction).round(),
      );
    });
  }
  for (final card in [CardId.prophecy, CardId.fateExchange]) {
    test('${card.wire} resolution is not a normal draw', () {
      var state = battleFixture(hand: [card, CardId.shelter, CardId.chain]);
      final play = BattleRulesCore.legalActions(
        state.view(PieceColor.white),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
      state = DeckManager.apply(state, play);
      final before = state.view(PieceColor.white);
      final resolve =
          BattleRulesCore.legalActions(before).whereType<ResolveAction>().first;
      state = DeckManager.apply(state, resolve);
      final cues = battleSoundCues(before, state.view(PieceColor.white));
      expect(cues.where((c) => c.sound == LunoSound.cardDraw), isEmpty);
      expect(cues.where((c) => c.sound == LunoSound.cardCast), isEmpty);
      expect(
        cues.map((c) => c.sound),
        card == CardId.fateExchange ? [LunoSound.cardFateExchange] : isEmpty,
      );
    });
  }
  test('Mine placement and real activation are different events', () {
    final lesson = BattleIntroduction(
      checkpoint: IntroductionStage.opponent.index,
    );
    final before = lesson.view;
    expect(lesson.continueLesson(), isTrue);
    final cues = battleSoundCues(before, lesson.view);
    expect(cues, contains((sound: LunoSound.mineTriggered, delayMs: 80)));
    expect(cues.where((c) => c.sound == LunoSound.cardMine), isEmpty);
    expect(battleSoundCues(lesson.view, lesson.view), isEmpty);
  });
  test('real chess check has an audible warning without result fanfare', () {
    var state = DeckManager.newBattle();
    for (final uci in ['e2e4', 'd7d6', 'f1b5']) {
      final before = state.view(PieceColor.white);
      if (state.rules.phase == BattlePhase.card) {
        state = DeckManager.apply(state, const PassAction());
      }
      state = DeckManager.apply(state, ChessMoveAction(uci));
      if (uci == 'f1b5') {
        final cues = battleSoundCues(before, state.view(PieceColor.white));
        expect(cues, contains((sound: LunoSound.check, delayMs: 120)));
        expect(
          cues.where(
            (c) => c.sound == LunoSound.victory || c.sound == LunoSound.defeat,
          ),
          isEmpty,
        );
      }
    }
  });
  for (final reason in ['stalemate', 'repetition', 'agreement']) {
    test('$reason uses a neutral result cue exactly once', () {
      final before = battleFixture().view(PieceColor.white);
      final draft =
          RuleDraft(before.rules)
            ..phase = BattlePhase.terminal
            ..terminal = TerminalState(reason);
      final after = PlayerView(
        draft.freeze(),
        before.viewer,
        before.ownHand,
        before.knowledge,
      );
      expect(battleSoundCues(before, after), [
        (sound: LunoSound.draw, delayMs: 400),
      ]);
      expect(battleSoundCues(after, after), isEmpty);
    });
  }
  for (final sound in [
    LunoSound.check,
    LunoSound.draw,
    LunoSound.mineTriggered,
  ]) {
    test('${sound.name} PCM is finite, distinct and not clipped', () {
      final bytes =
          File(
            'assets/${LunoAudioService.assetForSound(sound)}',
          ).readAsBytesSync();
      final data = bytes.buffer.asByteData();
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      var peak = 0;
      for (var i = 44; i < bytes.length; i += 2) {
        final value = data.getInt16(i, Endian.little).abs();
        if (value > peak) peak = value;
      }
      expect(peak, inInclusiveRange(100, 28000));
      expect(
        data.getInt16(bytes.length - 2, Endian.little).abs(),
        lessThan(15),
      );
      expect(bytes.length, lessThan(30000));
    });
  }
}
