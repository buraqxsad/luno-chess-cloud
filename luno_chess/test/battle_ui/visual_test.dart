import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import '../helpers/battle_v1_response.dart';
import 'fixtures.dart';

const captureKey = ValueKey('battle-capture');

void expectNoBattleLayoutError(WidgetTester tester) {
  final overflow = <String>[];
  for (final flex in tester.allRenderObjects.whereType<RenderFlex>()) {
    var child = flex.firstChild;
    while (child != null) {
      final data = child.parentData! as FlexParentData;
      final end =
          flex.direction == Axis.vertical
              ? data.offset.dy + child.size.height
              : data.offset.dx + child.size.width;
      final limit =
          flex.direction == Axis.vertical ? flex.size.height : flex.size.width;
      if (end > limit + .01) {
        overflow.add(
          '${flex.debugCreator}: ${flex.direction} child ends '
          '${(end - limit).toStringAsFixed(2)} px beyond ${flex.size}',
        );
      }
      child = data.nextSibling;
    }
  }
  expect(tester.takeException(), isNull, reason: overflow.join('\n'));
}

Future<BattleV1Controller> renderBattle(
  WidgetTester tester, {
  AuthoritativeBattleState? state,
  Size size = const Size(390, 844),
  String language = 'tr',
  double textScale = 1,
  int clock = 300000,
  bool longNames = false,
  Completer<void>? hold,
  ThemeData? theme,
  bool reducedMotion = true,
  PieceColor viewer = PieceColor.white,
  BattleV1Request? requestOverride,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final battle = state ?? battleFixture();
  final uid = viewer == PieceColor.white ? 'self' : 'other';
  final response = v1Response(state: battle, uid: uid, side: viewer);
  if (battle.rules.terminal case final terminal?) {
    response['status'] = 'finished';
    final public = (response['view'] as Map)['public'] as Map;
    public['result'] = {
      'reason': terminal.reason,
      'winner': terminal.winner == null ? null : sideWire(terminal.winner!),
    };
    public['settlementStatus'] = 'pending';
  }
  if (longNames) {
    final players =
        ((response['view'] as Map)['public'] as Map)['players'] as Map;
    (players['w'] as Map)['name'] = 'LunoUstasınınUzunOyuncuAdı';
    (players['b'] as Map)['name'] = 'GölgeHükümdarınınUzunOyuncuAdı';
  }
  final controller = BattleV1Controller(
    uid: uid,
    matchId: v1MatchId,
    initialResponse: response,
    persistPending: (_) async {},
    request:
        requestOverride ??
        (_, _) async {
          if (hold != null) await hold.future;
          return response;
        },
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: Locale(language),
        supportedLocales: LunoLocalizations.supportedLocales,
        localizationsDelegates: const [
          LunoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                padding: const EdgeInsets.only(top: 24, bottom: 24),
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
        home: BattleV1Screen(
          controllerOverride: controller,
          clockOverride: (_) => clock,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await warmBattleImages(tester);
  return controller;
}

Future<void> warmBattleImages(WidgetTester tester) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  final context = tester.element(find.byType(BattleV1Screen));
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(image.image, context);
    }
    for (final box
        in tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .toList()) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        await precacheImage(decoration.image!.image, context);
      }
    }
  });
  await tester.pumpAndSettle();
}

Future<void> closeCapture(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

AuthoritativeBattleState editedFixture(
  void Function(RuleDraft) edit, {
  List<CardId>? hand,
}) {
  final state = battleFixture(
    hand: hand ?? const [CardId.shelter, CardId.chain, CardId.lockedSquare],
  );
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

AuthoritativeBattleState effectFixture({
  BoardEffectType? board,
  PieceEffectType? piece,
  bool vow = false,
  bool all = false,
}) => editedFixture((d) {
  for (final type
      in all
          ? BoardEffectType.values
          : board == null
          ? <BoardEffectType>[]
          : [board]) {
    d.boardEffects.add(
      BoardEffectInstance(
        id: 'board-${type.name}',
        type: type,
        owner: PieceColor.black,
        squares:
            type == BoardEffectType.fog || type == BoardEffectType.boardSeal
                ? boardZone(12)
                : [12],
        responseSide: PieceColor.white,
        duration: EffectDuration.move,
      ),
    );
  }
  for (final type
      in all
          ? PieceEffectType.values
          : piece == null
          ? <PieceEffectType>[]
          : [piece]) {
    d.pieceEffects.add(
      ActivePieceEffect(
        id: 'piece-${type.name}',
        type: type,
        owner: PieceColor.black,
        pieceId: d.pieceIds[12]!,
        responseSide: PieceColor.white,
        duration: EffectDuration.move,
      ),
    );
  }
  if (vow || all) {
    d.vows.add(
      const VowState(
        id: 'watch',
        type: VowType.watch,
        owner: PieceColor.black,
        pieceId: null,
        square: 12,
        remainingMoves: 1,
      ),
    );
  }
});

AuthoritativeBattleState knowledgeFixture(bool stale) {
  final state = battleFixture();
  return AuthoritativeBattleState(
    state.rules,
    AuthoritativeHiddenState(
      hands: state.hidden.hands,
      decks: state.hidden.decks,
      knowledge: {
        ...state.hidden.knowledge,
        PieceColor.white: PlayerKnowledgeState(
          knownUpcomingCards:
              state.hidden.decks[PieceColor.white]!.take(2).toList(),
          radarObservations: [
            RadarObservation(
              CardId.shelter,
              inHand: true,
              observedTurn: 2,
              opponentCumulativeDrawCountAtObservation: 0,
              stale: stale,
            ),
          ],
        ),
      },
    ),
  );
}

Future<void> visualTap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const fourCards = [
  CardId.shadowContract,
  CardId.fateExchange,
  CardId.pawnDeviation,
  CardId.boardSeal,
];

class VisualScene {
  final String name;
  final AuthoritativeBattleState Function()? fixture;
  final List<String> taps;
  final Size size;
  final double scale;
  const VisualScene(
    this.name, {
    this.fixture,
    this.taps = const [],
    this.size = const Size(390, 844),
    this.scale = 1,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    final font = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/nunito/nunito-variable.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final scenes = <VisualScene>[
    const VisualScene('default'),
    VisualScene('first-turn', fixture: () => battleFixture(firstTurn: true)),
    VisualScene('four-card', fixture: () => battleFixture(hand: fourCards)),
    VisualScene('zero-card', fixture: () => battleFixture(hand: const [])),
    VisualScene(
      'low-mana',
      fixture: () => editedFixture((d) => d.mana[PieceColor.white] = 0),
    ),
    const VisualScene('selected', taps: ['hand-shelter']),
    const VisualScene('piece-target', taps: ['hand-shelter', 'square-12']),
    const VisualScene(
      'square-target',
      taps: ['hand-locked_square', 'square-28'],
    ),
    VisualScene(
      'zone',
      fixture:
          () => battleFixture(hand: [CardId.fog, CardId.shelter, CardId.mine]),
      taps: ['hand-fog', 'square-28'],
    ),
    VisualScene(
      'movement',
      fixture:
          () => DeckManager.apply(
            battleFixture(
              hand: [CardId.pawnDeviation, CardId.shelter, CardId.mine],
            ),
            const PlayCardAction(CardId.pawnDeviation, target: 12),
          ),
    ),
    for (final type in BoardEffectType.values)
      VisualScene(type.name, fixture: () => effectFixture(board: type)),
    for (final type in PieceEffectType.values.where(
      (t) => t != PieceEffectType.mineDebuff,
    ))
      VisualScene(type.name, fixture: () => effectFixture(piece: type)),
    VisualScene('vow', fixture: () => effectFixture(vow: true)),
    VisualScene(
      'mine-vow',
      fixture: () => effectFixture(board: BoardEffectType.mine, vow: true),
    ),
    VisualScene('multi-effect', fixture: () => effectFixture(all: true)),
    const VisualScene('arsenal', taps: ['open-arsenal']),
    VisualScene('radar', fixture: () => knowledgeFixture(false)),
    VisualScene('radar-stale', fixture: () => knowledgeFixture(true)),
    VisualScene(
      'prophecy',
      fixture:
          () => DeckManager.apply(
            battleFixture(hand: [CardId.prophecy, CardId.shelter, CardId.mine]),
            const PlayCardAction(CardId.prophecy),
          ),
      taps: ['open-private'],
    ),
    VisualScene(
      'fate',
      fixture:
          () => DeckManager.apply(
            battleFixture(
              hand: [CardId.fateExchange, CardId.shelter, CardId.mine],
            ),
            const PlayCardAction(
              CardId.fateExchange,
              sacrifice: CardId.shelter,
            ),
          ),
      taps: ['open-private'],
    ),
    for (final type in ModifierType.values)
      VisualScene(
        type.name,
        fixture:
            () => editedFixture(
              (d) => d.modifiers.add(
                PendingModifier(
                  id: 'modifier',
                  type: type,
                  owner: PieceColor.black,
                  responseSide: PieceColor.white,
                  targetCard:
                      type == ModifierType.discount ? null : CardId.shelter,
                  ownTurn: 2,
                ),
              ),
            ),
      ),
    VisualScene(
      'check',
      fixture:
          () => editedFixture((d) {
            d.board = Board.fromFen('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1');
            d.pieceIds = List.generate(
              64,
              (i) => d.board.pieceAt(i) == null ? null : 'p$i',
            );
            d.phase = BattlePhase.chess;
          }),
    ),
    const VisualScene('low-time'),
    const VisualScene('reconnect'),
    const VisualScene('pending'),
    const VisualScene('mismatch'),
    for (final reason in ['checkmate', 'stalemate', 'timeout', 'resign'])
      VisualScene(
        reason,
        fixture:
            () => editedFixture((d) {
              d.phase = BattlePhase.terminal;
              d.terminal = TerminalState(
                reason,
                winner: reason == 'stalemate' ? null : PieceColor.white,
              );
            }),
      ),
    const VisualScene('compact', size: Size(320, 640)),
    const VisualScene('large', size: Size(430, 932)),
    const VisualScene('long-tr'),
    const VisualScene('large-text', size: Size(320, 740), scale: 1.5),
    const VisualScene('match-menu', taps: ['open-menu']),
    const VisualScene('resign-confirm', taps: ['open-menu', 'resign-menu']),
    const VisualScene('card-detail', taps: ['detail-shelter']),
    VisualScene(
      'compact-four',
      fixture: () => battleFixture(hand: fourCards),
      size: const Size(320, 640),
    ),
    VisualScene(
      'compact-four-large-text',
      fixture: () => battleFixture(hand: fourCards),
      size: const Size(320, 640),
      scale: 1.5,
    ),
    const VisualScene(
      'arsenal-large-text',
      size: Size(320, 640),
      scale: 1.5,
      taps: ['open-arsenal'],
    ),
    VisualScene(
      'fate-large-text',
      size: const Size(320, 640),
      scale: 1.5,
      fixture:
          () => DeckManager.apply(
            battleFixture(
              hand: [CardId.fateExchange, CardId.shelter, CardId.mine],
            ),
            const PlayCardAction(
              CardId.fateExchange,
              sacrifice: CardId.shelter,
            ),
          ),
      taps: ['open-private'],
    ),
  ];
  assert(scenes.length == 50);
  // V216 references were reviewed against the preserved previous 50 images.
  // See qa/v216/golden-review; layout/behavior assertions remain independent.
  for (final scene in scenes) {
    testWidgets('visual state ${scene.name}', (tester) async {
      Completer<void>? hold;
      if (scene.name == 'pending' || scene.name == 'reconnect') {
        hold = Completer<void>();
      }
      final controller = await renderBattle(
        tester,
        state: scene.fixture?.call(),
        size: scene.size,
        textScale: scene.scale,
        clock: scene.name == 'low-time' ? 19000 : 300000,
        longNames: scene.name == 'long-tr',
        hold: hold,
      );
      if (scene.name == 'pending') {
        await tester.ensureVisible(find.byKey(const ValueKey('pass-card')));
        await tester.tap(find.byKey(const ValueKey('pass-card')));
        await tester.pump();
      }
      if (scene.name == 'reconnect') {
        unawaited(controller.reconnect());
        await tester.pump();
      }
      if (scene.name == 'mismatch') {
        controller.error = const FormatException('Projection mismatch');
        controller.notifyListeners();
        await tester.pump();
      }
      for (final key in scene.taps) {
        await visualTap(tester, key);
      }
      if (scene.name.startsWith('radar')) {
        await tester.tap(find.byTooltip('Özel bilgiler'));
        await tester.pumpAndSettle();
        expect(find.byType(PrivateKnowledgeSheet), findsOneWidget);
      }
      await warmBattleImages(tester);
      expectNoBattleLayoutError(tester);
      if (scene.name == 'compact-four') {
        for (final art
            in find
                .descendant(
                  of: find.byType(BattleHand),
                  matching: find.byType(BattleCardArt),
                )
                .evaluate()) {
          expect(
            tester.getSize(find.byWidget(art.widget)).height,
            greaterThanOrEqualTo(30),
          );
        }
      }
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile('goldens/${scene.name}.png'),
      );
      if (scene.name == 'mismatch' ||
          scene.name == 'pending' ||
          scene.name == 'reconnect') {
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).enabled,
          false,
        );
      }
      await closeCapture(tester);
      hold?.complete();
      await tester.pump();
    });
  }

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final language in ['tr', 'en']) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('real screen $width $language $scale', (tester) async {
          await renderBattle(
            tester,
            state: battleFixture(hand: fourCards),
            size: Size(width, 844),
            language: language,
            textScale: scale,
          );
          expectNoBattleLayoutError(tester);
          await visualTap(tester, 'hand-shadow_contract');
          for (final paragraph in tester.renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(BattleHand),
              matching: find.byType(RichText),
            ),
          )) {
            expect(
              paragraph.didExceedMaxLines,
              false,
              reason: 'Card copy was truncated at $width / $language / $scale',
            );
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('discard-card')),
          );
          await tester.pump();
          final button = tester.getRect(
            find.byKey(const ValueKey('discard-card')),
          );
          expect(button.bottom, lessThanOrEqualTo(820));
          expect(button.height, greaterThanOrEqualTo(48));
          expectNoBattleLayoutError(tester);
          await closeCapture(tester);
        });
      }
    }
  }
  for (final size in [
    const Size(320, 480),
    const Size(640, 360),
    const Size(768, 1024),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('short/wide result $size $language at 1.5', (tester) async {
        await renderBattle(
          tester,
          size: size,
          language: language,
          textScale: 1.5,
          state: editedFixture((d) {
            d.phase = BattlePhase.terminal;
            d.terminal = const TerminalState(
              'checkmate',
              winner: PieceColor.white,
            );
          }),
        );
        final home = find.text(language == 'tr' ? 'Ana menü' : 'Home');
        await tester.ensureVisible(home);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(home);
        expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        expectNoBattleLayoutError(tester);
        await closeCapture(tester);
      });
    }
  }
  for (final size in [
    const Size(320, 480),
    const Size(640, 360),
    const Size(768, 1024),
  ]) {
    for (final language in ['tr', 'en']) {
      for (final modal in [
        'open-menu',
        'detail-shadow_contract',
        'open-arsenal',
        'open-private',
        'radar',
      ]) {
        testWidgets('responsive modal $modal $size $language', (tester) async {
          final state =
              modal == 'open-private'
                  ? DeckManager.apply(
                    battleFixture(
                      hand: [CardId.fateExchange, CardId.shelter, CardId.mine],
                    ),
                    const PlayCardAction(
                      CardId.fateExchange,
                      sacrifice: CardId.shelter,
                    ),
                  )
                  : modal == 'radar'
                  ? knowledgeFixture(true)
                  : battleFixture(hand: fourCards);
          await renderBattle(
            tester,
            state: state,
            size: size,
            language: language,
            textScale: 1.5,
          );
          if (modal == 'radar') {
            final button = find.byTooltip(
              language == 'tr' ? 'Özel bilgiler' : 'Private knowledge',
            );
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
          } else {
            await visualTap(tester, modal);
          }
          final close = find.byTooltip(language == 'tr' ? 'Kapat' : 'Close');
          await tester.ensureVisible(close);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(close);
          expect(bounds.top, greaterThanOrEqualTo(24));
          expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
          expect(bounds.width, greaterThanOrEqualTo(48));
          expectNoBattleLayoutError(tester);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(
            find.byTooltip(language == 'tr' ? 'Kapat' : 'Close'),
            findsNothing,
          );
          await closeCapture(tester);
        });
      }
    }
  }
}
