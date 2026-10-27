import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_ui/tokens.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:luno_chess/widgets/resource_amount.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture;
import 'battle_deck_account_test.dart' show response;

const shotKey = ValueKey('v205-shot');
Widget shell(Widget child, {bool reduced = false, double scale = 1}) =>
    MaterialApp(
      theme: LunoTheme.dark,
      locale: const Locale('tr'),
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
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
      home: RepaintBoundary(key: shotKey, child: child),
    );

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(shotKey));
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
    for (final box
        in tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .toList()) {
      final d = box.decoration;
      if (d is BoxDecoration && d.image != null) {
        await precacheImage(d.image!.image, context);
      }
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(shotKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v205').create(recursive: true);
    await File('qa/v205/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    final store = GameStore.instance;
    store.data =
        PlayerData.initial()
          ..gold = 123456
          ..gems = 999
          ..trophies = 450;
    store.loaded = true;
    store.hasCompletedTutorial = true;
    store.hasChosenUsername = true;
  });
  test('teaching card examples are unique across lessons', () {
    final cards = [
      for (final step in [4, 5, 7]) ...battleLessonCards(step),
    ];
    expect(cards.toSet().length, cards.length);
    expect(cards.length, 8);
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('responsive deck and enlarged header $size x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: BattleSelectedDeckGrid(cards: starterDeck),
                ),
              ),
            ),
            reduced: true,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final slots = [
          for (final c in starterDeck)
            tester.getTopLeft(find.byKey(ValueKey('deck-slot-${c.wire}'))),
        ];
        final columns = slots.takeWhile((p) => p.dy == slots.first.dy).length;
        if (size.width >= 390 && scale == 1) {
          expect(columns, 5);
        } else {
          expect(columns, inInclusiveRange(1, 4));
        }
        expect(
          slots.map((p) => p.dy).toSet(),
          hasLength((starterDeck.length / columns).ceil()),
        );
        for (final c in starterDeck) {
          final bounds = tester.getRect(
            find.byKey(ValueKey('deck-slot-${c.wire}')),
          );
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.left, greaterThanOrEqualTo(16));
          expect(bounds.right, lessThanOrEqualTo(size.width - 16));
        }
        expect(tester.takeException(), isNull);
        if (size.width == 390 && scale == 1) {
          await capture(tester, 'selected-deck');
        }
        await tester.pumpWidget(
          shell(const HomeScreen(), reduced: true, scale: scale),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        if (size.width == 390 && scale == 1) await capture(tester, 'home');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('catalog ownership locks are based on confirmed entitlements', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      shell(
        BattleDeckScreen(
          catalogOnly: true,
          loadOverride: () async => response(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tiles =
        tester
            .widgetList<BattleCatalogCard>(find.byType(BattleCatalogCard))
            .toList();
    expect(tiles.singleWhere((c) => c.card == CardId.fog).locked, false);
    expect(tiles.singleWhere((c) => c.card == CardId.boardSeal).locked, true);
    expect(tiles.singleWhere((c) => c.card == CardId.shelter).locked, false);
    await capture(tester, 'catalog');
    await tester.ensureVisible(
      find.byWidgetPredicate(
        (w) => w is BattleCatalogCard && w.card == CardId.boardSeal,
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'catalog-locked');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('mana reserves fixed number width for every value', (
    tester,
  ) async {
    Rect? previous;
    for (var mana = 0; mana <= 6; mana++) {
      await tester.pumpWidget(
        shell(
          Scaffold(body: Center(child: BattleMana(value: mana, label: 'Mana'))),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(BattleMana));
      if (previous != null) expect(rect, previous);
      previous = rect;
    }
  });
  testWidgets('shop, play deck and teaching cards render at phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(shell(const ShopScreen(), reduced: true));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'shop');
    await tester.pumpWidget(shell(const PlayModeScreen(), reduced: true));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'play-mode-deck');
    GameStore.instance.tutorialStep = 4;
    await tester.pumpWidget(
      shell(const TutorialScreen(onboarding: true), reduced: true),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'tutorial-cards');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('card press has visible scale and selected rim', (tester) async {
    await tester.pumpWidget(
      shell(
        Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: BattleCardTile(
              card: CardId.shelter,
              cost: 2,
              selected: true,
              onSelect: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BattleCardTile)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final press = tester.widget<Transform>(
      find.byKey(const ValueKey('hand-card-pose')),
    );
    expect(press.transform.storage[0], closeTo(.97, .001));
    expect(press.transformHitTests, isFalse);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).border?.top.color ==
                BattleTokens.gold),
      ),
      findsWidgets,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
  testWidgets('currency decode accounts for its cropped canvas zoom', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dpr in [1.0, 2.0, 3.0]) {
      tester.view.devicePixelRatio = dpr;
      await tester.pumpWidget(
        shell(const Scaffold(body: LunoCurrencyArt(LunoAssets.coin, size: 38))),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).width, (38 * dpr * 2.15).ceil());
      expect(tester.widget<LunoArt>(find.byType(LunoArt)).decodeScale, 2.15);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'draw source arrives once and settles without repeated animation',
    (tester) async {
      final source = GlobalKey();
      Widget hand({bool reduced = false}) => shell(
        Scaffold(
          body: Column(
            children: [
              SizedBox(key: source, width: 32, height: 40),
              SizedBox(
                width: 90,
                height: 150,
                child: BattleCardArrival(
                  card: CardId.radar,
                  source: source,
                  trigger: 1,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(hand());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('draw-source-radar')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
      await tester.pumpWidget(hand());
      expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(hand(reduced: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('draw-source-radar')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final card in CardId.values) {
    testWidgets('accepted ${card.wire} gets one visible cast, not a replay', (
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
      final beforeSnapshot = before.toJson(), afterSnapshot = after.toJson();
      Widget feedback(PlayerView view) => shell(
        Scaffold(
          body: SizedBox.square(
            dimension: 332,
            child: BattleAcceptedFeedback(view: view),
          ),
        ),
      );
      await tester.pumpWidget(feedback(before));
      expect(find.byKey(ValueKey('accepted-card-${card.wire}')), findsNothing);
      await tester.pumpWidget(feedback(after));
      expect(
        find.byKey(ValueKey('accepted-card-${card.wire}')),
        findsOneWidget,
      );
      expect(acceptedBattleCards(before, after), [card]);
      final duration = battleEffectDuration(card).inMilliseconds;
      final spell = find.byKey(ValueKey('spell-${card.wire}-0'));
      final announcement = find.byKey(ValueKey('accepted-card-${card.wire}'));
      await tester.pump();
      await tester.pump(Duration(milliseconds: duration ~/ 4));
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.25, .002),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: announcement, matching: find.byType(Opacity)),
            )
            .opacity,
        1,
      );
      await tester.pump(Duration(milliseconds: duration ~/ 2));
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.75, .002),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: announcement, matching: find.byType(Opacity)),
            )
            .opacity,
        closeTo(.25 / .3, .001),
      );
      if ([CardId.chain, CardId.freeze, CardId.radar].contains(card)) {
        await capture(tester, 'cast-${card.wire}-75-percent');
      }
      await tester.pump(Duration(milliseconds: duration ~/ 4 - 1));
      expect(
        find.byKey(ValueKey('accepted-card-${card.wire}')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(ValueKey('accepted-card-${card.wire}')), findsNothing);
      expect(spell, findsNothing);
      await tester.pumpWidget(feedback(after));
      expect(find.byKey(ValueKey('accepted-card-${card.wire}')), findsNothing);
      expect(before.toJson(), beforeSnapshot);
      expect(after.toJson(), afterSnapshot);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('both players casting the same card never duplicate keys', (
    tester,
  ) async {
    final before = battleFixture().view(PieceColor.white);
    final draft = RuleDraft(before.rules);
    for (final side in PieceColor.values) {
      draft.used[side]!.add(CardId.radar);
    }
    final after = PlayerView(
      draft.freeze(),
      before.viewer,
      before.ownHand,
      before.knowledge,
    );
    Widget feedback(PlayerView view) => shell(
      Scaffold(
        body: SizedBox.square(
          dimension: 332,
          child: BattleAcceptedFeedback(view: view),
        ),
      ),
    );
    await tester.pumpWidget(feedback(before));
    await tester.pumpWidget(feedback(after));
    expect(find.byKey(const ValueKey('accepted-card-radar')), findsOneWidget);
    expect(find.byKey(const ValueKey('accepted-card-radar-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byKey(const ValueKey('accepted-card-radar')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(feedback(after));
    expect(find.byKey(const ValueKey('accepted-card-radar')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final card in [CardId.chain, CardId.freeze]) {
    testWidgets('real ${card.wire} cast animates on its accepted target', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 430);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final before = battleFixture(hand: [card, CardId.shelter]);
      final after = DeckManager.apply(before, PlayCardAction(card, target: 57));
      final beforeSnapshot = before.toJson(), afterSnapshot = after.toJson();
      Widget board(AuthoritativeBattleState state) => shell(
        Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 370,
              child: BattleBoard(
                view: state.view(PieceColor.white),
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(board(before));
      await tester.pumpWidget(board(after));
      expect(find.byKey(const ValueKey('accepted-pulse-57')), findsOneWidget);
      expect(
        acceptedBattleCasts(
          before.view(PieceColor.white),
          after.view(PieceColor.white),
        ),
        [(card: card, side: PieceColor.white)],
      );
      final duration = battleEffectDuration(card).inMilliseconds;
      final spell = find.byKey(ValueKey('spell-${card.wire}-0'));
      final pulse = find.byKey(const ValueKey('accepted-pulse-57'));
      await tester.pump();
      await tester.pump(Duration(milliseconds: duration ~/ 4));
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.25, .002),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: pulse, matching: find.byType(Opacity)),
            )
            .opacity,
        0,
      );
      await tester.pump(Duration(milliseconds: duration ~/ 2));
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.75, .002),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: pulse, matching: find.byType(Opacity)),
            )
            .opacity,
        closeTo(.34, .001),
      );
      await capture(tester, 'board-cast-${card.wire}-75-percent');
      await tester.pump(Duration(milliseconds: duration ~/ 4 - 1));
      expect(find.byKey(const ValueKey('accepted-pulse-57')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('accepted-pulse-57')), findsNothing);
      expect(spell, findsNothing);
      await tester.pumpWidget(board(after));
      expect(pulse, findsNothing);
      expect(spell, findsNothing);
      expect(before.toJson(), beforeSnapshot);
      expect(after.toJson(), afterSnapshot);
      expect(
        after.rules.pieceEffects.single.type,
        card == CardId.freeze ? PieceEffectType.freeze : PieceEffectType.chain,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('a background board update does not replay motion on resume', (
    tester,
  ) async {
    final before = DeckManager.newBattle();
    final after = DeckManager.apply(before, const ChessMoveAction('e2e4'));
    Widget board(AuthoritativeBattleState state) => shell(
      Scaffold(
        body: SizedBox.square(
          dimension: 332,
          child: BattleBoard(view: state.view(PieceColor.white), onTap: (_) {}),
        ),
      ),
    );
    final moving = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('moving-piece-'),
    );
    await tester.pumpWidget(board(before));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(board(after));
    expect(moving, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(board(after));
    expect(moving, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('chess move slides once and reduced motion cancels it', (
    tester,
  ) async {
    final before = DeckManager.newBattle();
    final after = DeckManager.apply(before, const ChessMoveAction('e2e4'));
    Widget board(AuthoritativeBattleState state, {bool reduced = false}) =>
        shell(
          Scaffold(
            body: SizedBox.square(
              dimension: 332,
              child: BattleBoard(
                view: state.view(PieceColor.white),
                onTap: (_) {},
              ),
            ),
          ),
          reduced: reduced,
        );
    await tester.pumpWidget(board(before));
    await tester.pumpWidget(board(after));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('moving-piece-'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('moving-piece-'),
      ),
      findsNothing,
    );
    await tester.pumpWidget(board(before, reduced: true));
    await tester.pumpWidget(board(after, reduced: true));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('moving-piece-'),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('own deck access and opponent deck access coexist', (
    tester,
  ) async {
    await renderBattle(tester);
    expect(find.byKey(const ValueKey('open-own-deck')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-own-deck')));
    await tester.pumpAndSettle();
    expect(find.text('Kartlarım · 10'), findsOneWidget);
    expect(find.text('Elinde'), findsNWidgets(3));
    await closeCapture(tester);
  });
  testWidgets(
    'Pass free and premium locks are distinct and rewards stay visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell(const PassScreen(), reduced: true));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Seviye bekleniyor'), findsNothing);
      expect(find.byType(ImageFiltered), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(ImageFiltered),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      for (final lock in ['common', 'premium']) {
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is LunoArt &&
                w.path == 'assets/native_art/v205-lock-$lock.png',
          ),
          findsWidgets,
        );
      }
      await capture(tester, 'pass-locks');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
