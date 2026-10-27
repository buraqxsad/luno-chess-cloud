import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('room input fits keyboard and is disabled while hosting', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: LunoTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
          viewInsets: const EdgeInsets.only(bottom: 250),
        ),
        child: child!,
      ),
      home: const FriendlyOnlineScreen(),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final dynamic state = tester.state(find.byType(FriendlyOnlineScreen));
    state.setState(() => state.roomCode = 'ABC123');
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Katıl')).onPressed, isNull);
    expect(tester.takeException(), isNull);
    state.roomCode = null;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
