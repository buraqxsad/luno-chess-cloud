import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import '../tool/battle_fixture_support.dart';
import 'visual_polish_v203_test.dart' show shell;

const captureKey = ValueKey('v214-spell-frame');
const expectedTargets = <CardId, List<int>>{
  CardId.radar: [],
  CardId.prophecy: [],
  CardId.shelter: [0],
  CardId.chain: [27],
  CardId.slow: [52],
  CardId.pawnDeviation: [18],
  CardId.pawnAdvance: [8],
  CardId.lockedSquare: [21],
  CardId.freeze: [52],
  CardId.purify: [0],
  CardId.mine: [21],
  CardId.breakSeal: [20],
  CardId.fog: [20, 21, 28, 29],
  CardId.manaSabotage: [],
  CardId.cardBlock: [],
  CardId.rookBend: [7],
  CardId.angryN: [11],
  CardId.shadowPass: [0],
  CardId.huntVow: [52],
  CardId.watchVow: [21],
  CardId.echo: [],
  CardId.fateExchange: [],
  CardId.shadowContract: [],
  CardId.boardSeal: [20, 21, 28, 29],
};

late List<Map> fixtures;

({AuthoritativeBattleState before, AuthoritativeBattleState after}) cast(
  CardId card, {
  bool publicSeal = true,
}) {
  final fixture = fixtures.singleWhere(
    (f) => f['fixtureId'] == 'card-${card.wire}',
  );
  var before = fixtureInitial(fixture);
  // Keep the locked-square visual variant; test the canonical public Mine below.
  if (card == CardId.breakSeal && publicSeal) {
    final draft = RuleDraft(before.rules);
    final old = draft.boardEffects.single;
    draft.boardEffects = [
      BoardEffectInstance(
        id: old.id,
        type: BoardEffectType.lockedSquare,
        squares: old.squares,
        owner: old.owner,
        responseSide: old.responseSide,
        duration: EffectDuration.move,
      ),
    ];
    before = AuthoritativeBattleState(draft.freeze(), before.hidden);
  }
  final action = BattleAction.fromJson(
    ((fixture['steps'] as List).first as Map)['action'] as Map,
  );
  return (before: before, after: DeckManager.apply(before, action));
}

BattleSpellCue cueFor(
  CardId card,
  ({AuthoritativeBattleState before, AuthoritativeBattleState after}) pair, {
  PieceColor viewer = PieceColor.white,
}) => BattleSpellCue.fromViews(
  card,
  PieceColor.white,
  pair.before.view(viewer),
  pair.after.view(viewer),
);

Future<Uint8List> pixels(
  BattleSpellCue cue,
  double progress, {
  PieceColor viewer = PieceColor.white,
  bool projectile = true,
}) async {
  final recorder = ui.PictureRecorder();
  BattleSpellPainter(
    cue: cue,
    viewer: viewer,
    progress: progress,
    color: battleAbilityColor(cue.card),
    showProjectile: projectile,
  ).paint(Canvas(recorder), const Size(320, 320));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 320);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

int alphaPixels(Uint8List bytes, {bool? top}) {
  var count = 0;
  for (var i = 3; i < bytes.length; i += 4) {
    final y = (i ~/ 4) ~/ 320;
    if ((top == null || (y < 160) == top) && bytes[i] > 8) count++;
  }
  return count;
}

int squarePixels(Uint8List bytes, Offset center) {
  var count = 0;
  for (var y = (center.dy - 20).toInt(); y < center.dy + 20; y++) {
    for (var x = (center.dx - 20).toInt(); x < center.dx + 20; x++) {
      if (x >= 0 &&
          x < 320 &&
          y >= 0 &&
          y < 320 &&
          bytes[(y * 320 + x) * 4 + 3] > 8) {
        count++;
      }
    }
  }
  return count;
}

Future<void> capture(
  WidgetTester tester,
  CardId card,
  PlayerView view,
  BattleSpellCue cue,
  double progress, {
  String? tag,
}) async {
  if (Platform.environment['LUNO_V214_VFX_CAPTURE'] != '1') return;
  await tester.pumpWidget(
    shell(
      Center(
        child: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: const Color(0xff172523),
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    '${tag ?? card.wire} / ${(progress * 100).round()}%',
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${battleEffectDuration(card).inMilliseconds} ms / '
                    '${cardDefinitions[card]!.target.name}',
                    style: const TextStyle(
                      color: Color(0xffbdd1cb),
                      fontSize: 13,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'OPPONENT RESOURCE EDGE',
                      style: TextStyle(color: Color(0xffbdd1cb), fontSize: 12),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 332,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BattleBoard(
                          view: view,
                          externalCastAnimation: true,
                          onTap: (_) {},
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: CustomPaint(
                            painter: BattleSpellPainter(
                              cue: cue,
                              viewer: view.viewer,
                              progress: progress,
                              color: battleAbilityColor(card),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'CASTER RESOURCE EDGE',
                      style: TextStyle(color: Color(0xffbdd1cb), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(captureKey));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, context);
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(captureKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('qa/v214/vfx-captures');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/${tag ?? card.wire}-${(progress * 100).round()}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    fixtures =
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

  test(
    'all 24 timings reserve readable impact and arrival precedes completion',
    () {
      expect(expectedTargets.keys.toSet(), CardId.values.toSet());
      for (final card in CardId.values) {
        final ms = battleEffectTiming(card).milliseconds;
        expect(ms, inInclusiveRange(1400, 2200));
        expect(
          battleEffectTiming(card).impact.inMilliseconds,
          greaterThanOrEqualTo(700),
        );
        expect(battleEffectDuration(card), Duration(milliseconds: ms));
        expect(
          battleImpactDelay(card),
          (ms * battleCastArrivalFraction).round(),
        );
        expect(battleImpactDelay(card), lessThan(ms));
      }
    },
  );

  test(
    'painter is transparent at both lifecycle boundaries for all cards',
    () async {
      final startLeaks = <String>[];
      for (final card in CardId.values) {
        final cue = cueFor(card, cast(card));
        for (final p in [-.2, 0.0, double.nan, double.negativeInfinity]) {
          if (alphaPixels(await pixels(cue, p)) > 0) {
            startLeaks.add('${card.wire}:$p');
          }
        }
        for (final p in [1.0, 1.2, double.infinity]) {
          expect(
            alphaPixels(await pixels(cue, p)),
            0,
            reason: '${card.wire}:$p',
          );
        }
      }
      expect(
        startLeaks,
        isEmpty,
        reason: 'Zero envelope must not paint a projectile head',
      );
    },
  );

  final signatures = <int>{};
  for (final card in CardId.values) {
    test('canonical ${card.wire} cue uses the correct public target', () {
      final pair = cast(card);
      final before = pair.before.toJson(), after = pair.after.toJson();
      final cue = cueFor(card, pair);
      expect(cue.squares, unorderedEquals(expectedTargets[card]!));
      expect(pair.before.toJson(), before);
      expect(pair.after.toJson(), after);
      expect(() => cue.squares.add(31), throwsUnsupportedError);
    });

    testWidgets('render ${card.wire} at 25 and 75 percent with distinct motion', (
      tester,
    ) async {
      final pair = cast(card), cue = cueFor(card, cast(card));
      final early = await tester.runAsync(() => pixels(cue, .25));
      final late = await tester.runAsync(() => pixels(cue, .75));
      // Resource-to-resource flights can be only one cell long. Check a real
      // projectile footprint, then require a substantially larger impact.
      expect(alphaPixels(early!), greaterThan(40));
      expect(alphaPixels(late!), greaterThan(100));
      expect(late, isNot(early));
      var hash = 0;
      for (final byte in late) {
        hash = (hash * 31 + byte) & 0x7fffffff;
      }
      expect(
        signatures.add(hash),
        isTrue,
        reason: '${card.wire} impact must be distinctive',
      );
      // The cast stage owns the projectile when this switch is off: an empty
      // early spell layer is intentional, but the impact layer must still appear.
      final externalEarly = await tester.runAsync(
        () => pixels(cue, .25, projectile: false),
      );
      final externalLate = await tester.runAsync(
        () => pixels(cue, .75, projectile: false),
      );
      expect(alphaPixels(externalEarly!), 0);
      expect(alphaPixels(externalLate!), greaterThan(100));
      await capture(tester, card, pair.after.view(PieceColor.white), cue, .25);
      await capture(tester, card, pair.after.view(PieceColor.white), cue, .75);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'accepted ${card.wire} has measured progress and exact bounded expiry',
      (tester) async {
        final pair = cast(card);
        final before = pair.before.view(PieceColor.white),
            after = pair.after.view(PieceColor.white);
        final snapshot = pair.after.toJson();
        Widget feedback(PlayerView view) => shell(
          Center(
            child: SizedBox.square(
              dimension: 332,
              child: BattleAcceptedFeedback(view: view),
            ),
          ),
        );
        final effect = find.byKey(ValueKey('spell-${card.wire}-0'));
        await tester.pumpWidget(feedback(before));
        expect(effect, findsNothing);
        await tester.pumpWidget(feedback(after));
        expect(effect, findsOneWidget);
        await tester.pump();
        final ms = battleEffectDuration(card).inMilliseconds;
        await tester.pump(Duration(milliseconds: ms ~/ 4));
        final early =
            tester.widget<CustomPaint>(effect).painter! as BattleSpellPainter;
        expect(early.progress, closeTo(.25, .002));
        expect(early.cue.squares, unorderedEquals(expectedTargets[card]!));
        await tester.pump(Duration(milliseconds: ms ~/ 2));
        final late =
            tester.widget<CustomPaint>(effect).painter! as BattleSpellPainter;
        expect(late.progress, closeTo(.75, .002));
        expect(battleSpellEnvelope(late.progress), 1);
        await tester.pump(Duration(milliseconds: ms ~/ 4 - 1));
        expect(effect, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(effect, findsNothing);
        await tester.pumpWidget(feedback(after));
        await tester.pump(Duration(milliseconds: ms));
        expect(
          effect,
          findsNothing,
          reason: 'Identical snapshot must not replay',
        );
        expect(pair.after.toJson(), snapshot);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'echo cast targets opponent resources but payoff targets caster resources',
    () async {
      final cue = cueFor(CardId.echo, cast(CardId.echo));
      for (final viewer in PieceColor.values) {
        final opponentOnTop = viewer == PieceColor.white;
        final casting = await pixels(cue, .75, viewer: viewer);
        expect(alphaPixels(casting, top: opponentOnTop), greaterThan(100));
        expect(alphaPixels(casting, top: !opponentOnTop), 0);
        final reward = await pixels(
          BattleSpellCue(CardId.echo, PieceColor.white, []),
          .75,
          viewer: viewer,
        );
        expect(alphaPixels(reward, top: !opponentOnTop), greaterThan(100));
        expect(alphaPixels(reward, top: opponentOnTop), 0);
      }
    },
  );

  test(
    'all public resource channels remain correct for both board orientations',
    () async {
      for (final card in [
        CardId.radar,
        CardId.manaSabotage,
        CardId.cardBlock,
        CardId.echo,
        CardId.prophecy,
        CardId.fateExchange,
        CardId.shadowContract,
      ]) {
        final cue = cueFor(card, cast(card));
        final toOpponent =
            cardDefinitions[card]!.target == CardTargetType.opponentCard;
        for (final viewer in PieceColor.values) {
          final top = toOpponent == (viewer == PieceColor.white);
          final frame = await pixels(cue, .75, viewer: viewer);
          expect(
            alphaPixels(frame, top: top),
            greaterThan(100),
            reason: '${card.wire}/$viewer',
          );
          expect(
            alphaPixels(frame, top: !top),
            0,
            reason: '${card.wire}/$viewer',
          );
        }
      }
    },
  );

  test(
    'every visible targeted square has an aligned impact in both orientations',
    () async {
      for (final card in CardId.values) {
        final pair = cast(card);
        for (final viewer in PieceColor.values) {
          final cue = cueFor(card, pair, viewer: viewer);
          final frame = await pixels(
            cue,
            .75,
            viewer: viewer,
            projectile: false,
          );
          for (final square in cue.squares) {
            expect(
              squarePixels(frame, battleSquareCenter(square, viewer, 40)),
              greaterThan(40),
              reason: '${card.wire}/$viewer must mark canonical square $square',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'actual Echo trigger returns to its owner and shares the longest bounded duration',
    (tester) async {
      final pair = cast(CardId.echo);
      var state = DeckManager.apply(
        pair.after,
        BattleRulesCore.legalActions(
          pair.after.view(PieceColor.white),
        ).whereType<ChessMoveAction>().first,
      );
      final before = state;
      final radar = BattleRulesCore.legalActions(
        state.view(PieceColor.black),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.radar);
      state = DeckManager.apply(state, radar);
      expect(
        state.rules.modifiers.where((m) => m.type == ModifierType.echo),
        isEmpty,
      );
      expect(
        state.rules.mana[PieceColor.white],
        (before.rules.mana[PieceColor.white]! + 2).clamp(0, 6),
      );
      Widget feedback(AuthoritativeBattleState s) => shell(
        Center(
          child: SizedBox.square(
            dimension: 332,
            child: BattleAcceptedFeedback(view: s.view(PieceColor.white)),
          ),
        ),
      );
      await tester.pumpWidget(feedback(before));
      await tester.pumpWidget(feedback(state));
      final effect = find.byKey(const ValueKey('spell-echo-1'));
      expect(effect, findsOneWidget);
      await tester.pump();
      await tester.pump(
        Duration(
          milliseconds:
              (battleEffectDuration(CardId.echo).inMilliseconds * .75).round(),
        ),
      );
      final painter =
          tester.widget<CustomPaint>(effect).painter! as BattleSpellPainter;
      expect(painter.progress, closeTo(.75, .001));
      expect(painter.cue.side, PieceColor.white);
      expect(painter.cue.resourceSide, isNull);
      await capture(
        tester,
        CardId.echo,
        state.view(PieceColor.white),
        painter.cue,
        .75,
        tag: 'echo-payoff',
      );
      // Restore the same accepted layer after the isolated capture fixture.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(feedback(before));
      await tester.pumpWidget(feedback(state));
      await tester.pump();
      await tester.pump(
        Duration(
          milliseconds: battleEffectDuration(CardId.echo).inMilliseconds - 1,
        ),
      );
      expect(effect, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(effect, findsNothing);
      await tester.pumpWidget(feedback(state));
      expect(effect, findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'public enemy Mine exposes the same cast and removal target to both viewers',
    () {
      final mine = cast(CardId.mine);
      expect(cueFor(CardId.mine, mine, viewer: PieceColor.black).squares, [21]);
      final removal = cast(CardId.breakSeal, publicSeal: false);
      expect(cueFor(CardId.breakSeal, removal).squares, [20]);
      expect(
        cueFor(CardId.breakSeal, removal, viewer: PieceColor.black).squares,
        [20],
        reason: 'Mine removal is public to the owner and opponent',
      );
    },
  );
}
