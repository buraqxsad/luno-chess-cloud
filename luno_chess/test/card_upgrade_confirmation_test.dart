import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/card_upgrade_confirmation.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      testWidgets(
        '$language upgrade confirmation fits $size and is single-use',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final navigator = GlobalKey<NavigatorState>();
          late BuildContext host;
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
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
                  host = context;
                  return const Scaffold();
                },
              ),
            ),
          );
          final result = confirmCardUpgrade(host, 'deploy', 2);
          await tester.pumpAndSettle();
          final confirm = find.text(language == 'en' ? 'UPGRADE' : 'YÜKSELT');
          await tester.ensureVisible(confirm);
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          final callback =
              tester
                  .widget<LunoButton>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is LunoButton &&
                          w.label == (language == 'en' ? 'UPGRADE' : 'YÜKSELT'),
                    ),
                  )
                  .onPressed!;
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          );
          await tester.pumpAndSettle();
          callback();
          await tester.pumpAndSettle();
          expect(find.text('Cover'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          callback();
          callback();
          await tester.pumpAndSettle();
          expect(await result, true);
          callback();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
