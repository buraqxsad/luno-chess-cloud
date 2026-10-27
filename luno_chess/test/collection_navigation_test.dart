import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';

class _Observer extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  testWidgets('all collection entries open once and return to hub', (
    tester,
  ) async {
    final observer = _Observer();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: CollectionScreen(
          deckLoadOverride:
              () async => {
                'ok': true,
                'protocolVersion': 'LUNO_BATTLE_V1',
                'available': true,
                'deck': starterDeck.map((card) => card.wire).toList(),
                'entitlements': starterDeck.map((card) => card.wire).toList(),
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    VoidCallback? last;
    for (final entry
        in <String, Type>{
          'DESTE': BattleDeckScreen,
          'KARTLAR': BattleDeckScreen,
          'TAŞ KOSTÜMLERİ': PieceCostumeScreen,
          'EMOJİLER': EmojiCollectionScreen,
        }.entries) {
      final label = find.text(entry.key);
      await tester.scrollUntilVisible(
        label,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(label), alignment: 0.5);
      await tester.pumpAndSettle();
      final ink =
          find.ancestor(of: label, matching: find.byType(InkWell)).first;
      final callback = tester.widget<InkWell>(ink).onTap!;
      final before = observer.pushes;
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(observer.pushes, before + 1, reason: entry.key);
      expect(find.byType(entry.value), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      last = callback;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    last!();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
