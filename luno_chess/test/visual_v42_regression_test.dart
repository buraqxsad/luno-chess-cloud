import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  testWidgets('public profile handles large text and invalid counters', (tester) async {
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: LunoTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: const PlayerDetailsScreen(
        name: 'uzunoyuncuismi', trophies: -12, wins: 999999, games: 12,
        country: 'TR', bio: 'Uzun bir oyuncu biyografisi. Her hamlede yeni bir fikir.',
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('-12'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
