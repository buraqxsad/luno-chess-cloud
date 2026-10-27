import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/effects.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_ui/tokens.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'v214_vfx_review_test.dart' as review;
import 'visual_polish_v203_test.dart' show shell;

const frameKey = ValueKey('v215-vfx-frame');
final captured = <Uint8List>[];

Future<void> capture(WidgetTester tester, String name, Widget child) async {
  if (Platform.environment['LUNO_V215_CAPTURE'] != '1') return;
  await tester.pumpWidget(
    shell(
      Center(
        child: RepaintBoundary(
          key: frameKey,
          child: ColoredBox(
            color: const Color(0xff172523),
            child: SizedBox(
              width: 360,
              height: 388,
              child: Column(
                children: [
                  SizedBox(
                    height: 38,
                    child: Center(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  SizedBox.square(dimension: 332, child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(frameKey));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, context);
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(frameKey),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = Uint8List.fromList(data!.buffer.asUint8List());
    captured.add(bytes);
    final dir = Directory('qa/v215/vfx-captures')..createSync(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    image.dispose();
  });
  expect(tester.takeException(), isNull);
}

Future<void> atlases() async {
  for (var start = 0; start < captured.length; start += 8) {
    final recorder = ui.PictureRecorder();
    // A single canvas contains only the already-rendered review frames.
    final actualCanvas = Canvas(recorder);
    for (var i = 0; i < 8 && start + i < captured.length; i++) {
      final codec = await ui.instantiateImageCodec(captured[start + i]);
      final image = (await codec.getNextFrame()).image;
      actualCanvas.drawImage(
        image,
        Offset((i % 4) * 360, (i ~/ 4) * 388),
        Paint(),
      );
      image.dispose();
      codec.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(1440, 776);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      'qa/v215/vfx-captures/atlas-${start ~/ 8 + 1}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    review.fixtures =
        ((jsonDecode(
                      File(
                        '../battle_contract/v1/rules.json',
                      ).readAsStringSync(),
                    )
                    as Map)['fixtures']
                as List)
            .cast<Map>();
    await (FontLoader('Nunito')..addFont(
      rootBundle.load('assets/fonts/nunito/nunito-variable.ttf'),
    )).load();
  });
  tearDownAll(atlases);

  for (final card in CardId.values) {
    testWidgets('V215 current ${card.wire} frame/target review', (
      tester,
    ) async {
      final pair = review.cast(card),
          cue = review.cueFor(card, review.cast(card));
      for (final progress in [.25, .75]) {
        final pixels = await tester.runAsync(
          () => review.pixels(cue, progress),
        );
        expect(
          review.alphaPixels(pixels!),
          greaterThan(progress == .25 ? 40 : 100),
        );
        expect(cue.squares, unorderedEquals(review.expectedTargets[card]!));
        await capture(
          tester,
          '${card.wire}-${(progress * 100).round()}',
          Stack(
            fit: StackFit.expand,
            children: [
              BattleBoard(
                view: pair.after.view(PieceColor.white),
                externalCastAnimation: true,
                onTap: (_) {},
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: CustomPaint(
                  painter: BattleSpellPainter(
                    cue: cue,
                    viewer: PieceColor.white,
                    progress: progress,
                    color: battleAbilityColor(card),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  PlayerView withRules(PlayerView view, RuleDraft rules) =>
      PlayerView(rules.freeze(), view.viewer, view.ownHand, view.knowledge);
  Widget feedback(PlayerView view) => shell(
    Center(
      child: SizedBox.square(
        dimension: 332,
        child: BattleAcceptedFeedback(view: view),
      ),
    ),
  );

  testWidgets(
    'mixed rarities retain independent progress, deadlines and no replay',
    (tester) async {
      var state = review.cast(CardId.boardSeal).before;
      final before = state.view(PieceColor.white);
      state = DeckManager.apply(
        state,
        BattleRulesCore.legalActions(state.view(PieceColor.white))
            .whereType<PlayCardAction>()
            .firstWhere((action) => action.card == CardId.radar),
      );
      state = DeckManager.apply(
        state,
        BattleRulesCore.legalActions(
          state.view(PieceColor.white),
        ).whereType<ChessMoveAction>().first,
      );
      state = DeckManager.apply(state, const PassAction());
      state = DeckManager.apply(
        state,
        BattleRulesCore.legalActions(
          state.view(PieceColor.black),
        ).whereType<ChessMoveAction>().first,
      );
      state = DeckManager.apply(
        state,
        BattleRulesCore.legalActions(state.view(PieceColor.white))
            .whereType<PlayCardAction>()
            .firstWhere((action) => action.card == CardId.boardSeal),
      );
      final after = state.view(PieceColor.white);
      final snapshot = after.toJson();
      await tester.pumpWidget(feedback(before));
      await tester.pumpWidget(feedback(after));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final radar = find.byKey(const ValueKey('spell-radar-1'));
      final seal = find.byKey(const ValueKey('spell-board_seal-0'));
      expect(
        (tester.widget<CustomPaint>(radar).painter! as BattleSpellPainter)
            .progress,
        closeTo(240 / battleEffectDuration(CardId.radar).inMilliseconds, .001),
      );
      expect(
        (tester.widget<CustomPaint>(seal).painter! as BattleSpellPainter)
            .progress,
        closeTo(
          240 / battleEffectDuration(CardId.boardSeal).inMilliseconds,
          .001,
        ),
      );
      await tester.pump(
        Duration(
          milliseconds: battleEffectDuration(CardId.radar).inMilliseconds - 241,
        ),
      );
      expect(radar, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(radar, findsNothing);
      expect(seal, findsOneWidget);
      await tester.pump(
        Duration(
          milliseconds:
              battleEffectDuration(CardId.boardSeal).inMilliseconds -
              battleEffectDuration(CardId.radar).inMilliseconds -
              1,
        ),
      );
      expect(seal, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(seal, findsNothing);
      await tester.pumpWidget(feedback(after));
      await tester.pump(battleEffectDuration(CardId.boardSeal));
      expect(radar, findsNothing);
      expect(seal, findsNothing);
      expect(after.toJson(), snapshot);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'visible empty-square expiry and enemy Mine removal animate publicly',
    (tester) async {
      final before = review
          .cast(CardId.lockedSquare)
          .after
          .view(PieceColor.white);
      final square = before.rules.boardEffects.single.squares.single;
      expect(before.rules.board.pieceAt(square), isNull);
      final after = withRules(
        before,
        RuleDraft(before.rules)..boardEffects.clear(),
      );
      await tester.pumpWidget(feedback(before));
      await tester.pumpWidget(feedback(after));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.byKey(ValueKey('accepted-pulse-$square')), findsOneWidget);
      await tester.pump(
        Duration(milliseconds: battleCleanupDuration.inMilliseconds - 240),
      );
      expect(find.byKey(ValueKey('accepted-pulse-$square')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final enemyDraft = RuleDraft(before.rules)
        ..boardEffects = [
          BoardEffectInstance(
            id: 'public-mine',
            type: BoardEffectType.mine,
            owner: PieceColor.black,
            squares: [square],
            responseSide: PieceColor.white,
            duration: EffectDuration.persistent,
          ),
        ];
      final enemy = withRules(before, enemyDraft);
      await tester.pumpWidget(
        shell(
          SizedBox.square(
            dimension: 40,
            child: BattleFloorEffects(
              rules: enemy.rules,
              viewer: PieceColor.white,
              square: square,
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('effect-public-mine-$square')),
        findsOneWidget,
      );
      await tester.pumpWidget(feedback(enemy));
      await tester.pumpWidget(
        feedback(
          withRules(enemy, RuleDraft(enemy.rules)..boardEffects.clear()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.byKey(ValueKey('accepted-pulse-$square')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in [
    'mine-lock',
    'mine-vow',
    'fog-mine',
    'seal-mine',
    'debuff-selection',
    'check-effects',
    'legal-persistent',
  ]) {
    testWidgets(
      'persistent overlap $kind retains target, piece and action clues',
      (tester) async {
        final base =
            kind == 'check-effects'
                ? DeckManager.newBattle(
                  white: starterDeck,
                  black: starterDeck,
                  board: Board.fromFen(
                    '4k3/1p2r3/8/8/3p4/2P5/PP1N4/R3K2R w KQ - 0 1',
                  ),
                ).view(PieceColor.white)
                : review.cast(CardId.freeze).before.view(PieceColor.white);
        final draft = RuleDraft(base.rules);
        const square = 21;
        BoardEffectInstance effect(
          String id,
          BoardEffectType type,
          List<int> squares,
        ) => BoardEffectInstance(
          id: id,
          type: type,
          owner: PieceColor.white,
          squares: squares,
          responseSide: PieceColor.black,
          duration: EffectDuration.move,
        );
        draft.boardEffects.clear();
        draft.pieceEffects.clear();
        draft.vows.clear();
        if (kind.contains('mine')) {
          draft.boardEffects.add(
            effect('mine', BoardEffectType.mine, [square]),
          );
        }
        if (kind == 'mine-lock' ||
            kind == 'check-effects' ||
            kind == 'legal-persistent') {
          draft.boardEffects.add(
            effect('lock', BoardEffectType.lockedSquare, [square]),
          );
        }
        if (kind == 'fog-mine' || kind == 'seal-mine') {
          draft.boardEffects.add(
            effect(
              'zone',
              kind == 'fog-mine'
                  ? BoardEffectType.fog
                  : BoardEffectType.boardSeal,
              boardZone(20),
            ),
          );
        }
        if (kind == 'mine-vow') {
          draft.vows.add(
            const VowState(
              id: 'watch',
              type: VowType.watch,
              owner: PieceColor.white,
              pieceId: null,
              square: square,
              remainingMoves: 3,
            ),
          );
        }
        final selected = draft.pieceIds.indexWhere(
          (id) =>
              id != null &&
              draft.board.pieceAt(draft.pieceIds.indexOf(id))?.color ==
                  PieceColor.white,
        );
        if (kind == 'debuff-selection') {
          draft.pieceEffects.add(
            ActivePieceEffect(
              id: 'chain',
              type: PieceEffectType.chain,
              owner: PieceColor.black,
              pieceId: draft.pieceIds[selected]!,
              responseSide: PieceColor.white,
              duration: EffectDuration.move,
            ),
          );
        }
        final view = withRules(base, draft);
        final board = BattleBoard(
          view: view,
          selected: selected,
          targets: kind == 'legal-persistent' ? {20, 22} : const {},
          externalCastAnimation: true,
          onTap: (_) {},
        );
        await tester.pumpWidget(
          shell(Center(child: SizedBox.square(dimension: 332, child: board))),
        );
        expect(find.byType(BattleBoard), findsOneWidget);
        for (final e in draft.boardEffects) {
          expect(
            find.byKey(ValueKey('effect-${e.id}-${e.squares.first}')),
            findsOneWidget,
          );
        }
        if (kind == 'mine-vow') {
          expect(find.byKey(const ValueKey('vow-watch')), findsOneWidget);
        }
        if (kind == 'debuff-selection') {
          expect(
            find.byKey(const ValueKey('piece-effect-chain')),
            findsOneWidget,
          );
        }
        if (kind == 'check-effects') {
          expect(MoveGen.inCheck(view.rules.board, PieceColor.white), isTrue);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).border ==
                      Border.all(color: BattleTokens.danger, width: 3),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await capture(tester, 'overlap-$kind', board);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
