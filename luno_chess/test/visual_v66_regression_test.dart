import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0]) {
      testWidgets('Ranked states fit $language at $width', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final locale = Locale(language);
        final copy = LunoLocalizations(locale);
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            locale: locale,
            supportedLocales: LunoLocalizations.supportedLocales,
            localizationsDelegates: const [
              LunoLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.5),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
            home: const OnlineHubScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(copy.translate('Bağlantı gerekli')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final dynamic state = tester.state(find.byType(OnlineHubScreen));
        for (final status in [
          'Rakip aranıyor',
          'Eşleşme iptal ediliyor',
          'Bağlantı yenileniyor',
          'Eşleşme araması sürüyor',
        ]) {
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .jumpTo(0);
          state.setState(() {
            state.waiting = true;
            state.joinedAt = DateTime.now();
            state.status = status;
            state.error =
                'İptal doğrulanamadı. Kuyruk korunuyor; durum yeniden denetleniyor.';
          });
          await tester.pump();
          expect(find.text(copy.translate(status)), findsOneWidget);
          final cancel = find.text(copy.translate('ARAMAYI İPTAL ET'));
          await tester.scrollUntilVisible(cancel, 160);
          await tester.pump();
          expect(cancel, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        state.waiting = false;
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
