import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'v219_battle_presentation_support.dart';

class _PresentationHarness {
  final scene = GlobalKey(), impact = GlobalKey(), board = GlobalKey();
  final own = GlobalKey(), opponent = GlobalKey();
  final cards = {for (final card in CardId.values) card: GlobalKey()};
  final sounds = <LunoSound>[];

  Widget build(PlayerView view, {int epoch = 0, bool reduced = false}) =>
      v219PresentationShell(
        RepaintBoundary(
          key: scene,
          child: SizedBox.expand(
            child: BattleAudioFeedback(
              view: view,
              synchronizationEpoch: epoch,
              play: sounds.add,
              child: BattleCastStage(
                view: view,
                board: board,
                own: own,
                opponent: opponent,
                cards: cards,
                synchronizationEpoch: epoch,
                child: Stack(
                  children: [
                    Positioned(
                      top: 30,
                      left: 150,
                      child: SizedBox(key: opponent, width: 100, height: 40),
                    ),
                    Positioned(
                      top: 100,
                      left: 34,
                      child: SizedBox.square(
                        key: board,
                        dimension: 332,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Color(0xff142321)),
                            RepaintBoundary(
                              key: impact,
                              child: BattleAcceptedFeedback(
                                view: view,
                                synchronizationEpoch: epoch,
                                showAnnouncements: false,
                                showProjectiles: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 550,
                      left: 150,
                      child: SizedBox(key: own, width: 100, height: 40),
                    ),
                    for (var i = 0; i < view.ownHand.length; i++)
                      Positioned(
                        top: 650,
                        left: i * 100.0,
                        child: SizedBox(
                          key: cards[view.ownHand[i]],
                          width: 80,
                          height: 100,
                          child: BattleCardArt(card: view.ownHand[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        reduced: reduced,
      );
}

Future<void> _warm(WidgetTester tester, _PresentationHarness harness) async {
  await tester.runAsync(() async {
    final context = harness.scene.currentContext!;
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
    await precacheImage(
      const AssetImage('assets/native_art/battle-impact-v209.webp'),
      context,
    );
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
}

Future<Uint8List> _capture(
  WidgetTester tester,
  _PresentationHarness harness,
  String name,
) async {
  final result = await tester.runAsync(() async {
    final directory = Directory('qa/v219/battle-presentation')
      ..createSync(recursive: true);
    final scene = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(harness.scene))
        .toImage(pixelRatio: 1);
    final layer = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(harness.impact))
        .toImage(pixelRatio: 1);
    try {
      final png = await scene.toByteData(format: ui.ImageByteFormat.png);
      final layerPng = await layer.toByteData(format: ui.ImageByteFormat.png);
      final raw = await layer.toByteData(format: ui.ImageByteFormat.rawRgba);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      await File(
        '${directory.path}/$name-impact.png',
      ).writeAsBytes(layerPng!.buffer.asUint8List());
      return Uint8List.fromList(raw!.buffer.asUint8List());
    } finally {
      scene.dispose();
      layer.dispose();
    }
  });
  expect(tester.takeException(), isNull, reason: name);
  return result!;
}

int _alphaPixels(Uint8List pixels, {Offset? center}) {
  var count = 0;
  for (var i = 3; i < pixels.length; i += 4) {
    final x = (i ~/ 4) % 332, y = (i ~/ 4) ~/ 332;
    if (pixels[i] > 8 &&
        (center == null ||
            ((x - center.dx).abs() <= 20 && (y - center.dy).abs() <= 20))) {
      count++;
    }
  }
  return count;
}

void _size(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 760);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadV219PresentationFonts();
    await LunoSettings.instance.load();
  });
  setUp(() async {
    await LunoSettings.instance.setEffectsLevel(3);
  });

  test('V219 external impact keeps the shared arrival and bounded cleanup', () {
    expect(battleCastArrivalFraction, .30);
    expect(battleExternalImpactProgress(0), 0);
    expect(battleExternalImpactProgress(battleCastArrivalFraction), 0);
    expect(battleExternalImpactProgress(.78), greaterThan(.3));
    expect(battleExternalImpactProgress(1), 1);
    expect(battleExternalImpactProgress(2), 1);
    var previous = 0.0;
    for (var i = 0; i <= 100; i++) {
      final progress = battleExternalImpactProgress(i / 100);
      expect(progress, inInclusiveRange(previous, 1));
      previous = progress;
    }
    for (final card in CardId.values) {
      expect(
        battleImpactDelay(card),
        (battleEffectDuration(card).inMilliseconds * battleCastArrivalFraction)
            .round(),
      );
    }
  });

  for (final card in [
    CardId.shelter,
    CardId.freeze,
    CardId.huntVow,
    CardId.boardSeal,
    CardId.mine,
  ]) {
    for (final viewer in PieceColor.values) {
      testWidgets(
        'V219 ${card.wire} ${viewer.name} flight impact audio frames',
        (tester) async {
          _size(tester);
          final harness = _PresentationHarness(), pair = v219Cast(card);
          final before = pair.before.view(viewer),
              after = pair.after.view(viewer);
          final cue = BattleSpellCue.fromViews(
            card,
            PieceColor.white,
            before,
            after,
          );
          expect(cue.squares, isNotEmpty);
          final unchanged = after.toJson();
          final duration = battleEffectDuration(card).inMilliseconds;
          final delay = battleImpactDelay(card);
          final tag = '${card.wire}-${viewer.name}';
          await tester.pumpWidget(harness.build(before));
          await _warm(tester, harness);
          await tester.pumpWidget(harness.build(after));
          await _warm(tester, harness);

          await tester.pump(Duration(milliseconds: delay - 1));
          for (final square in cue.squares) {
            expect(find.byKey(ValueKey('impact-ring-$square')), findsNothing);
          }
          expect(
            _alphaPixels(await _capture(tester, harness, '$tag-before')),
            0,
            reason: 'No impact may precede the external card arrival',
          );
          expect(harness.sounds, [LunoSound.cardCast]);

          await tester.pump(const Duration(milliseconds: 2));
          final flight = find.byKey(ValueKey('card-flight-${card.wire}'));
          final target =
              const Offset(40, 106) +
              cue.squares
                      .map((square) => battleSquareCenter(square, viewer, 40))
                      .reduce((a, b) => a + b) /
                  cue.squares.length.toDouble();
          final center =
              tester.getCenter(flight) -
              tester.getTopLeft(find.byKey(harness.scene));
          expect((center - target).distance, lessThan(.1));
          expect(harness.sounds, [LunoSound.cardCast, battleImpactSound(card)]);
          for (final square in cue.squares) {
            expect(find.byKey(ValueKey('impact-ring-$square')), findsOneWidget);
          }

          await tester.pump(const Duration(milliseconds: 23));
          final impact = await _capture(tester, harness, '$tag-impact');
          expect(_alphaPixels(impact), greaterThan(50));
          for (final square in cue.squares) {
            expect(
              _alphaPixels(
                impact,
                center:
                    const Offset(6, 6) + battleSquareCenter(square, viewer, 40),
              ),
              greaterThan(10),
              reason: 'Real impact pixels must hit square $square',
            );
          }

          await tester.pump(Duration(milliseconds: duration - delay - 24 + 1));
          expect(
            find.byKey(ValueKey('card-flight-${card.wire}')),
            findsNothing,
          );
          expect(
            _alphaPixels(await _capture(tester, harness, '$tag-cleared')),
            0,
          );
          await tester.pumpWidget(harness.build(after));
          await tester.pump(const Duration(seconds: 1));
          expect(harness.sounds, [LunoSound.cardCast, battleImpactSound(card)]);
          expect(
            after.toJson(),
            unchanged,
            reason: 'Presentation cannot mutate accepted state',
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final viewer in PieceColor.values) {
    testWidgets(
      'V219 public Mine delta without cast identity reaches ${viewer.name}',
      (tester) async {
        _size(tester);
        final harness = _PresentationHarness(), pair = v219Cast(CardId.mine);
        final before = pair.before.view(viewer),
            after = pair.after.view(viewer);
        final draft = RuleDraft(after.rules);
        draft.used[PieceColor.white] = List.of(
          before.rules.used[PieceColor.white]!,
        );
        final publicDelta = PlayerView(
          draft.freeze(),
          viewer,
          after.ownHand,
          after.knowledge,
        );
        expect(acceptedBattleCasts(before, publicDelta), isEmpty);
        final squares =
            publicDelta.rules.boardEffects
                .where((effect) => effect.type == BoardEffectType.mine)
                .expand((effect) => effect.squares)
                .toSet();
        expect(squares, isNotEmpty);
        await tester.pumpWidget(harness.build(before));
        await _warm(tester, harness);
        await tester.pumpWidget(harness.build(publicDelta));
        await _warm(tester, harness);
        await tester.pump(
          Duration(milliseconds: battleImpactDelay(CardId.mine) + 24),
        );
        final pixels = await _capture(
          tester,
          harness,
          'mine-public-delta-${viewer.name}',
        );
        for (final square in squares) {
          expect(
            find.byKey(ValueKey('accepted-pulse-$square')),
            findsOneWidget,
          );
          expect(
            _alphaPixels(
              pixels,
              center:
                  const Offset(6, 6) + battleSquareCenter(square, viewer, 40),
            ),
            greaterThan(10),
          );
        }
        expect(
          harness.sounds,
          isEmpty,
          reason: 'Public effect visibility does not invent an accepted cast',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets('V219 captured epoch cleanup reduced=$reduced', (tester) async {
      _size(tester);
      final harness = _PresentationHarness(), pair = v219Cast(CardId.freeze);
      final before = pair.before.view(PieceColor.white);
      final after = pair.after.view(PieceColor.white);
      await tester.pumpWidget(harness.build(before, reduced: reduced));
      await _warm(tester, harness);
      await tester.pumpWidget(harness.build(after, reduced: reduced));
      await _warm(tester, harness);
      if (!reduced) {
        await tester.pump(
          Duration(milliseconds: battleImpactDelay(CardId.freeze) + 24),
        );
        expect(
          _alphaPixels(await _capture(tester, harness, 'epoch-active')),
          greaterThan(50),
        );
      } else {
        expect(harness.sounds, [LunoSound.cardFreeze]);
      }
      await tester.pumpWidget(harness.build(after, epoch: 1, reduced: reduced));
      expect(find.byKey(const ValueKey('card-flight-freeze')), findsNothing);
      expect(
        _alphaPixels(await _capture(tester, harness, 'epoch-cleared-$reduced')),
        0,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        harness.sounds.where((sound) => sound == LunoSound.cardFreeze),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
