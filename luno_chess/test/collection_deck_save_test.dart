import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('collection refreshes ownership without reopening the screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    if (!store.loaded) await store.load();
    final original = store.data;
    addTearDown(() => store.data = original);
    store.data = PlayerData.initial();
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const CardCollectionScreen()),
    );
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate((widget) {
      if (widget.runtimeType.toString() != '_CardTile') return false;
      final dynamic tile = widget;
      return tile.def.key == 'trap1';
    });
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect((tester.widget(card) as dynamic).owned, false);
    store.data.ownedCards.add('trap');
    store.replaceDeck(List<String>.of(store.data.deck));
    await tester.pump();
    expect((tester.widget(card) as dynamic).owned, true);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Koleksiyonunda'), findsOneWidget);
    expect(find.text('Desteye ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('collection removal rolls back when online save is unavailable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    if (!store.loaded) await store.load();
    final original = store.data;
    addTearDown(() => store.data = original);
    store.data = PlayerData.initial();
    store.data.ownedCards.add('radar');
    store.data.cardLevel['radar'] = 1;
    final previous = List<String>.of(store.data.deck);
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const CardCollectionScreen()),
    );
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate((widget) {
      if (widget.runtimeType.toString() != '_CardTile') return false;
      final dynamic tile = widget;
      return tile.def.key == 'barbarian';
    });
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desteden çıkar'));
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
    expect(store.data.deck, previous);
    expect(
      find.text('Deste kaydı doğrulanamadı. Önceki desten geri yüklendi.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
