import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import '../tool/battle_fixture_support.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'v214_vfx_review_test.dart' as review;

final phase = Platform.environment['LUNO_V216_BATTLE_PHASE'] ?? 'after';
const frameKey = ValueKey('v216-card-stage');
final stageFrames = <Uint8List>[];
final matrix = <Map<String, Object?>>[];

Set<String> markers(RuleState s) => {
  ...s.pieceEffects.map((e) => e.id),
  ...s.boardEffects.map((e) => e.id),
  ...s.vows.map((e) => e.id),
  ...s.modifiers.map((e) => e.id),
};

Future<void> renderStage(WidgetTester tester, CardId card, String stage,
    PlayerView view, {Set<int> targets = const {}, Set<int> preview = const {},
    BattleSpellCue? cue, double progress = 0, bool includeInAtlas = true}) async {
  await tester.pumpWidget(shell(Center(child: RepaintBoundary(
    key: frameKey,
    child: Material(color: const Color(0xff142321), child: SizedBox(
      width: 344, height: 432,
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(6), child: Text(
          '${card.wire} / $stage',
          style: const TextStyle(fontFamily: 'Nunito', color: Colors.white,
              fontSize: 15, fontWeight: FontWeight.w800),
        )),
        SizedBox(height: 54, child: Row(mainAxisAlignment: MainAxisAlignment.center,
          children: [SizedBox.square(dimension: 48, child: BattleCardArt(card: card)),
            const SizedBox(width: 8), Text('${cardDefinitions[card]!.cost} mana',
              style: const TextStyle(fontFamily: 'Nunito', color: Colors.white, fontSize: 14)),
          ])),
        SizedBox.square(dimension: 332, child: Stack(fit: StackFit.expand, children: [
          BattleBoard(view: view, targets: targets, preview: preview,
            externalCastAnimation: true, onTap: (_) {}),
          if (cue != null) Padding(padding: const EdgeInsets.all(6), child: CustomPaint(
            painter: BattleSpellPainter(cue: cue, viewer: view.viewer,
              progress: progress, color: battleAbilityColor(card)),
          )),
        ])),
      ]),
    )),
  )), reduced: true));
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(frameKey));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, context);
    }
  });
  for (final render in tester.allRenderObjects) { render.markNeedsPaint(); }
  await tester.pump();
  await tester.runAsync(() async {
    final image = await tester.renderObject<RenderRepaintBoundary>(
      find.byKey(frameKey)).toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = Uint8List.fromList(data!.buffer.asUint8List());
    if (includeInAtlas) stageFrames.add(bytes);
    final dir = Directory('qa/v216/$phase/battle/stages')..createSync(recursive: true);
    await File('${dir.path}/${card.wire}-$stage.png').writeAsBytes(bytes);
    image.dispose();
  });
  expect(tester.takeException(), isNull, reason: '${card.wire}/$stage');
}

Future<void> atlas() async {
  for (var start = 0; start < stageFrames.length; start += 24) {
    final recorder = ui.PictureRecorder();
    // Composite only the exact Flutter frames saved above.
    final c = Canvas(recorder);
    c.drawColor(const Color(0xff142321), BlendMode.src);
    for (var i = 0; i < 24 && start + i < stageFrames.length; i++) {
      final codec = await ui.instantiateImageCodec(stageFrames[start + i]);
      final image = (await codec.getNextFrame()).image;
      c.drawImageRect(image, Rect.fromLTWH(0, 0, 344, 432),
        Rect.fromLTWH((i % 6) * 236.0, (i ~/ 6) * 296.0, 236, 296), Paint());
      image.dispose(); codec.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(1416, 1184);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('qa/v216/$phase/battle/stages/atlas-${start ~/ 24 + 1}.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose(); picture.dispose();
  }
  await File('qa/v216/$phase/battle/stages/matrix.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(matrix));
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() {
    review.fixtures = ((jsonDecode(File('../battle_contract/v1/rules.json')
        .readAsStringSync()) as Map)['fixtures'] as List).cast<Map>();
  });
  tearDownAll(atlas);
  for (final card in CardId.values) {
    testWidgets('V216 canonical six stages ${card.wire}', (tester) async {
      final fixture = review.fixtures.singleWhere((f) => f['fixtureId'] == 'card-${card.wire}');
      runFixture(fixture);
      final pair = review.cast(card);
      final before = pair.before.view(PieceColor.white), after = pair.after.view(PieceColor.white);
      final snapshot = pair.before.toJson();
      final legal = BattleRulesCore.legalActions(before);
      final action = BattleAction.fromJson((fixture['steps'] as List).first['action'] as Map)
          as PlayCardAction;
      expect(legal.map((a) => a.key), contains(action.key));
      final selected = BattleInteraction()..select(card, legal);
      expect(selected.card, card);
      await renderStage(tester, card, 'SELECT', before,
        targets: selected.targets(before, legal));
      if (action.target is int) {
        selected.tap(action.target as int, before, legal);
      } else if (action.target is String) {
        final squares = selected.targets(before, legal);
        if (squares.isNotEmpty) selected.tap(squares.first, before, legal);
      }
      await renderStage(tester, card, 'TARGET', before,
        targets: selected.targets(before, legal), preview: selected.preview());
      expect(selected.targets(before, legal).every((s) => s >= 0 && s < 64), isTrue);
      expect(selected.preview().every((s) => s >= 0 && s < 64), isTrue);
      final cue = review.cueFor(card, pair);
      expect(cue.squares, unorderedEquals(review.expectedTargets[card]!));
      for (final progress in [.25, .75]) {
        final pixels = await tester.runAsync(() => review.pixels(cue, progress));
        expect(review.alphaPixels(pixels!), greaterThan(0),
          reason: '${card.wire} must have a visible cast/impact');
      }
      await renderStage(tester, card, 'CAST', after, cue: cue, progress: .25);
      await renderStage(tester, card, 'IMPACT', after, cue: cue, progress: .75);
      var active = pair.after;
      ChessMoveAction? specialMove;
      if (active.rules.pending != null) {
        final resolve = BattleRulesCore.legalActions(active.view(PieceColor.white))
            .whereType<ResolveAction>().first;
        active = DeckManager.apply(active, resolve);
      }
      if (active.rules.special case final authorization?) {
        final pieceId = active.rules.pieceIds[authorization.from];
        specialMove = BattleRulesCore.legalActions(active.view(PieceColor.white))
          .whereType<ChessMoveAction>().first;
        final destination = Square.of(specialMove.uci.codeUnitAt(2) - 97,
          int.parse(specialMove.uci[3]) - 1);
        active = DeckManager.apply(active, specialMove);
        expect(active.rules.pieceIds[destination], pieceId);
        expect(active.rules.pieceIds[authorization.from], isNull);
        expect(active.rules.special, isNull);
        expect(active.rules.ply, pair.after.rules.ply + 1);
      }
      await renderStage(tester, card, 'ACTIVE', active.view(PieceColor.white));
      final added = markers(pair.after.rules).difference(markers(pair.before.rules));
      var expired = active, moves = 0;
      if (card != CardId.mine) {
        for (var n = 0; n < 14 && added.intersection(markers(expired.rules)).isNotEmpty; n++) {
          final choices = BattleRulesCore.legalActions(expired.view(expired.rules.board.turn));
          final next = choices.whereType<ResolveAction>().firstOrNull ??
              choices.whereType<PassAction>().firstOrNull ??
              choices.whereType<ChessMoveAction>().firstOrNull;
          if (next == null) break;
          expired = DeckManager.apply(expired, next);
          if (next is ChessMoveAction) moves++;
        }
      }
      await renderStage(tester, card, 'EXPIRY', expired.view(PieceColor.white),
        cue: cue, progress: 1);
      expect(pair.before.toJson(), snapshot);
      expect(review.alphaPixels(await tester.runAsync(() => review.pixels(cue, 1)) ?? Uint8List(0)), 0);
      final remaining = added.intersection(markers(expired.rules));
      if (card != CardId.mine) expect(remaining, isEmpty, reason: '${card.wire} actual expiry');
      if (card == CardId.mine) {
        final triggerFixture = review.fixtures.singleWhere((f) => f['fixtureId'] == 'mine-watch-castle');
        runFixture(triggerFixture);
        final triggerBefore = fixtureInitial(triggerFixture);
        var triggered = DeckManager.apply(triggerBefore, const ChessMoveAction('e1g1'));
        expect(triggered.rules.boardEffects.where((e) => e.type == BoardEffectType.mine), isEmpty);
        expect(triggered.rules.pieceEffects.where((e) => e.type == PieceEffectType.mineDebuff), hasLength(1));
        final triggerCue = BattleSpellCue.fromViews(CardId.mine, PieceColor.black,
          triggerBefore.view(PieceColor.white), triggered.view(PieceColor.white));
        expect(triggerCue.squares, [5]);
        await renderStage(tester, card, 'TRIGGER', triggered.view(PieceColor.white),
          cue: triggerCue, progress: .75, includeInAtlas: false);
        if (triggered.rules.phase == BattlePhase.card) {
          triggered = DeckManager.apply(triggered, const PassAction());
        }
        triggered = DeckManager.apply(triggered, const ChessMoveAction('e8d8'));
        if (triggered.rules.phase == BattlePhase.card) {
          triggered = DeckManager.apply(triggered, const PassAction());
        }
        final rookMove = BattleRulesCore.legalActions(triggered.view(PieceColor.white))
          .whereType<ChessMoveAction>().firstWhere((a) => a.uci.startsWith('f1'));
        triggered = DeckManager.apply(triggered, rookMove);
        expect(triggered.rules.pieceEffects.where((e) => e.type == PieceEffectType.mineDebuff), isEmpty);
        await renderStage(tester, card, 'REMOVAL', triggered.view(PieceColor.white),
          includeInAtlas: false);
      }
      matrix.add({'card': card.wire, 'cost': cardDefinitions[card]!.cost,
        'targetType': cardDefinitions[card]!.target.name,
        'legalTargets': selected.targets(before, legal).toList()..sort(),
        'publicImpact': cue.squares, 'impactMs': battleImpactDelay(card),
        'activeIds': added.toList(), 'expiryMoves': moves,
        'acceptedSpecialMove': specialMove?.uci,
        'triggerFixture': card == CardId.mine ? 'mine-watch-castle' : null,
        'expiry': card == CardId.mine ? 'persistent until enemy arrival/removal' :
            added.isEmpty ? 'transient complete; knowledge/result retained' : 'engine expired',
        'status': 'PASS'});
      await tester.pumpWidget(const SizedBox());
    });
  }
}
