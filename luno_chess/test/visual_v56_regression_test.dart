import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final initial in [1, 3, 5, 10, 30, -1]) {
    testWidgets('Time picker selection and single dispatch, initial $initial', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final results = <int?>[];
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
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () async => results.add(
                          await showGameTimeControlPicker(
                            context,
                            initial: initial,
                          ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final selected = initial < 0 ? 5 : initial;
      final tile = find.widgetWithText(ListTile, '$selected dakika / oyuncu');
      await tester.ensureVisible(tile);
      expect(tester.widget<ListTile>(tile).selected, isTrue);
      expect(find.text('Seçili süre'), findsOneWidget);
      final choose = tester.widget<ListTile>(tile).onTap!;
      choose();
      choose();
      await tester.pumpAndSettle();
      expect(results, [selected]);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ListTile).first)).pop();
      await tester.pumpAndSettle();
      expect(results, [selected, null]);
      expect(tester.takeException(), isNull);
    });
  }
}
