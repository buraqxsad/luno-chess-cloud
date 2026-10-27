import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ranked waiting fits enlarged text and respects reduced motion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        home: const OnlineHubScreen(),
      ),
    );
    expect(
      find.text('İnternet bağlantını kontrol et, ardından yeniden bağlan.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final dynamic state = tester.state(find.byType(OnlineHubScreen));
    state.setState(() {
      state.waiting = true;
      state.joinedAt = DateTime.now();
    });
    await tester.pump();
    expect(find.text('Rakibin bulunduğunda maç başlayacak.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .5,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is LunoButton && w.label == 'ARAMAYI İPTAL ET',
      ),
      findsOneWidget,
    );
    state.waiting = false;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
