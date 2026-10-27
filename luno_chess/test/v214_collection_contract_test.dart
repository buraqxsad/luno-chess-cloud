import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final language in ['tr', 'en']) {
    testWidgets('V1 collection catalog is not legacy ownership: $language', (
      tester,
    ) async {
      final store = GameStore.instance;
      final originalData = store.data;
      final originalLanguage = LunoSettings.instance.language;
      store.data = PlayerData.initial();
      store.data.gold = 7890;
      store.data.gems = 321;
      store.data.cardLevel[store.data.ownedCards.first] = 3;
      final before = jsonEncode(store.data.toJson());
      addTearDown(() {
        store.data = originalData;
        LunoSettings.instance.language = originalLanguage;
      });
      LunoSettings.instance.language = language;
      await tester.pumpWidget(
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
          home: const CollectionScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          language == 'en' ? '24 battle abilities' : '24 savaş yeteneği',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('/29'), findsNothing);
      expect(find.textContaining('KOLEKSİYON PUANI'), findsNothing);
      expect(find.textContaining('COLLECTION SCORE'), findsNothing);
      expect(jsonEncode(store.data.toJson()), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('old collection score remains labeled historical, not V1 power', (
    tester,
  ) async {
    final store = GameStore.instance;
    final originalData = store.data;
    final originalLanguage = LunoSettings.instance.language;
    store.data = PlayerData.initial();
    LunoSettings.instance.language = 'en';
    final before = jsonEncode(store.data.toJson());
    addTearDown(() {
      store.data = originalData;
      LunoSettings.instance.language = originalLanguage;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [LunoLocalizations.delegate],
        home: const CollectionBrowserScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LEGACY CARD ARCHIVE'), findsOneWidget);
    expect(find.textContaining('/29 archived'), findsOneWidget);
    expect(find.textContaining('historical points'), findsOneWidget);
    expect(jsonEncode(store.data.toJson()), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public player details ignore legacy collection power and unsafe bio',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: PlayerDetailsScreen.fromPlayer({
            'username': 'luno_player',
            'country': 'TR',
            'trophies': 50,
            'wins': 2,
            'gamesPlayed': 3,
            'collectionScore': 987654321,
            'bio': 'unsafe\u202Ebiography',
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('987654321'), findsNothing);
      expect(find.textContaining('KOLEKSİYON PUANI'), findsNothing);
      expect(find.textContaining('COLLECTION SCORE'), findsNothing);
      expect(find.textContaining('unsafe'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
