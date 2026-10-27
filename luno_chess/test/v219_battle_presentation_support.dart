import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import '../tool/battle_fixture_support.dart';

({AuthoritativeBattleState before, AuthoritativeBattleState after}) v219Cast(
  CardId card,
) {
  final contract =
      jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
          as Map;
  final fixture = (contract['fixtures'] as List).cast<Map>().singleWhere(
    (entry) => entry['fixtureId'] == 'card-${card.wire}',
  );
  final before = fixtureInitial(fixture);
  final action = BattleAction.fromJson(
    ((fixture['steps'] as List).first as Map)['action'] as Map,
  );
  return (before: before, after: DeckManager.apply(before, action));
}

Future<void> loadV219PresentationFonts() async {
  for (final entry
      in {
        'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
        'Cinzel': 'assets/fonts/cinzel-latin.ttf',
        'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
}

Widget v219PresentationShell(
  Widget child, {
  bool reduced = false,
  bool visible = true,
}) => MaterialApp(
  theme: LunoTheme.dark,
  locale: const Locale('en'),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: TickerMode(enabled: visible, child: child!),
      ),
  home: Scaffold(body: child),
);
