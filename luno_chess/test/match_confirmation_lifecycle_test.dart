import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/match_confirmation.dart';

void main() {
  testWidgets(
    'match confirmation ignores covered, duplicate and disposed callbacks',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold(body: Text('ROOT'));
            },
          ),
        ),
      );
      final answer = showMatchConfirmation(
        host,
        title: 'CONFIRM',
        message: 'MESSAGE',
        confirmLabel: 'ACCEPT',
      );
      await tester.pumpAndSettle();
      final callback =
          tester
              .widget<LunoButton>(
                find.byWidgetPredicate(
                  (w) => w is LunoButton && w.label == 'ACCEPT',
                ),
              )
              .onPressed!;
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('COVER')),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(find.text('COVER'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
      expect(find.text('ROOT'), findsOneWidget);
      callback();
      await tester.pumpAndSettle();
      expect(find.text('ROOT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
