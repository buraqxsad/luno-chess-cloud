import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture, captureKey;
import 'ui_v205_test.dart' show shell;

Future<void> shot(WidgetTester tester, String name, Key key) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(key));
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(key)).renderObject! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v206').create(recursive: true);
    await File('qa/v206/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

PlayerView view({RuleDraft? draft}) {
  final state = battleFixture();
  return PlayerView(
    (draft ?? RuleDraft(state.rules)).freeze(),
    PieceColor.white,
    state.hidden.hands[PieceColor.white]!,
    state.hidden.knowledge[PieceColor.white]!,
  );
}

Future<List<int>> pixels(CardId card, double progress) async {
  final recorder = ui.PictureRecorder();
  BattleSpellPainter(
    cue: BattleSpellCue(card, PieceColor.white, [27]),
    viewer: PieceColor.white,
    progress: progress,
    color: battleAbilityColor(card),
  ).paint(Canvas(recorder), const Size(320, 320));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 320);
  final data = await image.toByteData();
  final result = data!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  final signatures = <int>{};
  for (final card in CardId.values) {
    test(
      'native ${card.wire} effect changes pixels and finishes transparent',
      () async {
        final a = await pixels(card, .28),
            b = await pixels(card, .61),
            end = await pixels(card, 1);
        expect(a.any((p) => p != 0), isTrue);
        expect(b, isNot(a));
        expect(end.every((p) => p == 0), isTrue);
        var hash = 0;
        for (final p in b) {
          hash = (hash * 31 + p) & 0x7fffffff;
        }
        expect(
          signatures.add(hash),
          isTrue,
          reason: 'Every card has its own rendered motion',
        );
      },
    );
    testWidgets(
      'accepted ${card.wire} runs native VFX once without mutating rules',
      (tester) async {
        Widget feedback(PlayerView v) => shell(
          Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 320,
                child: BattleAcceptedFeedback(view: v),
              ),
            ),
          ),
        );
        final before = view();
        final draft = RuleDraft(before.rules)
          ..used[PieceColor.white]!.add(card);
        final after = view(draft: draft), snapshot = after.toJson();
        await tester.pumpWidget(feedback(before));
        expect(find.byKey(ValueKey('spell-${card.wire}-0')), findsNothing);
        await tester.pumpWidget(feedback(after));
        final paint = find.byKey(ValueKey('spell-${card.wire}-0'));
        expect(paint, findsOneWidget);
        final milliseconds = battleEffectDuration(card).inMilliseconds;
        await tester.pump();
        await tester.pump(Duration(milliseconds: milliseconds ~/ 4));
        final first =
            (tester.widget<CustomPaint>(paint).painter! as BattleSpellPainter)
                .progress;
        expect(first, closeTo(.25, .002));
        await tester.pump(Duration(milliseconds: milliseconds ~/ 2));
        final impact =
            tester.widget<CustomPaint>(paint).painter! as BattleSpellPainter;
        expect(impact.progress, greaterThan(first));
        expect(impact.progress, closeTo(.75, .002));
        expect(battleSpellEnvelope(impact.progress), 1);
        await tester.pump(Duration(milliseconds: milliseconds ~/ 4 - 1));
        expect(paint, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(paint, findsNothing);
        await tester.pumpWidget(feedback(after));
        expect(paint, findsNothing);
        expect(after.toJson(), snapshot);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'target extraction uses stable piece IDs and public enemy Mine targets',
    () {
      final before = view(), draft = RuleDraft(before.rules);
      draft.pieceEffects.add(
        ActivePieceEffect(
          id: 'ice',
          type: PieceEffectType.freeze,
          owner: PieceColor.white,
          pieceId: draft.pieceIds[57]!,
          responseSide: PieceColor.black,
          duration: EffectDuration.move,
        ),
      );
      draft.boardEffects.add(
        BoardEffectInstance(
          id: 'mine',
          type: BoardEffectType.mine,
          owner: PieceColor.black,
          squares: [26],
          responseSide: PieceColor.white,
          duration: EffectDuration.persistent,
        ),
      );
      expect(
        BattleSpellCue.fromViews(
          CardId.freeze,
          PieceColor.white,
          before,
          view(draft: draft),
        ).squares,
        [57],
      );
      expect(
        BattleSpellCue.fromViews(
          CardId.mine,
          PieceColor.black,
          before,
          view(draft: draft),
        ).squares,
        [26],
      );
      expect(
        battleSquareCenter(0, PieceColor.white, 40),
        const Offset(20, 300),
      );
      expect(
        battleSquareCenter(0, PieceColor.black, 40),
        const Offset(300, 20),
      );
    },
  );
  test('purify and seal break animate cleared public targets', () {
    final draft = RuleDraft(view().rules);
    draft.pieceEffects.add(
      ActivePieceEffect(
        id: 'chain',
        type: PieceEffectType.chain,
        owner: PieceColor.black,
        pieceId: draft.pieceIds[1]!,
        responseSide: PieceColor.white,
        duration: EffectDuration.move,
      ),
    );
    draft.boardEffects.add(
      BoardEffectInstance(
        id: 'lock',
        type: BoardEffectType.lockedSquare,
        owner: PieceColor.black,
        squares: [26],
        responseSide: PieceColor.white,
        duration: EffectDuration.move,
      ),
    );
    final before = view(draft: draft), after = view();
    expect(
      BattleSpellCue.fromViews(
        CardId.purify,
        PieceColor.white,
        before,
        after,
      ).squares,
      [1],
    );
    expect(
      BattleSpellCue.fromViews(
        CardId.breakSeal,
        PieceColor.white,
        before,
        after,
      ).squares,
      [26],
    );
    expect(
      BattleSpellCue(CardId.fog, PieceColor.white, [
        -1,
        64,
        20,
        20,
        21,
        22,
        23,
        24,
      ]).squares,
      [20, 21, 22, 23],
    );
  });
  for (final scale in [1.0, 1.5, 2.0]) {
    for (final compact in [true, false]) {
      testWidgets(
        'mana text remains inside stable meter $scale compact=$compact',
        (tester) async {
          Rect? initial;
          for (var mana = 0; mana <= 6; mana++) {
            await tester.pumpWidget(
              shell(
                Scaffold(
                  body: Center(
                    child: BattleMana(
                      value: mana,
                      label: 'Mana',
                      compact: compact,
                    ),
                  ),
                ),
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            final meter = tester.getRect(
              find.byKey(const ValueKey('battle-mana-meter')),
            );
            initial ??= meter;
            expect(meter, initial);
            final text = tester.getRect(find.text('$mana / 6'));
            expect(meter.inflate(.01).contains(text.topLeft), isTrue);
            expect(meter.inflate(.01).contains(text.bottomRight), isTrue);
            expect(
              (tester.renderObject(find.text('$mana / 6')) as RenderParagraph)
                  .didExceedMaxLines,
              isFalse,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets(
    'small info art retains a 44 pixel tap area and selection flashes',
    (tester) async {
      var details = 0;
      Widget card(bool selected, {bool reduced = false}) => shell(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 78,
              height: 150,
              child: BattleCardTile(
                card: CardId.freeze,
                cost: 3,
                selected: selected,
                onSelect: () {},
                onDetail: () => details++,
              ),
            ),
          ),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(card(false));
      final detail = find.byKey(const ValueKey('detail-freeze'));
      expect(tester.getSize(detail), const Size(44, 44));
      final button = tester.widget<IconButton>(detail);
      expect((button.icon as BattleArt).size, 16);
      await tester.tap(detail);
      expect(details, 1);
      await tester.pumpWidget(card(true));
      expect(find.byType(BattleCardSelectionFlash), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(card(true, reduced: true));
      expect(find.byType(BattleCardSelectionFlash), findsNothing);
    },
  );
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('four card battle layout $size $language', (tester) async {
        await renderBattle(
          tester,
          size: size,
          language: language,
          state: battleFixture(
            hand: const [
              CardId.shadowContract,
              CardId.fateExchange,
              CardId.pawnDeviation,
              CardId.boardSeal,
            ],
          ),
        );
        for (final card in [
          CardId.shadowContract,
          CardId.fateExchange,
          CardId.pawnDeviation,
          CardId.boardSeal,
        ]) {
          expect(
            tester
                .getSize(find.byKey(ValueKey('card-cost-${card.wire}')))
                .width,
            lessThan(20),
          );
          final tile = find.byKey(ValueKey('hand-${card.wire}'));
          final title =
              find.descendant(of: tile, matching: find.byType(Text)).last;
          expect(
            (tester.renderObject(title) as RenderParagraph).didExceedMaxLines,
            isFalse,
          );
          if (size.width == 320) {
            final paragraph = tester.renderObject(title) as RenderParagraph;
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length,
              ),
            );
            expect(
              boxes.map((b) => b.top).toSet().length,
              lessThanOrEqualTo(2),
              reason:
                  'A two-word card name must not strand one letter on a third line',
            );
          }
          if (size.width == 320) {
            final action = tester.getRect(
              find.byKey(const ValueKey('pass-card')),
            );
            expect(
              tester.getRect(tile).bottom,
              lessThanOrEqualTo(action.top),
              reason:
                  'The entire hand must remain above the bottom action on a compact phone',
            );
          }
        }
        if (language == 'tr') {
          await shot(tester, 'battle-${size.width.toInt()}', captureKey);
        }
        expect(tester.takeException(), isNull);
        await closeCapture(tester);
      });
    }
  }
  testWidgets('24 native effect contact frames', (tester) async {
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const key = ValueKey('v206-effects');
    await tester.pumpWidget(
      shell(
        Scaffold(
          body: RepaintBoundary(
            key: key,
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final card in CardId.values)
                  Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BattleSpellPainter(
                            cue: BattleSpellCue(card, PieceColor.white, [27]),
                            viewer: PieceColor.white,
                            progress: .55,
                            color: battleAbilityColor(card),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          card.wire,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await shot(tester, 'effects-all-24', key);
    expect(tester.takeException(), isNull);
  });
  for (final card in [
    CardId.freeze,
    CardId.chain,
    CardId.fog,
    CardId.boardSeal,
  ]) {
    testWidgets('real ${card.wire} cast keeps its caption outside the board', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness(hand: [card, CardId.shelter, CardId.radar]);
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(
        shell(
          BattleV1Screen(
            controllerOverride: h.controller,
            clockOverride: (_) => 300000,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String key) async {
        final f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap('hand-${card.wire}');
      await tap(
        'square-${card == CardId.freeze || card == CardId.chain ? 57 : 28}',
      );
      await tester.tap(find.byKey(const ValueKey('play-card')));
      await tester.pump();
      await tester.pump();
      final milliseconds = battleEffectDuration(card).inMilliseconds;
      final spell = find.byKey(ValueKey('spell-${card.wire}-0'));
      await tester.pump(Duration(milliseconds: milliseconds ~/ 4));
      expect(h.sent, hasLength(1));
      expect(spell, findsOneWidget);
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        0,
        reason: 'The external card is still travelling, before board impact',
      );
      expect(find.byKey(ValueKey('accepted-card-${card.wire}')), findsNothing);
      final notice = find.byKey(ValueKey('cast-notice-${card.wire}'));
      expect(notice, findsOneWidget);
      expect(
        tester.getRect(notice).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(BattleBoard)).bottom),
      );
      await shot(
        tester,
        'cast-${card.wire}-25-percent',
        const ValueKey('v205-shot'),
      );
      await tester.pump(Duration(milliseconds: milliseconds ~/ 4));
      final impact =
          tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter;
      expect(impact.progress, closeTo(.5, .002));
      expect(find.byKey(ValueKey('card-flight-${card.wire}')), findsNothing);
      final target = card == CardId.freeze || card == CardId.chain ? 57 : 28;
      final ring = find.byKey(ValueKey('impact-ring-$target'));
      expect(ring, findsOneWidget);
      await shot(
        tester,
        'cast-${card.wire}-50-percent',
        const ValueKey('v205-shot'),
      );
      final impactAt = milliseconds ~/ 2;
      final arrived =
          tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter;
      expect(
        arrived.progress,
        closeTo(battleExternalImpactProgress(impactAt / milliseconds), .002),
      );
      expect(battleSpellEnvelope(arrived.progress), 1);
      expect(ring, findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: ring, matching: find.byType(Opacity)),
            )
            .opacity,
        closeTo(.42, .002),
      );
      expect(
        tester.getRect(notice).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(BattleBoard)).bottom),
      );
      await shot(
        tester,
        'cast-${card.wire}-impact',
        const ValueKey('v205-shot'),
      );
      await tester.pump(Duration(milliseconds: milliseconds ~/ 4));
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.75, .002),
      );
      expect(ring, findsNothing);
      expect(find.byKey(ValueKey('card-flight-${card.wire}')), findsNothing);
      final elapsed = milliseconds ~/ 4 * 3;
      await tester.pump(Duration(milliseconds: milliseconds - elapsed - 1));
      expect(notice, findsOneWidget);
      expect(spell, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(spell, findsNothing);
      expect(
        notice,
        findsOneWidget,
        reason: 'Readable copy outlives the short VFX',
      );
      await tester.pump(Duration(milliseconds: 3599 - milliseconds));
      expect(notice, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(notice, findsNothing);
      expect(spell, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'cast caption cancels on background and account handoff but stays readable in reduced motion',
    (tester) async {
      Widget notice(PlayerView v, {bool reduced = false}) => shell(
        Scaffold(
          body: BattleCastNotice(
            view: v,
            child: const Text('Turn instruction'),
          ),
        ),
        reduced: reduced,
      );
      final before = view(),
          d = RuleDraft(view().rules)
            ..used[PieceColor.white]!.add(CardId.freeze);
      final after = view(draft: d);
      await tester.pumpWidget(notice(before));
      await tester.pumpWidget(notice(after));
      expect(find.byKey(const ValueKey('cast-notice-freeze')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cast-notice-freeze')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(notice(after));
      expect(find.byKey(const ValueKey('cast-notice-freeze')), findsNothing);
      await tester.pumpWidget(notice(before));
      await tester.pumpWidget(notice(after));
      await tester.pumpWidget(notice(after, reduced: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cast-notice-freeze')), findsOneWidget);
      await tester.pumpWidget(notice(before));
      await tester.pumpWidget(notice(after));
      await tester.pumpWidget(
        notice(
          PlayerView(after.rules, PieceColor.black, [], PlayerKnowledgeState()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cast-notice-freeze')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('hand card width is stable with one through four cards', (
    tester,
  ) async {
    double? initial;
    for (var count = 1; count <= 4; count++) {
      final state = battleFixture(hand: starterDeck.take(count).toList());
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 304,
                child: BattleHand(
                  view: state.view(PieceColor.white),
                  enabled: true,
                  compact: true,
                  cost: (_) => 2,
                  selectable: (_) => true,
                  onSelect: (_) {},
                  onDetail: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final width =
          tester.getSize(find.byKey(const ValueKey('hand-radar'))).width;
      initial ??= width;
      expect(width, initial);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'a triggered mine has native impact without another cast announcement',
    (tester) async {
      Widget feedback(PlayerView v) => shell(
        Scaffold(
          body: SizedBox.square(
            dimension: 320,
            child: BattleAcceptedFeedback(view: v),
          ),
        ),
      );
      final before = view(), d = RuleDraft(before.rules);
      d.pieceEffects.add(
        ActivePieceEffect(
          id: 'triggered-mine',
          type: PieceEffectType.mineDebuff,
          owner: PieceColor.black,
          pieceId: d.pieceIds[12]!,
          responseSide: PieceColor.white,
          duration: EffectDuration.pieceMove,
        ),
      );
      await tester.pumpWidget(feedback(before));
      await tester.pumpWidget(feedback(view(draft: d)));
      final paint =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('spell-mine-0')),
                  )
                  .painter!
              as BattleSpellPainter;
      expect(paint.cue.squares, [12]);
      expect(paint.cue.side, PieceColor.black);
      expect(find.byKey(const ValueKey('accepted-card-mine')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('echo reacts once to its exact opposing card', (tester) async {
    Widget feedback(PlayerView v) => shell(
      Scaffold(
        body: SizedBox.square(
          dimension: 320,
          child: BattleAcceptedFeedback(view: v),
        ),
      ),
    );
    final d = RuleDraft(view().rules);
    d.modifiers.add(
      const PendingModifier(
        id: 'echo',
        type: ModifierType.echo,
        owner: PieceColor.white,
        responseSide: PieceColor.black,
        targetCard: CardId.radar,
        ownTurn: 2,
      ),
    );
    final before = view(draft: d),
        next =
            RuleDraft(before.rules)
              ..modifiers.clear()
              ..used[PieceColor.black]!.add(CardId.radar);
    final after = view(draft: next);
    await tester.pumpWidget(feedback(before));
    await tester.pumpWidget(feedback(after));
    expect(find.byKey(const ValueKey('spell-echo-1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pumpWidget(feedback(after));
    expect(find.byKey(const ValueKey('spell-echo-1')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
