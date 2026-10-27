import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      testWidgets('$language all collection cards fit $size with double text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = GameStore.instance;
        final original = store.data;
        addTearDown(() => store.data = original);
        store.data = PlayerData.initial();
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
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
            home: const CardCollectionScreen(),
          ),
        );
        await tester.pump();
        for (final card in kCards.values) {
          final tile = find.byWidgetPredicate((w) {
            if (w.runtimeType.toString() != '_CardTile') return false;
            final dynamic item = w;
            return item.def.key == card.key;
          });
            tester.state<ScrollableState>(find.byType(Scrollable).first)
                .position.jumpTo(0);
            await tester.pump();
            await tester.scrollUntilVisible(tile, 250,
                scrollable: find.byType(Scrollable).first, maxScrolls: 80);
          await tester.pump();
          final art = find.descendant(
            of: tile,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is LunoArt &&
                  w.path == LunoAssets.card(card.key, card.level),
            ),
          );
          expect(tester.getSize(art).height, 96, reason: card.key);
          expect(tester.widget<LunoArt>(art).fit, BoxFit.contain);
          expect(tester.takeException(), isNull, reason: card.key);
        }
      });
    }
  }
}
