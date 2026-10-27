import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/card_level_sheet.dart';

void main() {
  testWidgets('Covered and disposed level callbacks cannot pop another route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: LunoTheme.dark,
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final held = kCards.values.firstWhere((c) => c.upgradeable && c.level == 3);
    final result = showCardLevelSheet(host, held, 999);
    await tester.pumpAndSettle();
    final action =
        tester
            .widgetList<InkWell>(find.byType(InkWell))
            .firstWhere((w) => w.onTap != null)
            .onTap!;
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covering route')),
      ),
    );
    await tester.pumpAndSettle();
    action();
    await tester.pumpAndSettle();
    expect(find.text('Covering route'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    action();
    action();
    await tester.pumpAndSettle();
    expect(await result, familyKeyAtLevel(held.family, 1));
    action();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Every upgraded family fits large text and returns selected level',
    (tester) async {
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
      for (final held in kCards.values.where(
        (c) => c.upgradeable && c.level == 3,
      )) {
        final result = showCardLevelSheet(host, held, 999);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: held.name);
        final target = find.text('Sv3 · ${held.name}');
        await tester.scrollUntilVisible(target, 200);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(await result, familyKeyAtLevel(held.family, 3));
        expect(find.text('SEVİYE SEÇ'), findsNothing);
      }
    },
  );

  testWidgets('Unaffordable levels cannot be selected', (tester) async {
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
    final held = kCards.values.firstWhere((c) => c.upgradeable && c.level == 3);
    final result = showCardLevelSheet(host, held, 0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<InkWell>(find.byType(InkWell))
          .every((w) => w.onTap == null),
      isTrue,
    );
    Navigator.of(tester.element(find.text('SEVİYE SEÇ'))).pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
