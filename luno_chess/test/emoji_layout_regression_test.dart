import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
      testWidgets(
        '$language emoji artwork remains visible at $size with large text',
        (tester) async {
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
              locale: Locale(language),
              supportedLocales: LunoLocalizations.supportedLocales,
              localizationsDelegates: const [
                LunoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: LunoTheme.dark,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
              home: const EmojiCollectionScreen(),
            ),
          );
          await tester.pump();
          expect(
            find.text(language == 'en' ? '0 / 4 selected' : '0 / 4 seçili'),
            findsOneWidget,
          );
          final art = find.byWidgetPredicate(
            (w) => w is LunoArt && w.path == LunoAssets.emoji('smile'),
          );
          await tester.scrollUntilVisible(
            art,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          expect(tester.getSize(art).height, greaterThanOrEqualTo(64));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
