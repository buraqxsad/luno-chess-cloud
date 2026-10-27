import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  testWidgets('Dragging away cancels activation and releases press state', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: LunoButton(label: 'Test', onPressed: () => calls++),
          ),
        ),
      ),
    );
    final button = find.byType(LunoButton);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    final dynamic state = tester.state(button);
    expect(state.pressed, isFalse);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Stale button callback cannot bypass disabled/loading state', (
    tester,
  ) async {
    var calls = 0;
    var loading = false;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: LunoButton(
                label: 'Test',
                loading: loading,
                onPressed: enabled ? () => calls++ : null,
              ),
            );
          },
        ),
      ),
    );
    final oldTap = tester.widget<InkWell>(find.byType(InkWell)).onTap!;
    update(() => loading = true);
    await tester.pump();
    oldTap();
    expect(calls, 0);
    update(() {
      loading = false;
      enabled = false;
    });
    await tester.pump();
    oldTap();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    oldTap();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
  for (final reduced in [false, true]) {
    testWidgets('Loading respects reduced motion=$reduced', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: child!,
              ),
          home: Scaffold(
            body: LunoButton(label: 'Test', loading: true, onPressed: () {}),
          ),
        ),
      );
      expect(
        find.byType(CircularProgressIndicator),
        reduced ? findsNothing : findsOneWidget,
      );
      expect(
        find.byIcon(Icons.hourglass_top_rounded),
        reduced ? findsOneWidget : findsNothing,
      );
      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
