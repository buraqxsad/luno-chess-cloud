import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show visualOnline;

void main() {
  setupPracticeTestAssets();
  const english = LunoLocalizations(Locale('en'));
  const copy = {
    'ARENA YOLU': 'ARENA ROAD',
    'Piyon Vadisi': 'Pawn Valley',
    'LUNO USTASI': 'LUNO MASTER',
    'LUNO KRALİYETİ': 'LUNO ROYALTY',
    'Elmas': 'Gems',
    'Seviye 2': 'Level 2',
    'Seviye 1 / 30': 'Level 1 / 30',
    'Sezon yolu tamamlandı': 'Season road complete',
    'ODA KODUYLA KATIL': 'JOIN WITH ROOM CODE',
    'MESAJLAR': 'MESSAGES',
    'Luno bildirimi': 'Luno notification',
  };
  for (final entry in copy.entries) {
    test('RC stable copy: ${entry.key}', () {
      expect(english.translate(entry.key), entry.value);
    });
  }
  for (final level in aiLevels) {
    test('RC coach name and description translate: ${level.id}', () {
      expect(english.translate(level.name), isNot(level.name));
      expect(english.translate(level.desc), isNot(level.desc));
    });
  }
  test('RC royalty display name has the correct Turkish spelling', () {
    expect(arenaForIndex(6).displayName, 'LUNO KRALİYETİ');
  });
  test('RC all content rewards use readable Turkish and English names', () {
    const expected = {
      'Neşeli Luno': 'Happy Luno',
      'Nadir Sandık': 'Rare Chest',
      'Zafer Lunosu': 'Victory Luno',
      'Efsanevi Sandık': 'Legendary Chest',
      'Osmanlı Taş Seti': 'Ottoman Piece Set',
      'Luno Kalbi': 'Luno Heart',
      'Kraliyet Sandığı': 'Royal Chest',
      'Viking Taş Seti': 'Viking Piece Set',
      'Premium Nadir Sandık': 'Premium Rare Chest',
      'Premium Luno Tepkisi': 'Premium Luno Reaction',
      'Roma Taş Seti': 'Roman Piece Set',
      'Premium Efsanevi Sandık': 'Premium Legendary Chest',
      'Ejderha Taş Seti': 'Dragon Piece Set',
      'Neon Krallık Seti': 'Neon Kingdom Set',
    };
    final rewards = [
      for (var level = 1; level <= kPassMaxLevel; level++) ...[
        passFree(level),
        passPrem(level),
      ],
    ].where((reward) => reward.kind != null);
    expect(rewards.length, expected.length);
    for (final reward in rewards) {
      expect(expected, contains(reward.name));
      expect(english.translate(reward.name!), expected[reward.name]);
    }
  });
  test('RC user-authored text is not partially translated', () {
    expect(english.translate('Seviye 2 benim adım'), 'Seviye 2 benim adım');
    expect(english.translate('Elmas_player'), 'Elmas_player');
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await GameStore.instance.bindAccount('first');
  });
  setUp(() {
    GameStore.instance.data = PlayerData.initial()..trophies = 450;
    GameStore.instance.loaded = true;
  });
  testWidgets('RC arena hero translates before composing the arena number', (
    tester,
  ) async {
    await tester.pumpWidget(shell(const ArenasScreen(), language: 'en'));
    expect(find.text('SOVEREIGN · ARENA 3'), findsOneWidget);
    expect(find.text('HÜKÜMDAR · ARENA 3'), findsNothing);
  });
  for (final language in ['tr', 'en']) {
    testWidgets('RC compact season header remains readable $language', (
      tester,
    ) async {
      final online = await visualOnline();
      addTearDown(online.dispose);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        shell(
          SeasonScreen(online: online),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final title = language == 'en' ? 'SEASON ROAD' : 'SEZON YOLU';
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(AppBar), matching: find.text(title)),
      );
      expect(paragraph.didExceedMaxLines, false, reason: title);
      if (language == 'en') {
        expect(
          find.text('Next tier at 1.000 trophies · 1d 0h remaining'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
