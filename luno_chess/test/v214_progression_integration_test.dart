import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/deck_account.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'battle_deck_account_test.dart' as deck;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'v214_deck_progression_result_test.dart' as progress;
import 'v214_active_deck_test.dart' show setup, reply;

Map<String, dynamic> account(int matches) {
  final owned = progress.ownership(matches);
  return {
    ...deck.response(owned: owned.map((c) => c.wire).toList()),
    'progression': progress.response(matches, owned),
  };
}

void main() {
  setupPracticeTestAssets();
  test(
    'deck model accepts authoritative progress and hides legacy absence',
    () {
      expect(
        BattleDeckAccount.fromResponse(
          account(6),
        ).progression!.meaningfulMatches,
        6,
      );
      expect(
        BattleDeckAccount.fromResponse(deck.response()).progression,
        isNull,
      );
      final forged = account(0);
      forged['progression']['meaningfulMatches'] = 20;
      expect(
        () => BattleDeckAccount.fromResponse(forged),
        throwsFormatException,
      );
    },
  );
  test(
    'confirmed save preserves progression without granting ownership',
    () async {
      final (store, online, _) = await setup((request) async {
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          return reply(account(6));
        }
        return reply({
          'ok': true,
          'deck': starterDeck.map((c) => c.wire).toList(),
        });
      });
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await online.getBattleV1Deck();
      final previous = online.cachedBattleDeck!;
      await online.setBattleV1Deck(starterDeck.map((c) => c.wire).toList());
      expect(online.cachedBattleDeck!.progression, same(previous.progression));
      expect(online.cachedBattleDeck!.owned, previous.owned);
      await store.bindAccount('other');
      expect(online.cachedBattleDeck, isNull);
    },
  );
  for (final language in ['tr', 'en']) {
    testWidgets('progress and next unlock fit $language at large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        deck.app(
          BattleDeckScreen(loadOverride: () async => account(6)),
          language,
          textScale: 1.5,
        ),
      );
      await tester.pump();
      await tester.pump();
      final label =
          language == 'tr'
              ? 'Sıralı maç 6/8'
              : 'Ranked matches 6/8';
      await tester.scrollUntilVisible(
        find.text(label),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
      expect(
        find.byKey(const ValueKey('battle-unlock-progress')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
