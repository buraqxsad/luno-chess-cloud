import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_ui/draw_motion.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'battle_deck_account_test.dart' show response;
import 'battle_draw_source_audit_test.dart' show battleScreenForAudit;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey;
import 'battle_ui/fixtures.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_ui/visual_test.dart' show renderBattle, captureKey;
import '../tool/source_string_audit.dart' show turkishCoreCopy;
import 'online_request_session_test.dart' show TestAuth;

Future<LunoOnlineService> fixtureOnline() async {
  final online = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: TestAuth(),
    appCheck: () async => 'local-test-only',
    databaseRead: (_) async => {},
    friendRequestStream: const Stream.empty(),
    matchInviteStream: const Stream.empty(),
    client: MockClient(
      (request) async => http.Response(
        jsonEncode({
          'ok': true,
          'state': {
            'rewards': {
              'missions': {
                'daily': [
                  {
                    'id': 'd1',
                    'title': 'Tahtaya çık',
                    'description': 'Bir maç oyna.',
                    'target': 1,
                    'progress': 0,
                    'claimed': false,
                    'reward': {'gold': 100},
                  },
                  {
                    'id': 'd2',
                    'title': 'Zafer zamanı',
                    'description': 'Bir maç kazan.',
                    'target': 1,
                    'progress': 1,
                    'claimed': false,
                    'reward': {'gold': 150},
                    'passXp': 20,
                  },
                ],
                'weekly': [],
                'special': [],
              },
              'periods': {},
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
  await online.start();
  expect(online.isOnline, true);
  expect((await online.getPlayerState())['ok'], true);
  return online;
}

Future<void> prepareImages(WidgetTester tester, Key key) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(key));
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
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
  await tester.pump();
}

Future<void> screenshot(
  WidgetTester tester,
  String name, {
  Key key = boundaryKey,
}) async {
  if (name.endsWith('-en')) checkEnglish(tester, name);
  if (name.endsWith('-tr')) checkTurkish(tester, name);
  expect(tester.takeException(), isNull, reason: name);
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(key)).renderObject! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('qa/source-audit/screens');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    final assets = <String>{};
    void collect(ImageProvider provider) {
      if (provider is ResizeImage) collect(provider.imageProvider);
      if (provider is AssetImage) assets.add(provider.assetName);
    }

    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      collect(widget.image);
    }
    for (final widget in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        collect(decoration.image!.image);
      }
    }
    await File(
      '${directory.path}/$name.assets.json',
    ).writeAsString(jsonEncode(assets.toList()..sort()));
    image.dispose();
  });
}

void checkEnglish(WidgetTester tester, String name) {
  final copy = <String>[];
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    final text = widget.text.toPlainText();
    // Language choices and user-supplied names are data, not an English fallback.
    if (text == 'Türkçe' ||
        text == GameStore.instance.data.username ||
        text == GameStore.instance.data.bio) {
      continue;
    }
    if (turkishCoreCopy.hasMatch(text)) copy.add(text);
  }
  expect(copy, isEmpty, reason: '$name contains Turkish core UI: $copy');
}

void checkTurkish(WidgetTester tester, String name) {
  final copy = <String>[];
  final englishCoreCopy = RegExp(
    r'\b(SETTINGS|MISSIONS|SHOP|PROFILE|COLLECTION|CURRENT ARENA|YOUR BOARD IS READY|WIN RATE|COMING SOON|From deck|Opponent Cards|Total matches|Cards played)\b',
  );
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    final text = widget.text.toPlainText();
    if (text == 'English' ||
        text == GameStore.instance.data.username ||
        text == GameStore.instance.data.bio) {
      continue;
    }
    if (englishCoreCopy.hasMatch(text)) copy.add(text);
  }
  expect(copy, isEmpty, reason: '$name contains English core UI: $copy');
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    final store = GameStore.instance;
    store.data =
        PlayerData.initial()
          ..username = 'LunoPlayer'
          ..bio = 'Every move matters.'
          ..gold = 12345
          ..gems = 250
          ..trophies = 450;
    store.loaded = true;
    store.hasCompletedTutorial = true;
    store.hasChosenUsername = true;
    store.practiceStage = null;
  });
  for (final language in ['tr', 'en']) {
    final screens = <String, Widget Function(LunoOnlineService)>{
      'startup': (_) => const Scaffold(body: LunoLoadingArtwork()),
      'home': (_) => const HomeScreen(),
      'play': (_) => const PlayModeScreen(),
      'collection':
          (_) => CollectionScreen(deckLoadOverride: () async => response()),
      'profile': (_) => const ProfileScreen(),
      'missions': (online) => MissionsScreen(online: online),
      'shop':
          (online) =>
              ShopScreen(online: online, playerStore: GameStore.instance),
      'settings': (_) => const SettingsScreen(),
      'friends-empty': (online) => FriendsScreen(online: online),
    };
    for (final entry in screens.entries) {
      testWidgets('source audit ${entry.key} $language', (tester) async {
        final online = await fixtureOnline();
        addTearDown(online.dispose);
        LunoSettings.instance.language =
            language == 'en'
                ? LunoSettings.languageEnglish
                : LunoSettings.languageTurkish;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(entry.value(online), language: language, reduced: true),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await prepareImages(tester, boundaryKey);
        await tester.pump(const Duration(milliseconds: 500));
        if (entry.key == 'missions') {
          final dynamic state = tester.state(find.byType(MissionsScreen));
          expect(state.error, isNull);
          expect(state.missions['daily'], hasLength(2));
        }
        if (language == 'en') checkEnglish(tester, entry.key);
        if (entry.key == 'home') {
          final labels =
              tester
                  .widgetList<Semantics>(find.byType(Semantics))
                  .map((widget) => widget.properties.label)
                  .toList();
          expect(
            labels,
            containsAll(
              language == 'en'
                  ? ['Collection', 'Season', 'Profile']
                  : ['Koleksiyon', 'Sezon', 'Profil'],
            ),
          );
          for (final label
              in language == 'en'
                  ? ['COLLECTION', 'SEASON', 'PROFILE']
                  : ['KOLEKSIYON', 'SEZON', 'PROFIL']) {
            expect(find.text(label), findsOneWidget);
          }
        }
        if (entry.key == 'play') {
          expect(
            find.text(
              language == 'en' ? 'PRACTICE · UNRANKED' : 'ANTRENMAN · KUPASIZ',
            ),
            findsOneWidget,
          );
          expect(
            find.text(language == 'en' ? 'ONLINE · INVITE' : 'ONLINE · DAVET'),
            findsOneWidget,
          );
        }
        await screenshot(tester, '${entry.key}-$language');
        if (entry.key == 'shop') {
          await tester.scrollUntilVisible(
            find.text(language == 'en' ? 'GOLD & GEMS' : 'ALTIN VE ELMAS'),
            450,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.textContaining('₺'), findsNothing);
          final balance = GameStore.instance.data.gems;
          final goldBalance = GameStore.instance.data.gold;
          for (final id in [
            'luno_gold_1000',
            'luno_gold_5500',
            'luno_gold_15000',
            'luno_gem_80',
            'luno_gem_500',
            'luno_gem_1500',
          ]) {
            final button = find.byKey(ValueKey('store-product-$id'));
            await tester.scrollUntilVisible(
              button,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              tester.widget<FilledButton>(button).onPressed,
              isNull,
              reason: 'No confirmed Play product means no fake purchase flow.',
            );
            expect(
              find.descendant(
                of: button,
                matching: find.text(
                  language == 'en' ? 'Unavailable' : 'Kullanılamıyor',
                ),
              ),
              findsOneWidget,
            );
            await tester.tap(button);
            await tester.pump();
          }
          expect(GameStore.instance.data.gems, balance);
          expect(GameStore.instance.data.gold, goldBalance);
          if (language == 'en') checkEnglish(tester, 'shop-gems');
          await screenshot(tester, 'shop-gems-$language');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
      'source audit battle initial, public arsenal and result $language',
      (tester) async {
        await renderBattle(
          tester,
          language: language,
          state: battleFixture(firstTurn: true),
        );
        await screenshot(tester, 'battle-initial-$language', key: captureKey);
        await tester.tap(find.byKey(const ValueKey('open-arsenal')));
        await tester.pumpAndSettle();
        await prepareImages(tester, captureKey);
        expect(
          find.textContaining(
            language == 'tr' ? 'Rakibin Kartları' : 'Opponent Cards',
          ),
          findsWidgets,
        );
        if (language == 'en') checkEnglish(tester, 'opponent-public-cards');
        await screenshot(
          tester,
          'opponent-public-cards-$language',
          key: captureKey,
        );
        await tester.pumpWidget(const SizedBox());
        final base = battleFixture(), draft = RuleDraft(base.rules);
        draft.phase = BattlePhase.terminal;
        draft.terminal = const TerminalState(
          'checkmate',
          winner: PieceColor.white,
        );
        await renderBattle(
          tester,
          language: language,
          state: AuthoritativeBattleState(draft.freeze(), base.hidden),
        );
        if (language == 'en') checkEnglish(tester, 'result');
        await screenshot(tester, 'result-$language', key: captureKey);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets('source audit own and secret-free opponent draw $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = Harness(firstTurn: true);
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(
        shell(battleScreenForAudit(harness), language: language),
      );
      await prepareImages(tester, boundaryKey);
      await tester.pump(const Duration(seconds: 1));
      await harness.controller.submit(
        harness.controller.legalActions.whereType<ChessMoveAction>().first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await screenshot(tester, 'own-draw-mid-$language');
      await tester.pump(const Duration(milliseconds: 400));
      await screenshot(tester, 'battle-after-draw-$language');
      final side = harness.state.rules.board.turn;
      final view = PlayerView(
        harness.state.rules,
        side,
        harness.state.hidden.hands[side]!,
        harness.state.hidden.knowledge[side]!,
      );
      final move =
          BattleRulesCore.legalActions(view).whereType<ChessMoveAction>().first;
      harness.state = DeckManager.apply(harness.state, move);
      harness.version++;
      await harness.controller.reconnect(synchronization: false);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('opponent-closed-draw')),
        findsOneWidget,
      );
      expect(find.byType(BattleClosedCard), findsOneWidget);
      await screenshot(tester, 'opponent-draw-$language');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('opponent-closed-draw')), findsNothing);
      await harness.controller.reconnect();
      await tester.pump();
      expect(find.byType(BattleClosedCard), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
