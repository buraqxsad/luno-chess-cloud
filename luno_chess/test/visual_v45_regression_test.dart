import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/deck_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';

void main() {
  testWidgets(
    'Upgraded family deck fits large text and rejects disposed taps',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.instance;
      final previous = store.data;
      addTearDown(() => store.data = previous);
      store.data =
          PlayerData.initial()
            ..ownedCards = {...kAllOwnable}
            ..deck = [...kFamilies, 'freeze']
            ..cardLevel = {for (final key in kFamilies) key: 3};
      tester.view.physicalSize = const Size(320, 568);
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
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
          home: const DeckScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final slots = find.descendant(
        of: find.byType(GridView).first,
        matching: find.byType(GestureDetector),
      );
      final tap = tester.widget<GestureDetector>(slots.first).onTap!;
      await tester.pumpWidget(const SizedBox.shrink());
      tap();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Deck stays scrollable on small screens with large text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
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
        home: const DeckScreen(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('KARTLARIN'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
