import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('friend actions fit and busy actions are disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 800);
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
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
        home: const FriendsScreen(),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(FriendsScreen));
    state.setState(() {
      state.socialLoading = false;
      state.friendRows = <Map<String, dynamic>>[
        {'uid': 'fixture', 'username': 'longplayername', 'trophies': 999999},
      ];
      state.friendBusy.add('fixture');
      state.inviteBusy.add('fixture');
    });
    await tester.pump();
    for (final label in ['Maça davet et', 'Arkadaşlıktan çıkar']) {
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == label,
        ),
      );
      expect(button.onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
