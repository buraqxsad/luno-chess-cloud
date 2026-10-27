import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'Chest reveal fits small screen, reduced motion $reducedMotion',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.5),
                    disableAnimations: reducedMotion,
                  ),
                  child: child!,
                ),
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (_) => ChestRevealDialog(
                                  chestId: 'rare',
                                  rewards: List.generate(
                                    8,
                                    (i) => {
                                      'type': 'gold',
                                      'name': 'Uzun isimli sandık ödülü $i',
                                      'amount': 1200 + i,
                                      'unlocked': true,
                                    },
                                  ),
                                ),
                          ),
                      child: const Text('open'),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        if (reducedMotion) {
          expect(find.text('SANDIK AÇILDI'), findsOneWidget);
        } else {
          final button = tester.widget<LunoButton>(find.byType(LunoButton));
          expect(button.label, 'HEMEN GÖSTER');
          expect(button.onPressed, isNotNull);
          await tester.tap(find.byKey(const ValueKey('chest-reveal-continue')));
          await tester.pump();
          expect(find.byType(ChestRevealDialog), findsOneWidget);
          expect(find.text('SANDIK AÇILDI'), findsOneWidget);
          expect(find.text('Koleksiyonuna eklendi.'), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('HARİKA'), 250);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('HARİKA'));
        await tester.pumpAndSettle();
        expect(find.byType(ChestRevealDialog), findsNothing);
      },
    );
  }
}
