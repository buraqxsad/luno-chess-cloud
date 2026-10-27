import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  testWidgets('ranking error remains reachable in landscape with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
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
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
        home: const RankingScreen(),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(RankingScreen));
    state.setState(() {
      state.loading = false;
      state.error = 'Sıralama servisine şu anda ulaşılamıyor.';
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('TEKRAR DENE'));
    await tester.pump();
    expect(find.text('TEKRAR DENE').hitTestable(), findsOneWidget);
  });
}
