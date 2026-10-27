import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart'
    show renderBattle, expectNoBattleLayoutError;
import 'helpers/battle_v1_response.dart';

const _departure = ValueKey('hand-discard-departure');
const _arrival = ValueKey('hand-arrival-position');

Widget _hand(
  AuthoritativeBattleState state, {
  List<BattleAcceptedFrame>? frames,
  int epoch = 0,
}) => shell(
  Scaffold(
    body: Center(
      child: SizedBox(
        width: 390,
        child: BattleHand(
          view: state.view(PieceColor.white),
          acceptedFrames: frames,
          synchronizationEpoch: epoch,
          enabled: true,
          cost: (_) => 2,
          selectable: (_) => true,
          onSelect: (_) {},
          onDetail: (_) {},
        ),
      ),
    ),
  ),
);

void main() {
  setupPracticeTestAssets();

  test(
    'V232 history reset distinguishes replacement from normal retention',
    () {
      final state = battleFixture().view(PieceColor.white);
      BattleAcceptedFrame frame(int sequence) =>
          BattleAcceptedFrame(sequence, state, state);
      expect(battleAcceptedHistoryReset(null, null), isFalse);
      expect(battleAcceptedHistoryReset(null, const []), isFalse);
      expect(battleAcceptedHistoryReset(const [], [frame(1)]), isFalse);
      expect(battleAcceptedHistoryReset([frame(1)], [frame(1)]), isFalse);
      expect(
        battleAcceptedHistoryReset([frame(1), frame(2)], [frame(2), frame(3)]),
        isFalse,
      );
      expect(battleAcceptedHistoryReset([frame(2)], const []), isTrue);
      expect(battleAcceptedHistoryReset([frame(2)], [frame(1)]), isTrue);
    },
  );

  for (final synchronization in [true, false]) {
    testWidgets(
      'V232 historical discard is not replayed on ${synchronization ? 'reconnect' : 'skipped versions'}',
      (tester) async {
        var state = battleFixture();
        var version = 0;
        final controller = await renderBattle(
          tester,
          state: state,
          reducedMotion: false,
          requestOverride:
              (_, _) async => v1Response(state: state, version: version),
        );
        state = DeckManager.apply(state, const DiscardAction(CardId.chain));
        version = synchronization ? 1 : 3;
        final expected = state.toJson();
        await controller.reconnect(synchronization: synchronization);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          find.byKey(_departure),
          findsNothing,
          reason: 'A new baseline is not a newly accepted discard',
        );
        expect(state.toJson(), expected);
        expectNoBattleLayoutError(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('V232 reconnect cancels an in-flight discard without replay', (
    tester,
  ) async {
    var state = battleFixture();
    var version = 0;
    final controller = await renderBattle(
      tester,
      state: state,
      reducedMotion: false,
      requestOverride: (path, payload) async {
        if (path == '/submitBattleV1Action') {
          state = DeckManager.apply(
            state,
            BattleAction.fromJson(payload['intent'] as Map),
          );
          version++;
        }
        return v1Response(state: state, version: version);
      },
    );
    expect(await controller.submit(const DiscardAction(CardId.chain)), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(_departure), findsOneWidget);
    await controller.reconnect();
    await tester.pump();
    expect(find.byKey(_departure), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(_departure), findsNothing);
    expectNoBattleLayoutError(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V232 a skipped-version baseline clears an existing departure', (
    tester,
  ) async {
    var state = battleFixture();
    var version = 0;
    final controller = await renderBattle(
      tester,
      state: state,
      reducedMotion: false,
      requestOverride: (path, payload) async {
        if (path == '/submitBattleV1Action') {
          state = DeckManager.apply(
            state,
            BattleAction.fromJson(payload['intent'] as Map),
          );
          version++;
        }
        return v1Response(state: state, version: version);
      },
    );
    expect(await controller.submit(const DiscardAction(CardId.chain)), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(_departure), findsOneWidget);
    version += 3;
    await controller.reconnect(synchronization: false);
    await tester.pump();
    expect(find.byKey(_departure), findsNothing);
    expectNoBattleLayoutError(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V232 retained accepted history does not play on initial mount', (
    tester,
  ) async {
    final before = battleFixture();
    final after = DeckManager.apply(before, const DiscardAction(CardId.chain));
    final frames = [
      BattleAcceptedFrame(
        1,
        before.view(PieceColor.white),
        after.view(PieceColor.white),
      ),
    ];
    await tester.pumpWidget(_hand(after, frames: frames));
    await tester.pumpWidget(_hand(after, frames: frames));
    expect(find.byKey(_departure), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'V232 accepted discard survives a batched chess move and is consumed once',
    (tester) async {
      final before = battleFixture();
      final discarded = DeckManager.apply(
        before,
        const DiscardAction(CardId.chain),
      );
      final moved = DeckManager.apply(discarded, const ChessMoveAction('e2e4'));
      final frames = [
        BattleAcceptedFrame(
          1,
          before.view(PieceColor.white),
          discarded.view(PieceColor.white),
        ),
        BattleAcceptedFrame(
          2,
          discarded.view(PieceColor.white),
          moved.view(PieceColor.white),
        ),
      ];
      await tester.pumpWidget(_hand(before, frames: const []));
      await tester.pumpWidget(_hand(moved, frames: frames));
      expect(find.byKey(_departure), findsOneWidget);
      final overlay = tester.widget<IgnorePointer>(find.byKey(_departure));
      expect(overlay.ignoring, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(_hand(moved, frames: frames));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        find.byKey(_departure),
        findsNothing,
        reason: 'Duplicate events cannot restart animation',
      );
      expectNoBattleLayoutError(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('V232 new accepted discard works after a synchronized baseline', (
    tester,
  ) async {
    final before = battleFixture();
    final after = DeckManager.apply(before, const DiscardAction(CardId.chain));
    await tester.pumpWidget(_hand(before, frames: const [], epoch: 0));
    await tester.pumpWidget(_hand(before, frames: const [], epoch: 1));
    await tester.pumpWidget(
      _hand(
        after,
        frames: [
          BattleAcceptedFrame(
            1,
            before.view(PieceColor.white),
            after.view(PieceColor.white),
          ),
        ],
        epoch: 1,
      ),
    );
    expect(find.byKey(_departure), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_departure), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'V232 skipped history cancels cast, board effect and announcement together',
    (tester) async {
      var state = battleFixture();
      var version = 0;
      final controller = await renderBattle(
        tester,
        state: state,
        reducedMotion: false,
        requestOverride: (path, payload) async {
          if (path == '/submitBattleV1Action') {
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(payload['intent'] as Map),
            );
            version++;
          }
          return v1Response(state: state, version: version);
        },
      );
      expect(
        await controller.submit(
          const PlayCardAction(CardId.shelter, target: 8),
        ),
        isTrue,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('card-flight-shelter')), findsOneWidget);
      expect(find.byKey(const ValueKey('spell-shelter-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('cast-notice-shelter')), findsOneWidget);
      version += 3;
      final accepted = state.toJson();
      await controller.reconnect(synchronization: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('card-flight-shelter')), findsNothing);
      expect(find.byKey(const ValueKey('spell-shelter-0')), findsNothing);
      expect(find.byKey(const ValueKey('cast-notice-shelter')), findsNothing);
      expect(
        state.toJson(),
        accepted,
        reason: 'Only transient feedback is cancelled, not the shield',
      );
      expect(state.rules.pieceEffects, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('V232 discarded accepted history cancels pending impact audio', (
    tester,
  ) async {
    final before = battleFixture();
    final after = DeckManager.apply(
      before,
      const PlayCardAction(CardId.shelter, target: 8),
    );
    final sounds = <LunoSound>[];
    Widget stage(
      AuthoritativeBattleState state,
      List<BattleAcceptedFrame> frames,
    ) => shell(
      BattleAudioFeedback(
        view: state.view(PieceColor.white),
        acceptedFrames: frames,
        play: sounds.add,
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(stage(before, const []));
    await tester.pumpWidget(
      stage(after, [
        BattleAcceptedFrame(
          1,
          before.view(PieceColor.white),
          after.view(PieceColor.white),
        ),
      ]),
    );
    expect(sounds, [LunoSound.cardCast]);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(stage(after, const []));
    await tester.pump(
      Duration(milliseconds: battleImpactDelay(CardId.shelter) + 20),
    );
    expect(sounds, [LunoSound.cardCast]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final origin in [
    const Offset(double.nan, 30),
    const Offset(30, double.infinity),
    const Offset(double.negativeInfinity, 30),
  ]) {
    testWidgets(
      'V232 invalid arrival origin settles to finite visible card $origin',
      (tester) async {
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: Center(
                child: SizedBox(
                  width: 90,
                  height: 150,
                  child: BattleCardArrival(
                    card: CardId.radar,
                    trigger: 1,
                    absoluteOrigin: origin,
                    child: const ColoredBox(color: Colors.cyan),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final transform =
            tester.widget<Transform>(find.byKey(_arrival)).transform;
        expect(transform.storage.every((value) => value.isFinite), isTrue);
        expect(transform.storage[12], closeTo(0, .001));
        expect(transform.storage[13], closeTo(0, .001));
        expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('V232 finite arrival still works after invalid origin recovery', (
    tester,
  ) async {
    Widget stage(Offset origin, int trigger) => shell(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 90,
            height: 150,
            child: BattleCardArrival(
              card: CardId.radar,
              trigger: trigger,
              absoluteOrigin: origin,
              child: const ColoredBox(color: Colors.cyan),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(stage(const Offset(double.nan, 30), 1));
    await tester.pump();
    await tester.pumpWidget(stage(const Offset(20, 20), 2));
    await tester.pump();
    final transform = tester.widget<Transform>(find.byKey(_arrival)).transform;
    expect(transform.storage.every((value) => value.isFinite), isTrue);
    expect(find.byKey(const ValueKey('draw-source-radar')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
    expect(
      tester.widget<Transform>(find.byKey(_arrival)).transform.storage[12],
      closeTo(0, .001),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
