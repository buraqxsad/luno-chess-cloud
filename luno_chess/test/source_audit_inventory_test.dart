import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/i18n/luno_text.dart' as game;
import '../tool/source_string_audit.dart' as audit;

void main() {
  test(
    'inventory production copy through the Dart AST; no untranslated visible candidate',
    () {
      audit.main();
      final entries =
          jsonDecode(
                File(
                  'qa/source-audit/string-inventory.json',
                ).readAsStringSync(),
              )
              as List;
      expect(entries.where((e) => e['status'] == 'VISIBLE_CANDIDATE'), isEmpty);
      expect(
        entries.where((e) => e['status'] == 'NATIVE_METADATA_CANDIDATE'),
        isEmpty,
      );
    },
  );
  const tr = LunoLocalizations(Locale('tr')),
      en = LunoLocalizations(Locale('en'));
  for (final entry
      in {
        'ODA KODU OLUŞTUR · 10 DK': 'CREATE ROOM · 10 MIN',
        '5 dakika / oyuncu': '5 minutes / player',
        'LunoPlayer seninle oynamak istiyor.':
            'LunoPlayer wants to play with you.',
        '+5.000 altın hesabına eklendi.':
            '+5.000 gold was added to your account.',
        '600  ·  PREMIUM AKTİFLEŞTİR': '600  ·  ACTIVATE PREMIUM',
        '450 kupa': '450 trophies',
        '6 gün 4 saat kaldı': '6d 4h remaining',
        'LunoPlayer artık arkadaş listende olmayacak.':
            'LunoPlayer will be removed from your friends.',
        '+120 altın': '+120 gold',
        '18 elmas': '18 gems',
        '150 altın + 20 Pass XP': '150 gold + 20 Pass XP',
        '600 · PREMIUM AL': '600 · GET PREMIUM',
        'Gizli hedef · hedef 3': 'Hidden objective · target 3',
      }.entries) {
    test('central dynamic copy preserves data: ${entry.key}', () {
      expect(tr.translate(entry.key), entry.key);
      expect(en.translate(entry.key), entry.value);
    });
  }
  for (final language in ['tr', 'en']) {
    for (final value in ['HAKKINDA', 'ORAN', 'Bir maç oyna.']) {
      testWidgets('user content remains verbatim in $language: $value', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: LunoLocalizations.supportedLocales,
            localizationsDelegates: const [
              LunoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: game.Text(value, localize: false, semanticsLabel: value),
          ),
        );
        expect(find.text(value), findsOneWidget);
        expect(tester.widget<Text>(find.byType(Text)).semanticsLabel, value);
      });
    }
  }
}
