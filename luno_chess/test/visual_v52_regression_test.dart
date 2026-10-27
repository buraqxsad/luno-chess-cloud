import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/widgets/match_offer_banner.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets('Offer controls fit and respect enabled=$enabled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var accepted = 0;
      var rejected = 0;
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
            body: MatchOfferBanner(
              title: 'Rakip maçın iptal edilmesini teklif ediyor.',
              firstLabel: 'KABUL ET',
              secondLabel: 'REDDET',
              enabled: enabled,
              onFirst: () => accepted++,
              onSecond: () => rejected++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final label in ['KABUL ET', 'REDDET']) {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        final button = tester.widget<LunoButton>(
          find.widgetWithText(LunoButton, label),
        );
        expect(button.onPressed != null, enabled);
        if (enabled) await tester.tap(find.text(label));
      }
      expect(accepted, enabled ? 1 : 0);
      expect(rejected, enabled ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}
