import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final keyboard in [0.0, 260.0]) {
    testWidgets(
      'Notices handle empty, long and replacement messages; keyboard $keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late BuildContext host;
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.5),
                    viewInsets: EdgeInsets.only(bottom: keyboard),
                  ),
                  child: child!,
                ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  host = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );
        showLunoNotice(host, '  \n ');
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        final longText = List.filled(
          50,
          'Bağlantı yeniden kuruluyor.',
        ).join(' ');
        showLunoNotice(host, longText);
        await tester.pumpAndSettle();
        expect(find.text(longText), findsOneWidget);
        expect(tester.takeException(), isNull);
        final scroll = find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(scroll, const Offset(0, -100));
        await tester.pump();
        expect(tester.takeException(), isNull);
        showLunoNotice(host, '  Güncel bildirim  ');
        await tester.pumpAndSettle();
        expect(find.text(longText), findsNothing);
        expect(find.text('Güncel bildirim'), findsOneWidget);
        showLunoNotice(host, ' ');
        await tester.pump();
        expect(find.text('Güncel bildirim'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      },
    );
  }
}
