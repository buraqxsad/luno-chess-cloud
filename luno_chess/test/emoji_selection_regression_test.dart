import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('emoji limit, rapid removal, timeout and disposal are safe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    if (!store.loaded) await store.load();
    final original = store.data;
    addTearDown(() => store.data = original);
    store.data = PlayerData.initial();
    store.data.ownedEmojis.addAll(kEmojiIds.take(5));
    store.data.emojiLoadout = kEmojiIds.take(4).toList();
    final previous = List<String>.of(store.data.emojiLoadout);
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const EmojiCollectionScreen()),
    );
    await tester.pumpAndSettle();
    Finder art(String id) => find.byWidgetPredicate(
      (w) => w is LunoArt && w.path == LunoAssets.emoji(id),
    );
    Future<VoidCallback> action(String id) async {
      await tester.scrollUntilVisible(
        art(id),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final button =
          find.ancestor(of: art(id), matching: find.byType(InkWell)).first;
      return tester.widget<InkWell>(button).onTap!;
    }

    final fifth = await action(kEmojiIds[4]);
    fifth();
    await tester.pump();
    expect(store.data.emojiLoadout, previous);
    expect(
      find.text('Maçta en fazla 4 hızlı ifade kullanabilirsin.'),
      findsOneWidget,
    );
    final first = await action(kEmojiIds.first);
    first();
    fifth();
    expect(store.data.emojiLoadout, previous.skip(1).toList());
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
    expect(store.data.emojiLoadout, previous);
    expect(find.text('İfadeler kaydedilemedi. Tekrar dene.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    first();
    expect(store.data.emojiLoadout, previous);
    expect(tester.takeException(), isNull);
  });
}
