import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('friend removal prompt opens once and cancel keeps friend', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: LunoTheme.dark, home: const FriendsScreen()));
    await tester.pump();
    final dynamic state = tester.state(find.byType(FriendsScreen));
    state.setState(() {
      state.socialLoading = false;
      state.friendRows = <Map<String, dynamic>>[
        {'uid': 'fixture', 'username': 'longplayername', 'trophies': 99999},
      ];
    });
    await tester.pump();
    final button = tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Arkadaşlıktan çıkar'));
    button.onPressed!();
    button.onPressed!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    final cancel = tester.widget<LunoButton>(find.byWidgetPredicate((w) => w is LunoButton && w.label == 'VAZGEÇ'));
    cancel.onPressed!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    expect(state.friendRows.length, 1);
    expect(tester.takeException(), isNull);
  });
}
