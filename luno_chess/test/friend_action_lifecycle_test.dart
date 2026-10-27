import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'friend response buttons reject busy hidden and disposed callbacks',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: const FriendsScreen(),
        ),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(FriendsScreen));
      state.setState(() {
        state.tab = 1;
        state.socialLoading = false;
        state.requestRows = <Map<String, dynamic>>[
          {'fromUid': 'fixture', 'fromUsername': 'Deniz'},
        ];
      });
      await tester.pump();
      final buttons =
          ['Kabul et', 'Reddet']
              .map(
                (label) => find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == label,
                ),
              )
              .toList();
      final callbacks =
          buttons
              .map((finder) => tester.widget<IconButton>(finder).onPressed!)
              .toList();
      state.setState(() => state.friendBusy.add('fixture'));
      await tester.pump();
      for (final button in buttons) {
        expect(tester.widget<IconButton>(button).onPressed, isNull);
      }
      for (final callback in callbacks) {
        callback();
      }
      await tester.pump();
      expect(state.friendBusy.length, 1);
      state.setState(() => state.friendBusy.clear());
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      for (final callback in callbacks) {
        callback();
      }
      await tester.pump();
      expect(state.friendBusy, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final callback in callbacks) {
        callback();
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
