import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('filled podium fits at $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
          home: const RankingScreen(),
        ),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(RankingScreen));
      state.setState(() {
        state.loading = false;
        state.error = null;
        state.rows = <Map<String, dynamic>>[
          for (var i = 0; i < 3; i++)
            {
              'uid': 'fixture-$i',
              'username': 'longplayername$i',
              'trophies': 999999 - i,
            },
        ];
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('999999'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
