import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Pasted room code discards separators before length limit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const FriendlyOnlineScreen()),
    );
    final field = find.byType(TextField);
    await tester.scrollUntilVisible(
      field,
      120,
      scrollable:
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    for (final input in [' LK7X9M ', 'LK7-X9M', 'LK7\nX9M']) {
      await tester.enterText(field, input);
      expect(tester.widget<TextField>(field).controller!.text, 'LK7X9M');
    }
      await tester.enterText(field, '');
      await tester.enterText(field, 'ABC1234');
    expect(tester.widget<TextField>(field).controller!.text, 'ABC123');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final fails in [false, true]) {
    testWidgets('Room copy handles failure=$fails and busy guards', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (fails) throw PlatformException(code: 'unavailable');
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  disableAnimations: true,
                ),
                child: child!,
              ),
          home: const FriendlyOnlineScreen(),
        ),
      );
      final dynamic state = tester.state(find.byType(FriendlyOnlineScreen));
      state.setState(() => state.roomCode = 'LK7X9M');
      await tester.pump();
      final copy = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Oda kodunu kopyala',
      );
      await tester.scrollUntilVisible(copy, 120);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, fails ? isNull : 'LK7X9M');
      expect(
        find.text(
          fails ? 'Kod kopyalanamadı. Tekrar dene.' : 'Oda kodu kopyalandı.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      state.setState(() => state.busy = true);
      await tester.pump();
      expect(tester.widget<IconButton>(copy).onPressed, isNull);
      final close = find.byWidgetPredicate(
        (w) => w is LunoButton && w.label == 'Odayı kapat',
      );
      await tester.scrollUntilVisible(
        close,
        100,
        scrollable:
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(tester.widget<LunoButton>(close).onPressed, isNull);
      expect(tester.takeException(), isNull);
      state.roomCode = null;
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
