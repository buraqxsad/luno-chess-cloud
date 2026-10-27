import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/deck_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(800, 1280),
  ]) {
    testWidgets('deck keeps card art visible at $size and double text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data = PlayerData.initial();
      store.data.ownedCards.addAll(kAllOwnable);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: const DeckScreen(),
        ),
      );
      await tester.pump();
      final art = find.byWidgetPredicate(
        (w) => w is LunoArt && w.path == LunoAssets.card('trap', 1),
      );
      await tester.scrollUntilVisible(
        art,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.getSize(art).height, greaterThanOrEqualTo(76));
      expect(tester.takeException(), isNull);
    });
  }
}
