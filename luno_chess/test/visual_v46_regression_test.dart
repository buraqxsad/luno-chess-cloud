import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/card_info.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  testWidgets('All card details fit small screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
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
    for (final key in kCards.keys) {
      showCardInfo(host, key);
      showCardInfo(host, key);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: key);
      expect(find.byType(AlertDialog), findsOneWidget);
      final close = tester.widget<LunoButton>(
        find.byWidgetPredicate((w) => w is LunoButton && w.label == 'KAPAT'),
      );
      close.onPressed!();
      close.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull, reason: key);
    }
  });

  testWidgets('Card action callback can run only once', (tester) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold();
          },
        ),
      ),
    );
    var calls = 0;
    showCardActionMenu(
      host,
      kCards.keys.first,
      owned: true,
      onAddToDeck: () => calls++,
    );
    await tester.pumpAndSettle();
    final action =
        tester
            .widget<LunoButton>(
              find.byWidgetPredicate(
                (w) => w is LunoButton && w.label == 'Desteye ekle',
              ),
            )
            .onPressed!;
    action();
    action();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
