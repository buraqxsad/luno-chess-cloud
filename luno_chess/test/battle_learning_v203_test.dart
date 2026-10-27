import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/i18n/battle_learning_copy.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/guide_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/battle_lesson_stage.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget shell(Widget child, {String language = 'tr', double scale = 1}) =>
    MaterialApp(
      theme: LunoTheme.dark,
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
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
      home: child,
    );
void noClippedText(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is RenderParagraph && paragraph.hasSize) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: paragraph.text.toPlainText(),
      );
    }
  }
}

void main() {
  setUpAll(() async {
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.loaded = true;
    GameStore.instance.hasCompletedTutorial = false;
    GameStore.instance.tutorialStep = 0;
  });
  test('TR and EN lessons use current V1 limits without legacy cards', () {
    for (final language in ['tr', 'en']) {
      final l = LunoLocalizations(Locale(language));
      expect(l.battleLessons, hasLength(10));
      final text = l.battleLessons
          .map((s) => '${s.title} ${s.body} ${s.hint}')
          .join(' ');
      expect(text, contains('6'));
      expect(text, contains('10'));
      expect(text, isNot(contains('Barbar')));
      expect(text, isNot(contains('altılı')));
      expect(text, isNot(contains('max 10')));
    }
    expect(starterDeck, hasLength(10));
    expect(CardId.values, hasLength(24));
  });
  for (final language in ['tr', 'en']) {
    testWidgets('arena promotion has no invented six-card slots $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final rewards in [
        <String>[],
        ['freeze', 'shield'],
      ]) {
        await tester.pumpWidget(
          shell(
            ArenaPromotionScreen(
              arenaName: 'Piyon Vadisi',
              arenaArt: LunoAssets.arena(1),
              unlockedCards: rewards,
            ),
            language: language,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('KART YUVASI'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is LunoArt &&
                rewards.any((id) => w.path == LunoAssets.card(id, 1)),
          ),
          findsNWidgets(rewards.length),
        );
        noClippedText(tester);
      }
    });
  }
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(800, 1100),
  ]) {
    for (final language in ['tr', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('all 10 lessons $size $language x$scale', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final l = LunoLocalizations(Locale(language));
          for (var step = 0; step < 10; step++) {
            GameStore.instance.tutorialStep = step;
            await tester.pumpWidget(
              shell(
                TutorialScreen(key: ValueKey(step), onboarding: true),
                language: language,
                scale: scale,
              ),
            );
            await tester.pump();
            expect(find.text(l.battleLessons[step].title), findsOneWidget);
            expect(find.byType(LunoButton).hitTestable(), findsOneWidget);
            noClippedText(tester);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
        testWidgets('current catalog details $size $language x$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final legacyDeck = List<String>.of(GameStore.instance.data.deck);
          await tester.pumpWidget(
            shell(
              const BattleDeckScreen(catalogOnly: true),
              language: language,
              scale: scale,
            ),
          );
          await tester.pump();
          await tester.scrollUntilVisible(
            find.byType(BattleCatalogCard).first,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester
                .widgetList<BattleCatalogCard>(find.byType(BattleCatalogCard))
                .map((c) => c.card)
                .toSet(),
            CardId.values.toSet(),
          );
          noClippedText(tester);
          final l = LunoLocalizations(Locale(language));
          for (final card in CardId.values) {
            final closed = showBattleCatalogDetail(
              tester.element(find.byType(BattleDeckScreen)),
              card,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
            expect(find.text(l.battleCardDetail(card)), findsOneWidget);
            noClippedText(tester);
            await tester.tap(find.byTooltip(l.battle(BattleCopy.close)));
            await tester.pumpAndSettle();
            await closed;
          }
          expect(GameStore.instance.data.deck, legacyDeck);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
  testWidgets('practice makes only legal moves and never changes account', (
    tester,
  ) async {
    final before = GameStore.instance.data.toJson();
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: SingleChildScrollView(child: BattleLessonStage(step: 1)),
        ),
      ),
    );
    await tester.pump();
    final original =
        tester
            .widget<BattleBoard>(find.byType(BattleBoard))
            .view
            .rules
            .toJson();
    await tester.tap(find.byKey(const ValueKey('square-12')));
    await tester.pump();
    expect(tester.widget<BattleBoard>(find.byType(BattleBoard)).targets, {
      20,
      28,
    });
    await tester.tap(find.byKey(const ValueKey('square-36')));
    await tester.pump();
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.toJson(),
      original,
    );
    await tester.tap(find.byKey(const ValueKey('square-12')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('square-28')));
    await tester.pump();
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).enabled,
      isFalse,
    );
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.toJson(),
      isNot(original),
    );
    expect(GameStore.instance.data.toJson(), before);
    await tester.tap(find.byTooltip('Yeniden dene'));
    await tester.pump();
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.toJson(),
      original,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    for (final language in ['tr', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('guide shop and pass full scroll $size $language x$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final screen in [
            const GuideScreen(),
            const ShopScreen(),
            const PassScreen(),
          ]) {
            await tester.pumpWidget(
              shell(screen, language: language, scale: scale),
            );
            await tester.pump(const Duration(milliseconds: 100));
            for (var i = 0; i < 100; i++) {
              noClippedText(tester);
              final scroller = find.byType(Scrollable).first;
              final position = tester.state<ScrollableState>(scroller).position;
              if (position.pixels >= position.maxScrollExtent - .1) break;
              await tester.drag(scroller, const Offset(0, -280));
              await tester.pump(const Duration(milliseconds: 100));
            }
            noClippedText(tester);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        });
      }
    }
  }
}
