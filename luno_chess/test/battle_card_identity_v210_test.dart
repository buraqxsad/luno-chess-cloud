import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/card_motion.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'battle_ui/fixtures.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, shot, noOverflow, visibleTap;
import 'interaction_clarity_v211_test.dart' show makeMove;

int hashBytes(List<int> bytes) {
  var hash = 2166136261;
  for (final value in bytes) {
    hash = ((hash ^ value) * 16777619) & 0xffffffff;
  }
  return hash;
}

void main() {
  setupPracticeTestAssets();
  for (final card in CardId.values) {
    test('${card.wire} has its own bounded PCM sound', () {
      final sound = battleImpactSound(card);
      final asset = LunoAudioService.assetForSound(sound);
      expect(asset, 'audio/spell_${card.wire}.wav');
      final bytes = File('assets/$asset').readAsBytesSync(),
          data = bytes.buffer.asByteData();
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 22050);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      var peak = 0;
      for (var i = 44; i < bytes.length; i += 2) {
        final sample = data.getInt16(i, Endian.little).abs();
        if (sample > peak) peak = sample;
      }
      expect(peak, inInclusiveRange(100, 28000));
      expect(data.getInt16(44, Endian.little), 0);
      expect(
        data.getInt16(bytes.length - 2, Endian.little).abs(),
        lessThan(15),
      );
      expect(bytes.length, inInclusiveRange(20000, 45000));
    });
    testWidgets('${card.wire} accepted cast plays only its own impact once', (
      tester,
    ) async {
      final before = battleFixture().view(PieceColor.white);
      final draft = RuleDraft(before.rules)..used[PieceColor.white]!.add(card);
      final after = PlayerView(
        draft.freeze(),
        before.viewer,
        before.ownHand,
        before.knowledge,
      );
      final sounds = <LunoSound>[];
      Widget stage(PlayerView view) => shell(
        BattleAudioFeedback(
          view: view,
          play: sounds.add,
          child: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpWidget(stage(before));
      await tester.pumpWidget(stage(after));
      expect(sounds, [LunoSound.cardCast]);
      await tester.pump(Duration(milliseconds: battleImpactDelay(card) - 1));
      expect(sounds, [LunoSound.cardCast]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(sounds, [LunoSound.cardCast, battleImpactSound(card)]);
      await tester.pumpWidget(stage(after));
      await tester.pump(const Duration(seconds: 1));
      expect(sounds, [LunoSound.cardCast, battleImpactSound(card)]);
      await tester.pumpWidget(const SizedBox());
      noOverflow(tester);
    });
  }
  test('24 sounds are different files, identities and actual waveforms', () {
    expect(CardId.values.map(battleImpactSound).toSet().length, 24);
    expect(
      CardId.values
          .map(
            (card) => hashBytes(
              File(
                'assets/${LunoAudioService.assetForSound(battleImpactSound(card))}',
              ).readAsBytesSync().skip(44).toList(),
            ),
          )
          .toSet()
          .length,
      24,
    );
  });
  test('shadow pass sound keeps oscillating after its descending sweep', () {
    final bytes = File('assets/audio/spell_shadow_pass.wav').readAsBytesSync();
    final data = bytes.buffer.asByteData();
    var crossings = 0, sum = 0, previous = 0, count = 0;
    for (var i = (22050 * .5).round(); i < (22050 * .75).round(); i++) {
      final sample = data.getInt16(44 + i * 2, Endian.little);
      if (count > 0 && (sample >= 0) != (previous >= 0)) crossings++;
      previous = sample;
      sum += sample;
      count++;
    }
    expect(crossings, greaterThan(70));
    expect((sum / count).abs(), lessThan(200));
  });
  test('24 semantic motion paths are distinct, bounded and return to target', () {
    const from = Offset(50, 610), to = Offset(275, 120);
    final signatures = <String>{};
    for (final card in CardId.values) {
      expect(battleCardFlightPoint(card, from, to, 0), from);
      expect(battleCardFlightPoint(card, from, to, 1), to);
      final signature = <String>[];
      for (var i = 0; i <= 100; i++) {
        final t = i / 100, motion = battleCardMotion(card, t);
        final p = battleCardFlightPoint(card, from, to, t);
        expect(p.dx.isFinite && p.dy.isFinite, isTrue, reason: card.wire);
        expect((p - from).distance, lessThan(650), reason: card.wire);
        expect(motion.scale, inInclusiveRange(.8, 1.3));
        expect(motion.impactX, inInclusiveRange(.7, 1.3));
        expect(motion.impactY, inInclusiveRange(.7, 1.3));
        if (i % 20 == 10) {
          signature.add(
            '${p.dx.toStringAsFixed(3)},${p.dy.toStringAsFixed(3)},'
            '${motion.turn.toStringAsFixed(3)},${motion.impactX.toStringAsFixed(3)}',
          );
        }
      }
      signatures.add(signature.join('|'));
    }
    expect(signatures.length, 24);
  });
  test(
    'purify ignores shield expiry and orphaned or opposing piece effects',
    () {
      final base = battleFixture().view(PieceColor.white),
          draft = RuleDraft(base.rules);
      ActivePieceEffect effect(String id, PieceEffectType type, String piece) =>
          ActivePieceEffect(
            id: id,
            type: type,
            owner: PieceColor.black,
            pieceId: piece,
            responseSide: PieceColor.white,
            duration: EffectDuration.move,
          );
      draft.pieceEffects.addAll([
        effect('actual', PieceEffectType.chain, draft.pieceIds[1]!),
        effect('shield', PieceEffectType.shelter, draft.pieceIds[8]!),
        effect('orphan', PieceEffectType.freeze, 'missing'),
        effect('opposing', PieceEffectType.slow, draft.pieceIds[57]!),
      ]);
      final before = PlayerView(
        draft.freeze(),
        PieceColor.white,
        base.ownHand,
        base.knowledge,
      );
      expect(
        BattleSpellCue.fromViews(
          CardId.purify,
          PieceColor.white,
          before,
          base,
        ).squares,
        [1],
      );
      final moved = RuleDraft(base.rules)..ply = base.rules.ply + 1;
      expect(
        BattleSpellCue.fromViews(
          CardId.purify,
          PieceColor.white,
          before,
          PlayerView(
            moved.freeze(),
            PieceColor.white,
            base.ownHand,
            base.knowledge,
          ),
        ).squares,
        isEmpty,
      );
    },
  );
  test(
    'ambiguous seal expiration does not invent a target or expose a mine',
    () {
      final base = battleFixture().view(PieceColor.white);
      BoardEffectInstance effect(
        String id,
        BoardEffectType type,
        PieceColor owner,
        int square,
      ) => BoardEffectInstance(
        id: id,
        type: type,
        owner: owner,
        squares: [square],
        responseSide: PieceColor.white,
        duration: EffectDuration.card,
      );
      PlayerView before(List<BoardEffectInstance> effects) {
        final draft = RuleDraft(base.rules)..boardEffects.addAll(effects);
        return PlayerView(
          draft.freeze(),
          PieceColor.white,
          base.ownHand,
          base.knowledge,
        );
      }

      final lock = effect(
        'lock',
        BoardEffectType.lockedSquare,
        PieceColor.black,
        26,
      );
      expect(
        BattleSpellCue.fromViews(
          CardId.breakSeal,
          PieceColor.white,
          before([
            lock,
            effect('own', BoardEffectType.fog, PieceColor.white, 27),
          ]),
          base,
        ).squares,
        [26],
      );
      expect(
        BattleSpellCue.fromViews(
          CardId.breakSeal,
          PieceColor.white,
          before([
            lock,
            effect('fog', BoardEffectType.fog, PieceColor.black, 27),
          ]),
          base,
        ).squares,
        isEmpty,
      );
      expect(
        BattleSpellCue.fromViews(
          CardId.breakSeal,
          PieceColor.white,
          before([
            effect('public-mine', BoardEffectType.mine, PieceColor.black, 26),
          ]),
          base,
        ).squares,
        [26],
      );
    },
  );
  testWidgets('prophecy tutorial tells the player to resolve before moving', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: SingleChildScrollView(child: BattleLessonStage(step: 7)),
        ),
        reduced: true,
      ),
    );
    await warm(tester);
    await visibleTap(tester, 'lesson-card-prophecy');
    await visibleTap(tester, 'lesson-play-card');
    expect(
      find.text('Etki uygulandı. Önce kartların sırasını onayla.'),
      findsOneWidget,
    );
    expect(
      find.text('Etki uygulandı. Mana harcandı; şimdi hamleni tamamla.'),
      findsNothing,
    );
    await visibleTap(tester, 'lesson-resolve');
    expect(
      find.text('Bilgi kartı tamamlandı. Sonraki adıma geçebilirsin.'),
      findsOneWidget,
    );
    expect(
      find.text('Şimdi bir taşına, sonra işaretli kareye dokun.'),
      findsNothing,
    );
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'completed tutorial moves do not retain an unfinished instruction',
    (tester) async {
      await tester.pumpWidget(
        shell(
          const Scaffold(
            body: SingleChildScrollView(child: BattleLessonStage(step: 4)),
          ),
          reduced: true,
        ),
      );
      await warm(tester);
      final play = BattleRulesCore.legalActions(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).view,
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.chain);
      await visibleTap(tester, 'square-${play.target}');
      await visibleTap(tester, 'lesson-play-card');
      await makeMove(tester);
      expect(
        find.text('Hamlen tamam. Eğitim adımına devam edebilirsin.'),
        findsOneWidget,
      );
      expect(
        find.text('Etki uygulandı. Mana harcandı; şimdi hamleni tamamla.'),
        findsNothing,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('new hand is readable $size $language at large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = Harness(
          hand: const [
            CardId.shadowContract,
            CardId.manaSabotage,
            CardId.pawnDeviation,
            CardId.fateExchange,
          ],
        );
        await tester.pumpWidget(
          shell(
            BattleV1Screen(
              controllerOverride: h.controller,
              clockOverride: (_) => 300000,
            ),
            language: language,
            scale: 1.8,
            reduced: true,
          ),
        );
        await warm(tester);
        noOverflow(tester);
        final name =
            'v210-hand-${size.width.toInt()}-${size.height.toInt()}-$language';
        await shot(tester, name);
        await tester.runAsync(() async {
          await Directory('qa/v210').create(recursive: true);
          await File('qa/v207/$name.png').copy('qa/v210/$name.png');
        });
        await tester.ensureVisible(
          find.byKey(const ValueKey('hand-shadow_contract')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getBottomRight(
                find.byKey(const ValueKey('hand-shadow_contract')),
              )
              .dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(const ValueKey('pass-card'))).dy,
          ),
        );
        await shot(tester, '$name-scrolled');
        await tester.runAsync(
          () => File(
            'qa/v207/$name-scrolled.png',
          ).copy('qa/v210/$name-scrolled.png'),
        );
        await visibleTap(tester, 'detail-shadow_contract');
        await tester.pumpAndSettle();
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        h.controller.dispose();
      });
    }
  }
  testWidgets(
    'all 24 effects have different geometry and temporal signatures',
    (tester) async {
      final identities = <String>{};
      await tester.runAsync(() async {
        await Directory('qa/v210').create(recursive: true);
        for (final card in CardId.values) {
          final frames = <int>[];
          for (final progress in [.42, .58, .81]) {
            final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
            BattleSpellPainter(
              cue: BattleSpellCue(card, PieceColor.white, [27]),
              viewer: PieceColor.white,
              progress: progress,
              color: Colors.white,
              showProjectile: false,
            ).paint(canvas, const Size(384, 384));
            final picture = recorder.endRecording(),
                image = await picture.toImage(384, 384);
            final rgba =
                (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List();
            expect(
              rgba.whereIndexedAlphaCount(),
              greaterThan(250),
              reason: card.wire,
            );
            frames.add(hashBytes(rgba));
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              'qa/v210/effect-${card.wire}-${(progress * 100).round()}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
          }
          expect(frames.toSet().length, 3, reason: card.wire);
          identities.add(frames.join(','));
        }
      });
      expect(identities.length, 24);
    },
  );
  testWidgets('current battle hand screenshot and smooth motion capture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = Harness(
      hand: const [
        CardId.freeze,
        CardId.radar,
        CardId.shelter,
        CardId.pawnAdvance,
      ],
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
    await shot(tester, 'v210-hand-ready');
    await tester.runAsync(
      () => File(
        'qa/v207/v210-hand-ready.png',
      ).copy('qa/v210/v210-hand-ready.png'),
    );
    await visibleTap(tester, 'hand-freeze');
    await visibleTap(tester, 'square-57');
    await visibleTap(tester, 'play-card');
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if ((i + 1) * 50 ==
          ((battleImpactDelay(CardId.freeze) / 50).ceil() * 50)) {
        final flight = find.byKey(const ValueKey('card-flight-freeze'));
        final transform = tester.widget<Transform>(
          find.descendant(of: flight, matching: find.byType(Transform)).first,
        );
        final cell =
            (tester.getSize(find.byType(BattleBoard)).shortestSide - 12) / 8;
        expect(
          76 * transform.transform.storage[5].abs(),
          lessThanOrEqualTo(cell),
        );
        expect(
          58 * transform.transform.storage[0].abs(),
          lessThanOrEqualTo(cell),
        );
      }
      final name = 'v210-motion-${i.toString().padLeft(2, '0')}';
      await shot(tester, name);
      noOverflow(tester);
      await tester.runAsync(
        () => File('qa/v207/$name.png').copy('qa/v210/$name.png'),
      );
    }
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });
}

extension on Uint8List {
  int whereIndexedAlphaCount() {
    var count = 0;
    for (var i = 3; i < length; i += 4) {
      if (this[i] > 0) count++;
    }
    return count;
  }
}
