import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  testWidgets('repeated chest close never pops the underlying shop route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: LunoTheme.dark,
        home: const Scaffold(body: Text('root')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('shop underneath')),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.text('shop underneath')),
      builder:
          (_) => const ChestRevealDialog(
            chestId: 'common',
            rewards: [
              {'type': 'gold', 'amount': 100},
            ],
          ),
    );
    await tester.pumpAndSettle();
    final close =
        tester
            .widget<LunoButton>(find.widgetWithText(LunoButton, 'HARİKA'))
            .onPressed!;
    close();
    close();
    await tester.pumpAndSettle();
    expect(find.text('shop underneath'), findsOneWidget);
    close();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('shop underneath'), findsOneWidget);
  });
}
