import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'helpers/v222_card_scenarios.dart';

void main() {
  for (final card in CardId.values) {
    for (final side in PieceColor.values) {
      test(
        '${card.wire}/${side.name}: cast survives a combined cast/resolve/move build',
        () {
          final initial = cardScenario(card, side);
          final tracker =
              BattlePresentationTracker()..observe(initial.view(side), 0);
          var state = initial;
          var version = 0;
          final play = BattleRulesCore.legalActions(state.view(side))
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          state = DeckManager.apply(state, play);
          final acceptedCast = state;
          tracker.observe(state.view(side), ++version);
          if (state.rules.pending != null) {
            state = DeckManager.apply(
              state,
              BattleRulesCore.legalActions(
                state.view(side),
              ).whereType<ResolveAction>().first,
            );
            tracker.observe(state.view(side), ++version);
          }
          state = DeckManager.apply(
            state,
            BattleRulesCore.legalActions(
              state.view(side),
            ).whereType<ChessMoveAction>().first,
          );
          tracker.observe(state.view(side), ++version);
          expect(tracker.frames, hasLength(version));
          final first = tracker.frames.first;
          expect(first.before.rules.fen, initial.rules.fen);
          expect(first.after.rules.toJson(), acceptedCast.rules.toJson());
          expect(acceptedBattleCasts(first.before, first.after), [
            (card: card, side: side),
          ]);
          expect(
            acceptedBattleCasts(
              tracker.frames.last.before,
              tracker.frames.last.after,
            ),
            isEmpty,
          );
          expect(
            battleSoundCues(
              first.before,
              first.after,
            ).where((cue) => cue.sound == battleImpactSound(card)),
            hasLength(1),
          );
          expect(tracker.frames.last.after.rules.board.turn, side.opposite);
        },
      );
    }
  }

  test(
    'synchronization, skipped versions, viewer change and reset do not replay casts',
    () {
      final initial = cardScenario(CardId.shelter, PieceColor.white);
      final cast = DeckManager.apply(
        initial,
        BattleRulesCore.legalActions(initial.view(PieceColor.white))
            .whereType<PlayCardAction>()
            .firstWhere((a) => a.card == CardId.shelter),
      );
      final tracker =
          BattlePresentationTracker()
            ..observe(initial.view(PieceColor.white), 0);
      tracker.observe(cast.view(PieceColor.white), 1);
      expect(tracker.frames, hasLength(1));
      final sequence = tracker.frames.single.sequence;
      tracker.observe(cast.view(PieceColor.white), 1);
      expect(tracker.frames.single.sequence, sequence);
      tracker.observe(cast.view(PieceColor.white), 3);
      expect(tracker.frames, isEmpty);
      tracker.observe(initial.view(PieceColor.white), 0, epoch: 1);
      tracker.observe(cast.view(PieceColor.white), 1, epoch: 1);
      expect(tracker.frames.single.sequence, greaterThan(sequence));
      tracker.observe(cast.view(PieceColor.black), 1, epoch: 1);
      expect(tracker.frames, isEmpty);
      tracker.reset();
      tracker.observe(cast.view(PieceColor.black), 9, epoch: 2);
      expect(tracker.frames, isEmpty);
      expect(
        () => tracker.frames.add(
          BattleAcceptedFrame(
            1,
            initial.view(PieceColor.white),
            cast.view(PieceColor.white),
          ),
        ),
        throwsUnsupportedError,
      );
    },
  );

  for (final viewer in PieceColor.values) {
    testWidgets(
      '${viewer.name}: three accepted casts in one build keep the latest card flight',
      (tester) async {
        const hand = [CardId.radar, CardId.mine, CardId.shelter];
        final deck = [
          ...hand,
          ...CardId.values.where((card) => !hand.contains(card)).take(7),
        ];
        final initial = DeckManager.newBattle(white: deck, black: deck);
        final draft =
            RuleDraft(initial.rules)
              ..phase = BattlePhase.card
              ..ownTurns = {PieceColor.white: 2, PieceColor.black: 2}
              ..mana = {PieceColor.white: 6, PieceColor.black: 6}
              ..repetitions = {};
        var state = AuthoritativeBattleState(draft.freeze(), initial.hidden);
        final tracker =
            BattlePresentationTracker()..observe(state.view(viewer), 0);
        var version = 0;
        final board = GlobalKey(), own = GlobalKey(), opponent = GlobalKey();
        final sounds = <LunoSound>[];
        Widget stage() => MaterialApp(
          home: Scaffold(
            body: BattleAudioFeedback(
              view: state.view(viewer),
              acceptedFrames: tracker.frames,
              play: sounds.add,
              child: BattleCastStage(
                view: state.view(viewer),
                acceptedFrames: tracker.frames,
                board: board,
                own: own,
                opponent: opponent,
                cards: const {},
                child: Column(
                  children: [
                    SizedBox(key: opponent, width: 100, height: 40),
                    SizedBox(
                      key: board,
                      width: 320,
                      height: 320,
                      child: BattleAcceptedFeedback(
                        view: state.view(viewer),
                        acceptedFrames: tracker.frames,
                        showProjectiles: false,
                      ),
                    ),
                    BattleCastNotice(
                      view: state.view(viewer),
                      acceptedFrames: tracker.frames,
                      child: const Text('next-action'),
                    ),
                    SizedBox(key: own, width: 100, height: 40),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(stage());
        await tester.pump();
        for (final action in <BattleAction>[
          const PlayCardAction(CardId.radar, target: 'mine'),
          const ChessMoveAction('e2e4'),
          const PlayCardAction(CardId.radar, target: 'shelter'),
          const ChessMoveAction('e7e5'),
          const PlayCardAction(CardId.mine, target: 26),
        ]) {
          state = DeckManager.apply(state, action);
          tracker.observe(state.view(viewer), ++version);
        }
        expect(tracker.frames, hasLength(5));
        expect(
          [
            for (final frame in tracker.frames)
              ...acceptedBattleCasts(
                frame.before,
                frame.after,
              ).map((c) => c.card),
          ],
          [CardId.radar, CardId.radar, CardId.mine],
        );
        await tester.pumpWidget(stage());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final flights = find.byWidgetPredicate(
          (widget) =>
              widget is Positioned &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'card-flight-',
              ),
        );
        expect(flights, findsNWidgets(3));
        expect(find.byKey(const ValueKey('card-flight-mine')), findsOneWidget);
        expect(find.byKey(const ValueKey('spell-radar-0')), findsNWidgets(2));
        expect(find.byKey(const ValueKey('spell-mine-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('cast-notice-mine')), findsOneWidget);
        expect(
          sounds.where((sound) => sound == LunoSound.cardCast),
          hasLength(3),
        );
        await tester.pumpWidget(stage());
        await tester.pump(const Duration(milliseconds: 50));
        expect(flights, findsNWidgets(3), reason: 'No duplicate replay');
        expect(
          sounds.where((sound) => sound == LunoSound.cardCast),
          hasLength(3),
        );
        for (final action in <BattleAction>[
          const ChessMoveAction('g1f3'),
          const PlayCardAction(CardId.mine, target: 27),
        ]) {
          state = DeckManager.apply(state, action);
          tracker.observe(state.view(viewer), ++version);
        }
        await tester.pumpWidget(stage());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          flights,
          findsNWidgets(3),
          reason: 'Live flights remain bounded',
        );
        expect(find.byKey(const ValueKey('card-flight-radar')), findsNothing);
        expect(
          find.byKey(const ValueKey('card-flight-radar-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('card-flight-mine-2')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('spell-radar-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('spell-mine-0')), findsNWidgets(2));
        expect(
          sounds.where((sound) => sound == LunoSound.cardCast),
          hasLength(4),
        );
        await tester.pump(const Duration(seconds: 3));
        expect(flights, findsNothing);
        expect(
          sounds.where((sound) => sound == LunoSound.cardRadar),
          hasLength(2),
        );
        expect(
          sounds.where((sound) => sound == LunoSound.cardMine),
          hasLength(2),
        );
        final played = List<LunoSound>.of(sounds);
        await tester.pumpWidget(stage());
        await tester.pump(const Duration(seconds: 1));
        expect(
          sounds,
          played,
          reason: 'Duplicate projection cannot replay audio',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final card in [CardId.purify, CardId.breakSeal]) {
    for (final side in PieceColor.values) {
      testWidgets(
        '${card.wire}/${side.name}: combined notifications retain exact board target and one audio cue',
        (tester) async {
          var state = cardScenario(card, side);
          final initial = state;
          final tracker =
              BattlePresentationTracker()..observe(state.view(side), 0);
          final board = GlobalKey(), own = GlobalKey(), opponent = GlobalKey();
          final sounds = <LunoSound>[];
          Widget stage() => MaterialApp(
            home: Scaffold(
              body: BattleAudioFeedback(
                view: state.view(side),
                acceptedFrames: tracker.frames,
                play: sounds.add,
                child: BattleCastStage(
                  view: state.view(side),
                  acceptedFrames: tracker.frames,
                  board: board,
                  own: own,
                  opponent: opponent,
                  cards: const {},
                  child: Column(
                    children: [
                      SizedBox(key: opponent, width: 100, height: 40),
                      SizedBox(
                        key: board,
                        width: 320,
                        height: 320,
                        child: BattleAcceptedFeedback(
                          view: state.view(side),
                          acceptedFrames: tracker.frames,
                        ),
                      ),
                      SizedBox(key: own, width: 100, height: 40),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(stage());
          await tester.pump();
          final play = BattleRulesCore.legalActions(state.view(side))
              .whereType<PlayCardAction>()
              .firstWhere((action) => action.card == card);
          state = DeckManager.apply(state, play);
          final cast = state;
          tracker.observe(state.view(side), 1);
          state = DeckManager.apply(
            state,
            BattleRulesCore.legalActions(
              state.view(side),
            ).whereType<ChessMoveAction>().first,
          );
          tracker.observe(state.view(side), 2);
          // A single aggregated delta cannot safely distinguish a removed target
          // from expired effects. The exact accepted cast delta can.
          expect(
            BattleSpellCue.fromViews(
              card,
              side,
              initial.view(side),
              state.view(side),
            ).squares,
            isEmpty,
          );
          final expected =
              BattleSpellCue.fromViews(
                card,
                side,
                initial.view(side),
                cast.view(side),
              ).following(state.rules).squares;
          expect(expected, isNotEmpty);
          await tester.pumpWidget(stage());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900));
          final painters =
              tester
                  .widgetList<CustomPaint>(find.byType(CustomPaint))
                  .map((paint) => paint.painter)
                  .whereType<BattleSpellPainter>()
                  .where((painter) => painter.cue.card == card)
                  .toList();
          expect(painters, isNotEmpty);
          expect(painters.first.cue.squares, expected);
          expect(
            sounds.where((sound) => sound == battleImpactSound(card)),
            hasLength(1),
          );
          await tester.pumpWidget(stage());
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            sounds.where((sound) => sound == battleImpactSound(card)),
            hasLength(1),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
