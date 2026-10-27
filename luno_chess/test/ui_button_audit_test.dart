import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    store.data = PlayerData.initial();
    store.loaded = true;
    store.hasChosenUsername = true;
    store.hasCompletedTutorial = true;
    store.tutorialStep = 0;
    LunoSettings.instance.language = LunoSettings.languageTurkish;
    LunoSettings.instance.effectsLevel = 2;
    LunoSettings.instance.musicLevel = 2;
    LunoSettings.instance.vibrationEnabled = true;
  });

  testWidgets('ana menüdeki her kısayol ve alt menü gerçek ekrana açılır', (
    tester,
  ) async {
    GameStore.instance.firstSessionMatchesStarted = 2;
    expect(GameStore.instance.needsFirstSessionMatch, isFalse);
    await _pump(tester, const HomeScreen());

    final quickLinks = <String, Type>{
      'Luno Pass': PassScreen,
      'Arkadaş': FriendsScreen,
      'Görevler': MissionsScreen,
      'Sıralama': RankingScreen,
      'Rehber': TutorialScreen,
      'Ayarlar': SettingsScreen,
    };
    for (final entry in quickLinks.entries) {
      await _pump(tester, const HomeScreen());
      await _tapText(tester, entry.key.toUpperCase());
      await _advance(tester);
      expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
    }

    final bottomNav = <String, Type>{
      'Mağaza': ShopScreen,
      'Koleksiyon': CollectionScreen,
      'Savaş': PlayModeScreen,
      'Sezon': SeasonScreen,
      'Profil': ProfileScreen,
    };
    for (final entry in bottomNav.entries) {
      await _pump(tester, const HomeScreen());
      await _tapText(tester, entry.key.toUpperCase());
      await _advance(tester);
      expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
    }

    await _pump(tester, const HomeScreen());
    await _tapText(tester, 'MEVCUT ARENA');
    await _advance(tester);
    expect(find.byType(ArenasScreen), findsOneWidget);
  });

  testWidgets('koleksiyon hub içindeki dört CTA doğru alt ekrana açılır', (
    tester,
  ) async {
    final entries = <String, Type>{
      'DESTE': BattleDeckScreen,
      'KARTLAR': BattleDeckScreen,
      'TAŞ KOSTÜMLERİ': PieceCostumeScreen,
      'EMOJİLER': EmojiCollectionScreen,
    };
    for (final entry in entries.entries) {
      await _pump(tester, const CollectionScreen());
      await tester.ensureVisible(find.text(entry.key));
      await _tapText(tester, entry.key);
      await _advance(tester);
      expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('savaş modu CTAları AI, online ve yerel akışa bağlanır', (
    tester,
  ) async {
    await _pump(tester, const PlayModeScreen());

    await tester.scrollUntilVisible(
      find.text('YAPAY ZEKÂYA KARŞI'),
      250,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await _tapText(tester, 'YAPAY ZEKÂYA KARŞI');
    await _advance(tester);
    expect(find.byType(DifficultyScreen), findsOneWidget);

    await _pump(tester, const PlayModeScreen());
    await tester.scrollUntilVisible(
      find.text('ARKADAŞINLA OYNA'),
      250,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await _tapText(tester, 'ARKADAŞINLA OYNA');
    await _advance(tester);
    expect(find.byType(FriendlyOnlineScreen), findsOneWidget);

    await _pump(tester, const PlayModeScreen());
    await tester.scrollUntilVisible(
      find.text('SIRALI MAÇ'),
      250,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    final rankedTile =
        find
            .ancestor(
              of: find.text('SIRALI MAÇ'),
              matching: find.byType(InkWell),
            )
            .first;
    final rankedTap = tester.widget<InkWell>(rankedTile).onTap!;
    rankedTap();
    rankedTap();
    await _advance(tester);
    expect(find.byType(OnlineHubScreen), findsOneWidget);
    expect(find.byType(OnlineHubScreen, skipOffstage: false), findsOneWidget);
    Navigator.of(tester.element(find.byType(OnlineHubScreen))).pop();
    await _advance(tester);
    expect(find.byType(PlayModeScreen), findsOneWidget);

    await _pump(tester, const PlayModeScreen());
    rankedTap();
    await tester.pump();
    expect(find.byType(OnlineHubScreen), findsNothing);
    await tester.scrollUntilVisible(
      find.text('YÜZ YÜZE OYNA'),
      250,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.ensureVisible(find.text('YÜZ YÜZE OYNA'));
    await _advance(tester);
    await tester.tap(find.text('YÜZ YÜZE OYNA'));
    await _advance(tester);
    expect(find.text('SÜRE SEÇ'), findsOneWidget);
    await tester.tap(find.text('5 dakika / oyuncu'));
    await _advance(tester);
    expect(find.byType(BattleV1Screen), findsOneWidget);
  });

  testWidgets('kart eylem menüsü detay ve kapat CTAlarını çalıştırır', (
    tester,
  ) async {
    await _pump(tester, const CardCollectionScreen());
    final firstOwned = kStarterOwned.first;
    final cardName = cardForOwned(firstOwned, 1).name;
    await tester.ensureVisible(find.text(cardName));
    await _tapText(tester, cardName);
    await _advance(tester);
    expect(find.text('Kart detayları'), findsOneWidget);

    await tester.ensureVisible(find.text('Kart detayları'));
    await tester.tap(find.text('Kart detayları'));
    await tester.pump();
    expect(find.text('KAPAT'), findsOneWidget);
    await tester.tap(find.text('KAPAT'));
    await _advance(tester);
    expect(find.text('Kart detayları'), findsNothing);
  });

  testWidgets('maç menüsü geri, iptal ve teslim onayı akışlarını kapatır', (
    tester,
  ) async {
    await _pump(tester, GameScreen(level: aiLevels.first));
    await tester.tap(find.byTooltip('Maç menüsü'));
    await _advance(tester);
    expect(find.text('Menüye dön'), findsOneWidget);

    await tester.tap(find.text('Menüye dön'));
    await _advance(tester);
    expect(find.text('Maçtan çık?'), findsOneWidget);
    await tester.tap(find.text('KAL'));
    await _advance(tester);
    expect(find.text('Maçtan çık?'), findsNothing);

    await tester.tap(find.byTooltip('Maç menüsü'));
    await _advance(tester);
    await tester.tap(find.text('Teslim ol'));
    await _advance(tester);
    expect(find.text('Teslim ol?'), findsOneWidget);
    await tester.tap(find.text('VAZGEÇ'));
    await _advance(tester);
    expect(find.text('Teslim ol?'), findsNothing);
  });

  testWidgets(
    'profil düzenle ve ayarlar ekranlarının CTAları kapanır veya açılır',
    (tester) async {
      await _pump(tester, const ProfileScreen());
      await tester.tap(find.byTooltip('Profili düzenle'));
      await _advance(tester);
      expect(find.byType(EditProfileScreen), findsOneWidget);

      await _pump(tester, const SettingsScreen());
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pump();
      expect(find.text(LunoSettings.languageEnglish), findsWidgets);

      await tester.tap(find.text('English').last);
      await tester.pump();
      expect(LunoSettings.instance.language, LunoSettings.languageEnglish);
    },
  );
}

Future<void> _tapText(WidgetTester tester, String value) async {
  final text = find.text(value);
  final inkWell = find.ancestor(of: text, matching: find.byType(InkWell));
  if (inkWell.evaluate().isNotEmpty) {
    await tester.ensureVisible(inkWell.last);
    await tester.pumpAndSettle();
    await tester.tap(inkWell.last);
  } else {
    await tester.tap(text.first);
  }
}

Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(key: UniqueKey(), theme: LunoTheme.dark, home: screen),
  );
  await tester.pump(const Duration(milliseconds: 120));
}
