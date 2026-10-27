import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/match_menu_sheet.dart';

void main() {
  testWidgets('match menu ignores covered duplicate and disposed callbacks', (
    tester,
  ) async {
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
    final result = showMatchMenuSheet(host, const [
      MatchMenuEntry('restart', 'RESTART', LunoAssets.matchContinue),
    ]);
    await tester.pumpAndSettle();
    final callback =
        tester
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.text('RESTART'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap!;
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
    expect(await result, 'restart');
    callback();
    await tester.pumpAndSettle();
    expect(find.text('ROOT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
