import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_deck_account_test.dart' as deck;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'v217_player_journey_support.dart';

void main() {
  setupPracticeTestAssets();
  setUp(() async {
    await SharedPreferences.getInstance();
  });
  final store = GameStore.instance;
  setUpAll(store.load);

  testWidgets('V217 confirmed collection replacement -> saved ten -> cold '
      'service/store restart -> actual AI uses custom arsenal', (tester) async {
    journeyViewport(tester);
    await journeyAwait(tester, () => store.bindAccount('v217-custom-deck'));
    final transport = JourneyTransport(store)..ownedCards.add(CardId.mine);
    final online = transport.service();
    await journeyAwait(tester, online.start);
    await tester.pumpWidget(
      shell(BattleDeckScreen(online: online), language: 'en', reduced: true),
    );
    await journeyPump(tester);
    debugPrint('JOURNEY deck: collection loaded');
    await tester.scrollUntilVisible(
      deck.card(CardId.mine),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await journeyTap(tester, deck.card(CardId.mine));
    expect(find.text('WHICH CARD TO REPLACE?'), findsOneWidget);
    final replacement = find.byKey(const ValueKey('deck-slot-purify')).last;
    await tester.tapAt(tester.getTopLeft(replacement) + const Offset(12, 12));
    await journeyPump(tester);
    expect(find.text('WHICH CARD TO REPLACE?'), findsNothing);
    debugPrint('JOURNEY deck: replacement selected');
    expect(
      transport.deckWrites,
      0,
      reason: 'Editing is not a server-confirmed save',
    );
    final save = find.byWidgetPredicate(
      (widget) => widget is LunoButton && widget.icon == Icons.save_rounded,
    );
    await tester.scrollUntilVisible(
      save,
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await journeyTap(tester, save);
    debugPrint('JOURNEY deck: saved');
    expect(transport.deckWrites, 1);
    final expected =
        starterDeck
            .map((card) => card == CardId.purify ? CardId.mine : card)
            .toList();
    expect(online.cachedBattleDeck!.deck, expected);
    expect(transport.savedDeck, expected);
    await tester.pumpWidget(const SizedBox());
    online.dispose();
    await journeyFlush(tester, store);
    debugPrint('JOURNEY deck: store flushed');

    final restored = GameStore.createForTesting();
    addTearDown(restored.dispose);
    await journeyAwait(tester, restored.load);
    expect(restored.accountUid, store.accountUid);
    final restartedOnline = transport.service(playerStore: restored);
    addTearDown(restartedOnline.dispose);
    await journeyAwait(tester, restartedOnline.start);
    expect(
      restartedOnline.cachedBattleDeck,
      isNull,
      reason: 'This must exercise a cold service, not a warm test cache',
    );
    final readsBefore = transport.deckReads;
    await tester.pumpWidget(
      shell(
        BattleV1Screen(deckOnline: restartedOnline),
        language: 'en',
        reduced: true,
      ),
    );
    await journeyPump(tester);
    expect(transport.deckReads, readsBefore + 1);
    final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
    expect(
      board.view.rules.arsenals[PieceColor.white],
      unorderedEquals(expected),
    );
    expect(board.view.rules.arsenals[PieceColor.white], hasLength(10));
    expect(
      board.view.rules.arsenals[PieceColor.black],
      unorderedEquals(starterDeck),
    );
    expect(board.view.rules.mana[PieceColor.white], 1);
    expect(board.view.rules.ply, 0);
    expect(find.byKey(const ValueKey('ai-deck-unavailable')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await journeyFlush(tester, store);
    expect(tester.takeException(), isNull);
  });

  testWidgets('V217 shop emote -> owned collection -> quick slot; confirmed '
      'costume -> equip -> store restart -> actual battle cosmetics', (
    tester,
  ) async {
    journeyViewport(tester);
    await journeyAwait(
      tester,
      () => store.bindAccount('v217-cosmetic-journey'),
    );
    // A pre-existing server entitlement, not a locally granted purchase.
    final transport = JourneyTransport(store)..ownedSets.add('ottoman');
    final online = transport.service();
    addTearDown(online.dispose);
    await journeyAwait(tester, online.start);
    final beforeGold = store.data.gold;
    await tester.pumpWidget(
      shell(
        ShopScreen(online: online, playerStore: store, cosmeticsOnly: true),
        language: 'en',
        reduced: true,
      ),
    );
    await journeyPump(tester);
    final buy = find.byKey(const ValueKey('shop-emote-heart'));
    await tester.scrollUntilVisible(
      buy,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await journeyTap(tester, buy);
    await journeyPump(tester);
    expect(transport.purchases, 1);
    expect(
      store.data.ownedEmojis,
      contains('heart'),
      reason:
          'Purchase UI: ${find.byType(SnackBar).evaluate().map((element) => (element.widget as SnackBar).content)}',
    );
    expect(store.data.gold, lessThan(beforeGold));
    expect(find.byType(ShopRewardDialog), findsOneWidget);
    await journeyTap(tester, find.byKey(const ValueKey('shop-reward-action')));
    await journeyTap(tester, buy);
    expect(
      transport.purchases,
      1,
      reason: 'An owned shop item must open collection, not purchase twice',
    );
    expect(find.byType(EmojiCollectionScreen), findsOneWidget);
    await journeyTap(tester, find.byKey(const ValueKey('emote-select-heart')));
    expect(transport.preferenceWrites, 1);
    expect(store.data.emojiLoadout, ['heart']);
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
      shell(
        PieceCostumeScreen(online: online, playerStore: store),
        language: 'en',
        reduced: true,
      ),
    );
    await journeyPump(tester);
    final equip = find.byKey(const ValueKey('costume-equip-ottoman'));
    await tester.scrollUntilVisible(
      equip,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await journeyTap(tester, equip);
    expect(transport.profileWrites, 1);
    expect(store.data.pieceSet, 'ottoman');
    expect(store.data.isMembershipActive, isFalse);
    expect(
      store.data.premium,
      isFalse,
      reason: 'A cosmetic purchase cannot activate the paid Pass',
    );
    await tester.pumpWidget(const SizedBox());
    await journeyFlush(tester, store);

    final restored = GameStore.createForTesting();
    addTearDown(restored.dispose);
    await journeyAwait(tester, restored.load);
    expect(restored.data.ownedPieceSets, contains('ottoman'));
    expect(restored.data.pieceSet, 'ottoman');
    expect(restored.data.ownedEmojis, contains('heart'));
    expect(restored.data.emojiLoadout, ['heart']);
    expect(restored.data.gold, store.data.gold);
    final owner = store.accountUid!;
    await journeyAwait(tester, () async {
      await store.bindAccount('v217-cosmetic-parking');
      expect(store.data.pieceSet, 'luno');
      expect(store.data.ownedEmojis, isNot(contains('heart')));
      await store.bindAccount(owner);
    });
    expect(store.data.pieceSet, restored.data.pieceSet);
    expect(store.data.emojiLoadout, restored.data.emojiLoadout);
    final restartedOnline = transport.service(playerStore: restored);
    addTearDown(restartedOnline.dispose);
    await journeyAwait(tester, restartedOnline.start);
    await tester.pumpWidget(
      shell(
        BattleV1Screen(deckOnline: restartedOnline),
        language: 'en',
        reduced: true,
      ),
    );
    await journeyPump(tester);
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).pieceSet,
      restored.data.pieceSet,
    );
    expect(store.data.emojiLoadout, restored.data.emojiLoadout);
    await tester.pumpWidget(const SizedBox());
    await journeyFlush(tester, store);
    expect(tester.takeException(), isNull);
  });
}
