import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/card_info.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final details in [false, true]) {
    testWidgets(
      'covered card ${details ? 'details' : 'action'} callback is inert',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        late BuildContext page;
        var changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: LunoTheme.dark,
            home: Builder(
              builder: (context) {
                page = context;
                return const Scaffold();
              },
            ),
          ),
        );
        if (details) {
          showCardInfo(page, 'barbarian');
        } else {
          showCardActionMenu(
            page,
            'barbarian',
            owned: true,
            onAddToDeck: () => changes++,
          );
        }
        await tester.pumpAndSettle();
        final action =
            tester
                .widget<LunoButton>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is LunoButton &&
                        w.label == (details ? 'KAPAT' : 'Desteye ekle'),
                  ),
                )
                .onPressed!;
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other screen')),
          ),
        );
        await tester.pumpAndSettle();
        action();
        await tester.pumpAndSettle();
        expect(find.text('Other screen'), findsOneWidget);
        expect(changes, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        action();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      testWidgets(
        '$language card details and close remain reachable at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late BuildContext page;
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
              home: Builder(
                builder: (context) {
                  page = context;
                  return const Scaffold();
                },
              ),
            ),
          );
          var changes = 0;
          final cardsToCheck =
              size == const Size(320, 568) ? kCards.keys : ['barbarian'];
          for (final key in cardsToCheck) {
            for (final owned in [false, true]) {
              showCardActionMenu(
                page,
                key,
                owned: owned,
                onAddToDeck: () => changes++,
              );
              await tester.pumpAndSettle();
              final closeSheet = find.byTooltip(
                language == 'en' ? 'CLOSE' : 'KAPAT',
              );
              await tester.ensureVisible(closeSheet);
              expect(closeSheet.hitTestable(), findsOneWidget);
              expect(
                tester.getSize(closeSheet).width,
                greaterThanOrEqualTo(48),
              );
              final addButton = find.byWidgetPredicate(
                (w) => w is LunoButton && w.label == 'Desteye ekle',
              );
              expect(addButton, owned ? findsOneWidget : findsNothing);
              final staleAdd =
                  owned ? tester.widget<LunoButton>(addButton).onPressed : null;
              await tester.tap(closeSheet);
              await tester.pumpAndSettle();
              staleAdd?.call();
              await tester.pump();
              expect(changes, 0);
              expect(find.byType(BottomSheet), findsNothing);
              expect(tester.takeException(), isNull, reason: key);
            }
          }
          showCardActionMenu(
            page,
            'barbarian',
            owned: true,
            onAddToDeck: () {},
          );
          await tester.pumpAndSettle();
          final details = find.text(
            language == 'en' ? 'Card details' : 'Kart detayları',
          );
          await tester.ensureVisible(details);
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          final close = find.text(language == 'en' ? 'CLOSE' : 'KAPAT');
          await tester.ensureVisible(close);
          expect(close.hitTestable(), findsOneWidget);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
          if (size == const Size(320, 568)) {
            final strings = LunoLocalizations(Locale(language));
            for (final card in kCards.values) {
              showCardInfo(page, card.key);
              await tester.pumpAndSettle();
              final description = find.text(strings.translate(card.desc));
              await tester.ensureVisible(description);
              await tester.pump();
              expect(description, findsOneWidget, reason: card.key);
              await tester.ensureVisible(close);
              expect(close.hitTestable(), findsOneWidget, reason: card.key);
              await tester.tap(close);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: card.key);
            }
          }
        },
      );
    }
  }
}
