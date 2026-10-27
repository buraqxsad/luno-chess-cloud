import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(800, 1280),
  ]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
        'chest ${size.width}x${size.height}, reduced=$reducedMotion, large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: LunoTheme.dark,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: reducedMotion,
                      padding: const EdgeInsets.only(top: 24, bottom: 24),
                    ),
                    child: child!,
                  ),
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: TextButton(
                        onPressed:
                            () => showDialog<void>(
                              context: context,
                              builder:
                                  (_) => ChestRevealDialog(
                                    chestId: 'royal',
                                    rewards: [
                                      {'type': 'gold', 'amount': 123456789},
                                      for (var i = 0; i < 10; i++)
                                        {
                                          'type': 'card',
                                          'id': 'unknown',
                                          'name':
                                              'Uzun isimli koleksiyon kartı $i',
                                          'amount': 12,
                                          'unlocked': true,
                                        },
                                      {'type': 'gems', 'amount': 987654321},
                                    ],
                                  ),
                            ),
                        child: const Text('open'),
                      ),
                    ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Altın  x123456789'), findsOneWidget);
          expect(find.text('Elmas  x987654321'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.widgetWithText(LunoButton, 'HARİKA'),
            250,
            scrollable: find.byType(Scrollable).last,
            maxScrolls: 60,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithText(LunoButton, 'HARİKA'));
          await tester.pumpAndSettle();
          expect(find.byType(ChestRevealDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
