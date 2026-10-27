import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;

class Pushes extends NavigatorObserver {
  int count = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    count++;
  }
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasChosenUsername = true
      ..firstSessionMatchesStarted = 2
      ..hasCompletedTutorial = true;
  });

  for (final language in ['tr', 'en']) {
    testWidgets('home resource and primary entries open once: $language', (
      tester,
    ) async {
      final entries = <(String, Type)>[
        (LunoAssets.statusProfile, ProfileScreen),
        (LunoAssets.navChat, InboxScreen),
        (LunoAssets.trophy, SeasonScreen),
        (LunoAssets.coin, ShopScreen),
        (LunoAssets.gem, ShopScreen),
      ];
      for (final entry in entries) {
        await pumpHome(tester, language);
        final art = find.byWidgetPredicate(
          (widget) => widget is LunoArt && widget.path == entry.$1,
        );
        final ink = find.ancestor(of: art, matching: find.byType(InkWell));
        final action = tester.widget<InkWell>(ink.first).onTap!;
        action();
        action();
        await advance(tester);
        expect(
          find.byType(entry.$2, skipOffstage: false),
          findsOneWidget,
          reason: entry.$1,
        );
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await advance(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
      }
      await pumpHome(tester, language);
      final label = language == 'en' ? 'ENTER BATTLE' : 'SAVAŞA GİR';
      final ink = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      final action = tester.widget<InkWell>(ink.first).onTap!;
      action();
      action();
      await advance(tester);
      expect(find.byType(PlayModeScreen, skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('all home entries ignore covered and disposed callbacks: '
        '$language', (tester) async {
      final observer = Pushes();
      await pumpHome(tester, language, observer: observer);
      final actions = homeActions(tester);
      expect(actions, hasLength(18));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('home-cover')),
        ),
      );
      await advance(tester);
      final count = observer.count;
      for (final action in actions) {
        action();
      }
      await advance(tester);
      expect(observer.count, count);
      expect(find.text('home-cover'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      for (var index = 0; index < actions.length; index++) {
        expect(actions[index], returnsNormally, reason: 'entry $index');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('home press feedback ignores disposed controls: $language', (
      tester,
    ) async {
      await pumpHome(tester, language);
      final highlights =
          tester
              .widgetList<InkWell>(find.byType(InkWell))
              .map((widget) => widget.onHighlightChanged)
              .whereType<ValueChanged<bool>>()
              .toList();
      expect(highlights, hasLength(7));
      await tester.pumpWidget(const SizedBox());
      for (var index = 0; index < highlights.length; index++) {
        expect(
          () => highlights[index](true),
          returnsNormally,
          reason: 'highlight $index',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('home entries reject departed accounts before next frame: tr/en', (
    tester,
  ) async {
    // Keep the process-wide store in one test zone across both account changes.
    for (final language in ['tr', 'en']) {
      await tester.runAsync(
        () => GameStore.instance.bindAccount('home-owner-$language'),
      );
      final observer = Pushes();
      await pumpHome(tester, language, observer: observer);
      final actions = homeActions(tester);
      expect(actions, hasLength(18));
      final oldRevision = GameStore.instance.accountBindingRevision;
      await tester.runAsync(
        () => GameStore.instance.bindAccount('home-next-$language'),
      );
      expect(
        GameStore.instance.accountBindingRevision,
        greaterThan(oldRevision),
      );
      final count = observer.count;
      for (final action in actions) {
        action();
      }
      expect(observer.count, count, reason: language);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    }
  });
}

List<VoidCallback> homeActions(WidgetTester tester) =>
    tester
        .widgetList<InkWell>(find.byType(InkWell))
        .map((widget) => widget.onTap)
        .whereType<VoidCallback>()
        .toList();

Future<void> advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> pumpHome(
  WidgetTester tester,
  String language, {
  Pushes? observer,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  LunoSettings.instance.language =
      language == 'en'
          ? LunoSettings.languageEnglish
          : LunoSettings.languageTurkish;
  final app =
      shell(HomeScreen(key: UniqueKey()), language: language) as MaterialApp;
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: app.theme,
      locale: app.locale,
      supportedLocales: app.supportedLocales,
      localizationsDelegates: app.localizationsDelegates,
      builder: app.builder,
      home: app.home,
      navigatorObservers: observer == null ? [] : [observer],
    ),
  );
  await tester.pump();
}
