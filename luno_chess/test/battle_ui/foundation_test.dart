import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/tokens.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('foundation fits $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BattleMana(value: 3, label: 'Mana'),
                      BattleCommand(
                        label: 'Rakibin cephaneliği',
                        icon: Icons.style_outlined,
                        onPressed: () => taps++,
                      ),
                      BattleIconControl(
                        icon: Icons.close,
                        label: 'Cancel',
                        onPressed: () => taps++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(BattleIconControl)),
          const Size(48, 48),
        );
        await tester.tap(find.text('Rakibin cephaneliği'));
        expect(taps, 1);
      });
    }
  }
  testWidgets('mana reflects changes without changing glyph dimensions', (
    tester,
  ) async {
    Widget build(int mana) => MaterialApp(
      home: Scaffold(body: BattleMana(value: mana, label: 'Mana')),
    );
    await tester.pumpWidget(build(1));
    expect(tester.getSize(find.byType(BattleManaGlyph)), const Size(24, 24));
    await tester.pumpWidget(build(6));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('6 / 6'), findsOneWidget);
    expect(find.text('1 / 6'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion turns off foundation transitions', (
    tester,
  ) async {
    Duration? duration;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = BattleTokens.duration(context);
              return const BattleMana(value: 2, label: 'Mana');
            },
          ),
        ),
      ),
    );
    expect(duration, Duration.zero);
  });
}
