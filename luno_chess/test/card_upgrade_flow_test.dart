import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/deck_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final change in ['balance', 'level', 'arena', 'ownership', 'account']) {
    testWidgets('upgrade confirmation rechecks $change before sending', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.instance;
      if (!store.loaded) await store.load();
      final original = store.data;
      final originalUid = store.accountUid;
      addTearDown(() {
        store.accountUid = originalUid;
        store.data = original;
      });
      store.data = PlayerData.initial();
      store.data.ownedCards.add('trap');
      store.data.cardLevel['trap'] = 1;
      store.data.gold = 10000;
      store.data.trophies = 300;
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const DeckScreen()),
      );
      await tester.pumpAndSettle();
      final upgrades = find.byWidgetPredicate(
        (w) => w is TextButton && w.onPressed != null,
      );
      await tester.scrollUntilVisible(
        upgrades.first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(upgrades.first),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(upgrades.first.hitTestable(), findsOneWidget);
      await tester.tap(upgrades.first);
      await tester.pumpAndSettle();
      switch (change) {
        case 'balance':
          store.data.gold = 0;
        case 'level':
          store.data.cardLevel['trap'] = 2;
        case 'arena':
          store.data.trophies = 0;
        case 'ownership':
          store.data.ownedCards.remove('trap');
        case 'account':
          // Real rebinding/persistence is covered by the async guard tests.
          store.accountUid = 'different-player';
      }
      final gold = store.data.gold;
      final level = store.data.cardLevel['trap'];
      await tester.tap(find.text('YÜKSELT'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text(
          'Kart veya bakiyen değişti. Güncel bilgileri kontrol edip tekrar dene.',
        ),
        change == 'account' ? findsNothing : findsOneWidget,
      );
      expect(store.data.gold, gold);
      expect(store.data.cardLevel['trap'], level);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    'failed upgrade releases busy state without spending or leveling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.instance;
      if (!store.loaded) await store.load();
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial();
      store.data.ownedCards.add('trap');
      store.data.cardLevel['trap'] = 1;
      store.data.gold = 10000;
      store.data.trophies = 300;
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const DeckScreen()),
      );
      await tester.pumpAndSettle();
      final upgrades = find.byWidgetPredicate(
        (w) => w is TextButton && w.onPressed != null,
      );
      await tester.scrollUntilVisible(
        upgrades.first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final action = tester.widget<TextButton>(upgrades.first).onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('VAZGEÇ'));
      await tester.pumpAndSettle();
      expect(store.data.gold, 10000);
      expect(store.data.cardLevel['trap'], 1);
      action();
      await tester.pumpAndSettle();
      await tester.tap(find.text('YÜKSELT'));
      await tester.pump();
      expect(store.data.gold, 10000);
      expect(store.data.cardLevel['trap'], 1);
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(store.data.gold, 10000);
      expect(store.data.cardLevel['trap'], 1);
      expect(upgrades, findsWidgets);
      expect(
        find.text(
          'Yükseltme doğrulanamadı. Bağlantı yenilendiğinde kartını kontrol et.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      action();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
