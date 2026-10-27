import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/deck_account.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

Map<String, dynamic> response({
  List<String>? deck,
  List<String>? owned,
  bool available = true,
}) => {
  'ok': true,
  'protocolVersion': 'LUNO_BATTLE_V1',
  'available': available,
  'deck': deck ?? starterDeck.map((c) => c.wire).toList(),
  'entitlements': owned ?? [...starterDeck.map((c) => c.wire), 'fog'],
};

Widget app(Widget child, String language, {double textScale = 1}) =>
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
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: child,
    );

Finder card(CardId id) => find.byWidgetPredicate(
  (widget) => widget is BattleCatalogCard && widget.card == id,
);

void main() {
  test(
    'battle deck response rejects forged, duplicate, unknown and locked cards',
    () {
      expect(BattleDeckAccount.fromResponse(response()).deck, starterDeck);
      expect(
        () => BattleDeckAccount.fromResponse(
          response(deck: [...starterDeck.take(9).map((c) => c.wire), 'mine']),
        ),
        throwsFormatException,
      );
      expect(
        () => BattleDeckAccount.fromResponse(
          response(deck: [...starterDeck.take(9).map((c) => c.wire), 'radar']),
        ),
        throwsFormatException,
      );
      expect(
        () => BattleDeckAccount.fromResponse(response(owned: ['radar', 'fog'])),
        throwsFormatException,
      );
      expect(
        () => BattleDeckAccount.fromResponse(
          response(owned: [...starterDeck.map((c) => c.wire), 'bogus']),
        ),
        throwsFormatException,
      );
    },
  );

  for (final language in ['tr', 'en']) {
    testWidgets('owned card replaces starter and saves exactly ten $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<String>? saved;
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            loadOverride: () async => response(),
            saveOverride: (deck) async {
              saved = [...deck];
              return {'ok': true, 'deck': deck};
            },
          ),
          language,
        ),
      );
      await tester.pump();
      final mainScroll = find.byType(Scrollable).first;
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('selected-deck-grid'))),
        alignment: .2,
      );
      final selectedCard = find.byKey(const ValueKey('deck-slot-purify'));
      await Scrollable.ensureVisible(
        tester.element(selectedCard),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(selectedCard);
      await tester.pump();
      expect(saved, isNull);
      await tester.scrollUntilVisible(
        card(CardId.fog),
        240,
        scrollable: mainScroll,
      );
      tester.widget<BattleCatalogCard>(card(CardId.fog)).onTap!();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text(language == 'tr' ? 'DESTENİ KAYDET' : 'SAVE DECK'),
        -240,
        scrollable: mainScroll,
      );
      final button = tester
          .widgetList<LunoButton>(find.byType(LunoButton))
          .singleWhere(
            (button) =>
                button.label ==
                (language == 'tr' ? 'DESTENİ KAYDET' : 'SAVE DECK'),
          );
      expect(button.onPressed, isNotNull);
      button.onPressed!();
      await tester.pump();
      expect(saved, hasLength(10));
      expect(saved, contains('fog'));
      expect(saved, isNot(contains('purify')));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'unavailable server deck is read-only and catalog stays offline',
    (tester) async {
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            loadOverride: () async => response(available: false),
            saveOverride: (_) async => throw StateError('must not save'),
          ),
          'tr',
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('Çevrimiçi savaş şu anda kapalı'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    testWidgets('selected deck fits $size at 1.8x text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          BattleDeckScreen(loadOverride: () async => response()),
          'tr',
          textScale: 1.8,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('selected-deck-grid')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('selected-deck-grid')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
