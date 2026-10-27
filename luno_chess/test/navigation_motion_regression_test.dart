import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/navigation/luno_route.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('Route preserves state and result; reduced=$reduced', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: child!,
              ),
          home: StatefulBuilder(
            builder:
                (context, update) => Scaffold(
                  body: TextButton(
                    onPressed: () => update(() => count++),
                    child: Text('Count $count'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Count 0'));
      await tester.pump();
      final result = navigator.currentState!.push(
        lunoRoute<int>(
          const Scaffold(body: Center(child: Text('Destination'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final interim = tester.getCenter(find.text('Destination'));
      await tester.pumpAndSettle();
      final settled = tester.getCenter(find.text('Destination'));
      if (reduced) {
        expect(interim, settled);
      } else {
        expect(interim.dx, greaterThan(settled.dx));
      }
      navigator.currentState!.pop(7);
      await tester.pumpAndSettle();
      expect(await result, 7);
      expect(find.text('Count 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 5; i++) {
        navigator.currentState!.push(
          lunoRoute<void>(const Scaffold(body: Text('Temporary'))),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('Temporary'), findsNothing);
        expect(find.text('Count 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
