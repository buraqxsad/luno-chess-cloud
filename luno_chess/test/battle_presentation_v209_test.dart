import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/mentor.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'battle_ui/fixtures.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, shot, noOverflow, visibleTap;

AuthoritativeBattleState castFreeze(AuthoritativeBattleState state) =>
    DeckManager.apply(
      state,
      BattleRulesCore.legalActions(
        state.view(PieceColor.white),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.freeze),
    );

void main() {
  setupPracticeTestAssets();
  test('cast trajectory starts and ends at real positions', () {
    const from = Offset(34, 640), to = Offset(220, 180);
    expect(battleCastPoint(from, to, 0), from);
    expect(battleCastPoint(from, to, 1), to);
    expect(battleCastPoint(from, to, .5).dy, lessThan((from.dy + to.dy) / 2));
  });
  test('accepted card sound is ordered and refreshes remain silent', () {
    final before = battleFixture(
      hand: const [CardId.freeze, CardId.radar, CardId.shelter],
    );
    final after = castFreeze(before);
    final cues = battleSoundCues(
      before.view(PieceColor.white),
      after.view(PieceColor.white),
    );
    expect(cues, contains((sound: LunoSound.cardCast, delayMs: 0)));
    expect(
      cues,
      contains((
        sound: LunoSound.cardFreeze,
        delayMs: battleImpactDelay(CardId.freeze),
      )),
    );
    expect(
      battleSoundCues(
        after.view(PieceColor.white),
        after.view(PieceColor.white),
      ),
      isEmpty,
    );
    expect(
      battleSoundCues(
        after.view(PieceColor.white),
        before.view(PieceColor.white),
      ),
      isEmpty,
    );
    expect(
      battleSoundCues(
        before.view(PieceColor.white),
        after.view(PieceColor.black),
      ),
      isEmpty,
    );
    for (final card in CardId.values) {
      expect(battleImpactSound(card), isNot(LunoSound.uiClick));
    }
  });
  test(
    'legal move draws a card, while opponent draws stay private and silent',
    () {
      var state = DeckManager.newBattle();
      final before = state.view(PieceColor.white);
      state = DeckManager.apply(state, const ChessMoveAction('e2e4'));
      final cues = battleSoundCues(before, state.view(PieceColor.white));
      expect(cues, contains((sound: LunoSound.move, delayMs: 0)));
      expect(cues, contains((sound: LunoSound.cardDraw, delayMs: 160)));
      final next = DeckManager.apply(state, const ChessMoveAction('e7e5'));
      expect(
        battleSoundCues(
          state.view(PieceColor.white),
          next.view(PieceColor.white),
        ).where((cue) => cue.sound == LunoSound.cardDraw),
        isEmpty,
      );
    },
  );
  test('discard has its own sound without a fake cast or mana cue', () {
    final state = battleFixture();
    final after = DeckManager.apply(
      state,
      DiscardAction(state.hidden.hands[PieceColor.white]!.first),
    );
    expect(
      battleSoundCues(
        state.view(PieceColor.white),
        after.view(PieceColor.white),
      ),
      [(sound: LunoSound.cardDiscard, delayMs: 0)],
    );
  });
  test('scene leases survive old practice screen disposal', () async {
    final audio = LunoAudioService.instance;
    await audio.setScene(LunoMusicScene.menu);
    final first = audio.holdScene(LunoMusicScene.battle);
    final second = audio.holdScene(LunoMusicScene.battle);
    audio.releaseScene(first);
    expect(audio.effectiveScene, LunoMusicScene.battle);
    audio.releaseScene(second);
    expect(audio.effectiveScene, LunoMusicScene.menu);
    audio.releaseScene(second);
    expect(audio.effectiveScene, LunoMusicScene.menu);
  });
  for (final name in [
    'card_draw',
    'card_cast',
    'card_discard',
    'card_frost',
    'card_shield',
    'card_arcane',
    'card_strike',
    'lesson_complete',
  ]) {
    test('short $name audio is packaged PCM without clipping', () {
      final bytes = File('assets/audio/$name.wav').readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
      final data = bytes.buffer.asByteData();
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 22050);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      var peak = 0;
      for (var i = 44; i < bytes.length; i += 2) {
        final value = data.getInt16(i, Endian.little).abs();
        if (value > peak) peak = value;
      }
      expect(peak, inInclusiveRange(100, 28000));
      expect(data.getInt16(44, Endian.little), 0);
      expect(bytes.length, lessThan(45000));
    });
  }
  testWidgets('pending impact cancels on background and disposal', (
    tester,
  ) async {
    final before = battleFixture(
      hand: const [CardId.freeze, CardId.radar, CardId.shelter],
    );
    final after = castFreeze(before), sounds = <LunoSound>[];
    Widget stage(PlayerView view) => shell(
      BattleAudioFeedback(
        view: view,
        play: sounds.add,
        child: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpWidget(stage(before.view(PieceColor.white)));
    expect(sounds, isEmpty);
    await tester.pumpWidget(stage(after.view(PieceColor.white)));
    expect(sounds, [LunoSound.cardCast]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, [LunoSound.cardCast]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(stage(after.view(PieceColor.white)));
    expect(sounds, [LunoSound.cardCast]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('synchronization silences history without remounting the child', (
    tester,
  ) async {
    final before = battleFixture(
      hand: const [CardId.freeze, CardId.radar, CardId.shelter],
    );
    final after = castFreeze(before), sounds = <LunoSound>[];
    final childKey = GlobalKey();
    Widget stage(PlayerView view, int epoch) => shell(
      BattleAudioFeedback(
        view: view,
        synchronizationEpoch: epoch,
        play: sounds.add,
        child: Scaffold(key: childKey, body: const SizedBox()),
      ),
    );
    await tester.pumpWidget(stage(before.view(PieceColor.white), 0));
    final childState = childKey.currentState;
    await tester.pumpWidget(stage(after.view(PieceColor.white), 1));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, isEmpty);
    expect(childKey.currentState, same(childState));
    await tester.pumpWidget(stage(after.view(PieceColor.white), 1));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('synchronization cancels an already pending impact', (
    tester,
  ) async {
    final before = battleFixture(
      hand: const [CardId.freeze, CardId.radar, CardId.shelter],
    );
    final after = castFreeze(before), sounds = <LunoSound>[];
    Widget stage(PlayerView view, int epoch) => shell(
      BattleAudioFeedback(
        view: view,
        synchronizationEpoch: epoch,
        play: sounds.add,
        child: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpWidget(stage(before.view(PieceColor.white), 0));
    await tester.pumpWidget(stage(after.view(PieceColor.white), 0));
    expect(sounds, [LunoSound.cardCast]);
    await tester.pumpWidget(stage(after.view(PieceColor.white), 1));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds, [LunoSound.cardCast]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'card notice reports effective cost even after mana regeneration',
    (tester) async {
      final before = battleFixture(
        hand: const [CardId.freeze, CardId.radar, CardId.shelter],
      );
      final cast = castFreeze(before);
      final draft = RuleDraft(cast.rules)..mana[PieceColor.white] = 3;
      final after = AuthoritativeBattleState(draft.freeze(), cast.hidden);
      Widget stage(PlayerView view) => shell(
        Scaffold(
          body: BattleCastNotice(view: view, child: const Text('phase')),
        ),
      );
      await tester.pumpWidget(stage(before.view(PieceColor.white)));
      await tester.pumpWidget(stage(after.view(PieceColor.white)));
      await tester.pumpAndSettle();
      expect(find.text('Sen · 4 mana'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'all 24 native effect signatures render distinct nonblank pixels',
    (tester) async {
      final hashes = <int>{};
      await tester.runAsync(() async {
        await Directory('qa/v209').create(recursive: true);
        for (final card in CardId.values) {
          final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
          BattleSpellPainter(
            cue: BattleSpellCue(card, PieceColor.white, [27]),
            viewer: PieceColor.white,
            progress: .55,
            color: battleAbilityColor(card),
            showProjectile: false,
          ).paint(canvas, const Size(384, 384));
          final picture = recorder.endRecording(),
              image = await picture.toImage(384, 384);
          final rgba =
              (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
          var painted = 0, hash = 2166136261;
          for (var i = 0; i < rgba.length; i++) {
            hash = ((hash ^ rgba[i]) * 16777619) & 0xffffffff;
            if (i % 4 == 3 && rgba[i] > 0) painted++;
          }
          expect(painted, greaterThan(250), reason: card.wire);
          hashes.add(hash);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'qa/v209/ability-${card.wire}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        }
      });
      expect(hashes.length, CardId.values.length);
    },
  );
  testWidgets('delayed turn updates do not invent a precise mana cost', (
    tester,
  ) async {
    final before = battleFixture(
      hand: const [CardId.freeze, CardId.radar, CardId.shelter],
    );
    final cast = castFreeze(before);
    final draft = RuleDraft(cast.rules)
      ..ownTurns[PieceColor.white] =
          before.rules.ownTurns[PieceColor.white]! + 1;
    final after = AuthoritativeBattleState(draft.freeze(), cast.hidden);
    Widget stage(PlayerView view) => shell(
      Scaffold(body: BattleCastNotice(view: view, child: const Text('phase'))),
    );
    await tester.pumpWidget(stage(before.view(PieceColor.white)));
    await tester.pumpWidget(stage(after.view(PieceColor.white)));
    await tester.pumpAndSettle();
    expect(find.text('Sen · Etki uygulandı'), findsOneWidget);
    expect(find.text('Sen · 4 mana'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cast starts at the scrolled hand and lands on the real square', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = battleFixture(
      hand: const [CardId.radar, CardId.freeze, CardId.shelter],
    );
    final after = castFreeze(before);
    final board = GlobalKey(), own = GlobalKey(), opponent = GlobalKey();
    final cards = {
      for (final card in before.view(PieceColor.white).ownHand)
        card: GlobalKey(),
    };
    final scroll = ScrollController();
    Widget stage(PlayerView view, {int epoch = 0}) => shell(
      Scaffold(
        body: BattleCastStage(
          view: view,
          synchronizationEpoch: epoch,
          board: board,
          own: own,
          opponent: opponent,
          cards: cards,
          child: Stack(
            children: [
              Positioned(
                left: 50,
                top: 100,
                width: 300,
                height: 300,
                child: ColoredBox(key: board, color: Colors.black),
              ),
              Positioned(
                left: 150,
                top: 20,
                width: 100,
                height: 40,
                child: SizedBox(key: opponent),
              ),
              Positioned(
                left: 150,
                top: 440,
                width: 100,
                height: 40,
                child: SizedBox(key: own),
              ),
              Positioned(
                left: 90,
                top: 540,
                width: 170,
                height: 100,
                child: SingleChildScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final card in view.ownHand)
                        SizedBox(key: cards[card], width: 100, height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(stage(before.view(PieceColor.white)));
    await tester.pump();
    scroll.jumpTo(90);
    await tester.pump();
    final source = tester.getCenter(find.byKey(cards[CardId.freeze]!));
    final boardOrigin =
        tester.getTopLeft(find.byKey(board)) + const Offset(6, 6);
    final cue = BattleSpellCue.fromViews(
      CardId.freeze,
      PieceColor.white,
      before.view(PieceColor.white),
      after.view(PieceColor.white),
    );
    final target =
        boardOrigin +
        cue.squares
                .map((s) => battleSquareCenter(s, PieceColor.white, 36))
                .reduce((a, b) => a + b) /
            cue.squares.length.toDouble();
    await tester.pumpWidget(stage(after.view(PieceColor.white)));
    await tester.pump();
    final flight = find.byKey(const ValueKey('card-flight-freeze'));
    expect((tester.getCenter(flight) - source).distance, lessThan(.01));
    await tester.pump(Duration(milliseconds: battleImpactDelay(CardId.freeze)));
    expect((tester.getCenter(flight) - target).distance, lessThan(.01));
    final childState = own.currentContext;
    await tester.pumpWidget(stage(after.view(PieceColor.white), epoch: 1));
    await tester.pump();
    expect(flight, findsNothing);
    expect(own.currentContext, same(childState));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
  testWidgets('mentor motion is finite and stops when backgrounded', (
    tester,
  ) async {
    Widget mentor(Object cue, {bool reduced = false}) => shell(
      Scaffold(
        body: BattleMentor(
          cue: cue,
          child: const ColoredBox(color: Colors.cyan),
        ),
      ),
      reduced: reduced,
    );
    await tester.pumpWidget(mentor('first'));
    await tester.pump(const Duration(milliseconds: 250));
    final transform = find.descendant(
      of: find.byType(BattleMentor),
      matching: find.byType(Transform),
    );
    expect(tester.widget<Transform>(transform).transform.entry(0, 2), isNot(0));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(mentor('next'));
    await tester.pump(const Duration(milliseconds: 250));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.widget<Transform>(transform).transform.entry(0, 2), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(mentor('next', reduced: true));
    // The shell's rebuilt Material theme has its own finite transition.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(tester.widget<Transform>(transform).transform.entry(0, 2), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(768, 1024),
  ]) {
    testWidgets(
      'accepted card flight is measured, finite and readable at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = Harness(
          hand: const [CardId.freeze, CardId.shelter, CardId.radar],
        );
        await tester.pumpWidget(
          shell(
            BattleV1Screen(
              controllerOverride: h.controller,
              clockOverride: (_) => 300000,
            ),
          ),
        );
        await warm(tester);
        await visibleTap(tester, 'hand-freeze');
        await visibleTap(tester, 'square-57');
        await visibleTap(tester, 'play-card');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 280));
        expect(
          find.byKey(const ValueKey('card-flight-freeze')),
          findsOneWidget,
        );
        noOverflow(tester);
        await shot(
          tester,
          'v209-flight-${size.width.toInt()}-${size.height.toInt()}',
        );
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
        await h.controller.reconnect();
        await tester.pump();
        expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        h.controller.dispose();
      },
    );
  }
  testWidgets('reduced motion does not launch a perspective cast', (
    tester,
  ) async {
    final h = Harness(
      hand: const [CardId.freeze, CardId.shelter, CardId.radar],
    );
    await tester.pumpWidget(
      shell(
        BattleV1Screen(
          controllerOverride: h.controller,
          clockOverride: (_) => 300000,
        ),
        reduced: true,
      ),
    );
    await warm(tester);
    await visibleTap(tester, 'hand-freeze');
    await visibleTap(tester, 'square-57');
    await visibleTap(tester, 'play-card');
    await tester.pump();
    expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
    expect(find.text('Dondurma'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });
  testWidgets(
    'tutorial has all 24 unique detailed cards and four real practices',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 9)),
          ),
          reduced: true,
        ),
      );
      await warm(tester);
      await visibleTap(tester, 'lesson-card-library');
      await tester.pumpAndSettle();
      for (final card in CardId.values) {
        expect(
          find.byKey(ValueKey('lesson-library-${card.wire}')),
          findsOneWidget,
        );
      }
      await visibleTap(tester, 'lesson-library-freeze');
      await tester.pumpAndSettle();
      expect(
        find.text(
          const LunoLocalizations(Locale('tr')).battleCardDetail(CardId.freeze),
        ),
        findsWidgets,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final language in ['tr', 'en']) {
    testWidgets('final lesson remains readable at large text $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      GameStore.instance.tutorialStep = 9;
      await tester.pumpWidget(
        shell(
          const TutorialScreen(onboarding: true),
          scale: 1.8,
          language: language,
          reduced: true,
        ),
      );
      await warm(tester);
      noOverflow(tester);
      await shot(tester, 'v209-tutorial-final-$language');
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('actual native cast sequence capture for motion review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = Harness(
      hand: const [CardId.freeze, CardId.shelter, CardId.radar],
    );
    await tester.pumpWidget(
      shell(
        BattleV1Screen(
          controllerOverride: h.controller,
          clockOverride: (_) => 300000,
        ),
      ),
    );
    await warm(tester);
    await visibleTap(tester, 'hand-freeze');
    await visibleTap(tester, 'square-57');
    await visibleTap(tester, 'play-card');
    await tester.pump();
    for (var i = 0; i < 28; i++) {
      await tester.pump(const Duration(milliseconds: 140));
      final name = 'v209-motion-${i.toString().padLeft(2, '0')}';
      await shot(tester, name);
      noOverflow(tester);
      await tester.runAsync(
        () => File('qa/v207/$name.png').copy('qa/v209/$name.png'),
      );
    }
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });
}
