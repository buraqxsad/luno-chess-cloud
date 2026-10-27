import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/battle_collection_progress.dart';
import 'battle_deck_account_test.dart' show app, response, card;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show noOverflow;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v215_progression_product_test.dart' show modernProgress;
import 'v216_progression_visual_test.dart' show v216Deck;

Future<VoidCallback> prepareChangedDeck(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    card(CardId.fog),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  tester.widget<BattleCatalogCard>(card(CardId.fog)).onTap!();
  await tester.pumpAndSettle();
  tester
      .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid).last)
      .onTap!(CardId.purify);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('SAVE DECK'),
    -250,
    scrollable: find.byType(Scrollable).first,
  );
  return tester
      .widgetList<LunoButton>(find.byType(LunoButton))
      .singleWhere((button) => button.icon == Icons.save_rounded)
      .onPressed!;
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true
      ..hasChosenUsername = true;
  });

  for (final language in ['tr', 'en']) {
    testWidgets(
      'V216 long press keeps verified counters and account guard $language',
      (tester) async {
        final auth = TestAuth()..currentUser = TestUser('first');
        final online = LunoOnlineService.forTesting(
          auth: auth,
          bootstrap: () async {},
        );
        addTearDown(online.dispose);
        await tester.pumpWidget(
          app(
            BattleDeckScreen(
              catalogOnly: true,
              online: online,
              loadOverride: () async => v216Deck(),
            ),
            language,
            textScale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          card(CardId.breakSeal),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final tile = find.descendant(
          of: card(CardId.breakSeal),
          matching: find.byType(InkWell),
        );
        tester.widget<InkWell>(tile).onLongPress!();
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(BattleUnlockProgress),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('catalog-open-deck')), findsNothing);
        auth.currentUser = TestUser('second');
        await online.retry();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('V216 locked OR counters and no deck action $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            catalogOnly: true,
            loadOverride: () async => v216Deck(),
          ),
          language,
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        card(CardId.breakSeal),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final tap =
          tester.widget<BattleCatalogCard>(card(CardId.breakSeal)).onTap!;
      tap();
      tap();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('catalog-open-deck')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(
            language == 'tr' ? 'Sıralı maç  0/2' : 'Ranked matches  0/2',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(
            language == 'tr'
                ? 'Günlük ödül günü  1/2'
                : 'Daily reward days  1/2',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(language == 'tr' ? 'VEYA' : 'OR'), findsWidgets);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'V216 owned library card opens focused replacement without autosave $language',
      (tester) async {
        var saves = 0;
        var savedDeck = starterDeck.map((c) => c.wire).toList();
        final owned = [...starterDeck.map((c) => c.wire), 'mine'];
        await tester.pumpWidget(
          app(
            BattleDeckScreen(
              catalogOnly: true,
              loadOverride:
                  () async => {
                    ...response(owned: owned, deck: savedDeck),
                    'progression': modernProgress(0, 1, true),
                  },
              saveOverride: (deck) async {
                saves++;
                savedDeck = List.of(deck);
                return {'ok': true, 'deck': deck};
              },
            ),
            language,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          card(CardId.mine),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        tester.widget<BattleCatalogCard>(card(CardId.mine)).onTap!();
        await tester.pumpAndSettle();
        final button = tester.widget<LunoButton>(
          find.byKey(const ValueKey('catalog-open-deck')),
        );
        button.onPressed!();
        button.onPressed!();
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'tr'
                ? 'HANGİ KART DEĞİŞSİN?'
                : 'WHICH CARD TO REPLACE?',
          ),
          findsOneWidget,
        );
        expect(
          find.byType(BattleDeckScreen, skipOffstage: false),
          findsNWidgets(2),
        );
        expect(saves, 0);
        final grid = tester.widget<BattleSelectedDeckGrid>(
          find.byType(BattleSelectedDeckGrid).last,
        );
        expect(grid.cards, starterDeck);
        grid.onTap!(CardId.purify);
        await tester.pumpAndSettle();
        final active = tester.widget<BattleSelectedDeckGrid>(
          find.byType(BattleSelectedDeckGrid),
        );
        expect(active.cards, contains(CardId.mine));
        expect(active.cards, isNot(contains(CardId.purify)));
        expect(saves, 0);
        noOverflow(tester);
        await tester.scrollUntilVisible(
          find.text(language == 'tr' ? 'DESTENİ KAYDET' : 'SAVE DECK'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final save = tester
            .widgetList<LunoButton>(find.byType(LunoButton))
            .singleWhere((b) => b.icon == Icons.save_rounded);
        save.onPressed!();
        await tester.pumpAndSettle();
        expect(saves, 1);
        save.onPressed!();
        await tester.pumpAndSettle();
        expect(
          saves,
          1,
          reason: 'A stale callback must not save an unchanged deck again',
        );
        expect(
          find.text(language == 'tr' ? 'Deste kaydedildi' : 'Deck saved'),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.byType(BattleDeckScreen))).pop();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          card(CardId.mine),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester.widget<BattleCatalogCard>(card(CardId.mine)).selected,
          isTrue,
        );
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'V216 arena says true card relationship and next threshold $language',
      (tester) async {
        await tester.pumpWidget(
          app(const ArenasScreen(), language, textScale: 1.5),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            language == 'tr' ? '100 kupa kaldı' : '100 trophies to',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            language == 'tr'
                ? 'Kartlar her arenada'
                : 'Cards unlock separately',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('arena-card-library')),
          findsOneWidget,
        );
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'V216 collection card route receives ownership loader $language',
      (tester) async {
        var loads = 0;
        await tester.pumpWidget(
          app(
            CollectionScreen(
              deckLoadOverride: () async {
                loads++;
                return v216Deck();
              },
            ),
            language,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'tr' ? 'KARTLAR' : 'CARDS'));
        await tester.pumpAndSettle();
        expect(loads, 1);
        expect(
          tester
              .widget<BattleDeckScreen>(find.byType(BattleDeckScreen))
              .catalogOnly,
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('battle-owned-count')),
          findsOneWidget,
        );
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('V216 pending ownership is preview, cannot edit or claim owned', (
    tester,
  ) async {
    final load = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      app(
        BattleDeckScreen(catalogOnly: true, loadOverride: () => load.future),
        'en',
      ),
    );
    await tester.pump();
    final item = tester.widget<BattleCatalogCard>(card(CardId.radar));
    expect(item.ownershipKnown, isFalse);
    expect(find.text('In deck'), findsNothing);
    item.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('catalog-open-deck')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    load.complete(v216Deck());
    await tester.pump();
    noOverflow(tester);
  });

  testWidgets(
    'V216 retry coalesces rapid taps without extra ownership requests',
    (tester) async {
      var loads = 0;
      final retryLoad = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            catalogOnly: true,
            loadOverride: () {
              loads++;
              return loads == 1
                  ? Future.error(StateError('offline'))
                  : retryLoad.future;
            },
          ),
          'en',
        ),
      );
      await tester.pumpAndSettle();
      final retry =
          tester
              .widgetList<IconButton>(find.byType(IconButton))
              .singleWhere((button) => button.tooltip == 'Retry')
              .onPressed!;
      retry();
      retry();
      await tester.pump();
      expect(loads, 2);
      retryLoad.complete(v216Deck());
      await tester.pumpAndSettle();
      expect(find.text('10/24 cards owned'), findsOneWidget);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'V216 unconfirmed save retains changes and never reports success',
    (tester) async {
      final result = Completer<Map<String, dynamic>>();
      var saves = 0;
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            loadOverride: () async => response(),
            saveOverride: (_) {
              saves++;
              return result.future;
            },
          ),
          'en',
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
          .onTap!(CardId.purify);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        card(CardId.fog),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      tester.widget<BattleCatalogCard>(card(CardId.fog)).onTap!();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('SAVE DECK'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      final save =
          tester
              .widgetList<LunoButton>(find.byType(LunoButton))
              .singleWhere((b) => b.icon == Icons.save_rounded)
              .onPressed!;
      save();
      save();
      await tester.pump();
      expect(saves, 1);
      expect(find.text('Deck saved'), findsNothing);
      result.complete({
        'ok': true,
        'deck': starterDeck.map((c) => c.wire).toList(),
      });
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Deck save could not be confirmed. Your draft is kept; check the save or retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('Deck saved'), findsNothing);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('selected-deck-grid')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
            .cards,
        contains(CardId.fog),
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('V216 account change removes private card condition modal', (
    tester,
  ) async {
    final auth = TestAuth()..currentUser = TestUser('first');
    final online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
    );
    addTearDown(online.dispose);
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          catalogOnly: true,
          online: online,
          loadOverride: () async => v216Deck(),
        ),
        'en',
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      card(CardId.mine),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<BattleCatalogCard>(card(CardId.mine)).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(BattleUnlockProgress), findsWidgets);
    auth.currentUser = TestUser('second');
    await online.retry();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 stale ownership response cannot replace the next account', (
    tester,
  ) async {
    final auth = TestAuth()..currentUser = TestUser('first');
    final changes = StreamController<TestUser>(sync: true);
    addTearDown(changes.close);
    final online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
      authChanges: changes.stream,
    );
    addTearDown(online.dispose);
    final oldLoad = Completer<Map<String, dynamic>>();
    final newLoad = Completer<Map<String, dynamic>>();
    var loads = 0;
    await tester.pumpWidget(
      app(
        LunoAccountScope(
          service: online,
          page: BattleDeckScreen(
            online: online,
            catalogOnly: true,
            loadOverride: () => ++loads == 1 ? oldLoad.future : newLoad.future,
          ),
        ),
        'en',
      ),
    );
    await tester.pump();
    final nextUser = TestUser('second');
    auth.currentUser = nextUser;
    changes.add(nextUser);
    await online.retry();
    await tester.pump();
    await tester.pump();
    expect(loads, 2);
    oldLoad.complete(v216Deck(matches: 20));
    newLoad.complete(v216Deck());
    await tester.pumpAndSettle();
    expect(find.text('10/24 cards owned'), findsOneWidget);
    expect(find.text('24/24 cards owned'), findsNothing);
    await tester.scrollUntilVisible(
      card(CardId.mine),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<BattleCatalogCard>(card(CardId.mine)).locked, isTrue);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V216 duplicate entitlement rows preserve one earned card', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          catalogOnly: true,
          loadOverride:
              () async => response(
                owned: [...starterDeck.map((c) => c.wire), 'fog', 'fog'],
              ),
        ),
        'en',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('11/24 cards owned'), findsOneWidget);
    await tester.scrollUntilVisible(
      card(CardId.fog),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<BattleCatalogCard>(card(CardId.fog)).locked, isFalse);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  for (final malformed in ['duplicate', 'unknown']) {
    testWidgets('V216 malformed $malformed deck stays unowned preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            catalogOnly: true,
            loadOverride:
                () async => response(
                  deck:
                      malformed == 'duplicate'
                          ? List.filled(10, 'radar')
                          : [
                            ...starterDeck.take(9).map((c) => c.wire),
                            'unknown',
                          ],
                ),
          ),
          'en',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ownership unavailable. Cards are preview only.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('battle-owned-count')), findsNothing);
      final radar = tester.widget<BattleCatalogCard>(card(CardId.radar));
      expect(radar.ownershipKnown, isFalse);
      radar.onTap!();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('catalog-open-deck')), findsNothing);
      expect(find.text('In your collection'), findsNothing);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('V216 live arena thresholds and maximum arena are not stale', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ArenasScreen(), 'en', textScale: 1.5));
    await tester.pumpAndSettle();
    GameStore.instance.applyServerState({'trophies': 620, 'arenaIdx': 3});
    await tester.pumpAndSettle();
    expect(find.textContaining('380 trophies to Emperor'), findsOneWidget);
    GameStore.instance.applyServerState({'trophies': 4000, 'arenaIdx': 8});
    await tester.pumpAndSettle();
    expect(find.text('Highest arena reached'), findsOneWidget);
    expect(find.textContaining('trophies to'), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  for (final malformed in [
    'rejected',
    'missing',
    'type',
    'duplicate',
    'unknown',
    'extra',
    'reordered',
  ]) {
    testWidgets('V216 $malformed save needs exact acknowledgment and retry', (
      tester,
    ) async {
      var saves = 0;
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            loadOverride: () async => response(),
            saveOverride: (deck) async {
              saves++;
              if (saves > 1) return {'ok': true, 'deck': List.of(deck)};
              return switch (malformed) {
                'rejected' => {'ok': false, 'deck': deck},
                'missing' => {'ok': true},
                'type' => {
                  'ok': true,
                  'deck': [1, ...deck.skip(1)],
                },
                'duplicate' => {'ok': true, 'deck': List.filled(10, 'radar')},
                'unknown' => {
                  'ok': true,
                  'deck': ['unknown', ...deck.skip(1)],
                },
                'extra' => {
                  'ok': true,
                  'deck': [...deck, 'mine'],
                },
                _ => {'ok': true, 'deck': deck.reversed.toList()},
              };
            },
          ),
          'en',
        ),
      );
      final save = await prepareChangedDeck(tester);
      save();
      save();
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(find.text('Deck saved'), findsNothing);
      expect(
        find.text(
          'Deck save could not be confirmed. Your draft is kept; check the save or retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('Unsaved changes'), findsOneWidget);
      save();
      await tester.pumpAndSettle();
      expect(saves, 2);
      expect(find.text('Deck saved'), findsOneWidget);
      expect(
        find.text(
          'Deck save could not be confirmed. Your draft is kept; check the save or retry.',
        ),
        findsNothing,
      );
      save();
      await tester.pumpAndSettle();
      expect(saves, 2);
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('V216 loaded ownership cannot survive a store account epoch', (
    tester,
  ) async {
    final store = GameStore.instance;
    await tester.runAsync(() => store.bindAccount('epoch-first'));
    addTearDown(() => store.bindAccount(null));
    var saves = 0;
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          loadOverride: () async => response(),
          saveOverride: (deck) async {
            saves++;
            return {'ok': true, 'deck': deck};
          },
        ),
        'en',
      ),
    );
    final save = await prepareChangedDeck(tester);
    await tester.runAsync(() => store.bindAccount('epoch-second'));
    await tester.pumpAndSettle();
    save();
    await tester.pumpAndSettle();
    expect(
      saves,
      0,
      reason: 'Loaded rights belong to the previous store epoch',
    );
    expect(find.text('Deck saved'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Battle deck'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Your session changed. Reopen this screen to load your deck.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('battle-owned-count')), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V216 delayed save cannot confirm after store account epoch', (
    tester,
  ) async {
    final store = GameStore.instance;
    await tester.runAsync(() => store.bindAccount('save-first'));
    addTearDown(() => store.bindAccount(null));
    final pending = Completer<Map<String, dynamic>>();
    List<String>? submitted;
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          loadOverride: () async => response(),
          saveOverride: (deck) {
            submitted = List.of(deck);
            return pending.future;
          },
        ),
        'en',
      ),
    );
    final save = await prepareChangedDeck(tester);
    save();
    await tester.pump();
    expect(submitted, hasLength(10));
    await tester.runAsync(() => store.bindAccount('save-second'));
    pending.complete({'ok': true, 'deck': submitted});
    await tester.pumpAndSettle();
    expect(find.text('Deck saved'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Battle deck'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Your session changed. Reopen this screen to load your deck.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('battle-owned-count')), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V216 pending ownership is invalidated by store account epoch', (
    tester,
  ) async {
    final store = GameStore.instance;
    await tester.runAsync(() => store.bindAccount('load-first'));
    addTearDown(() => store.bindAccount(null));
    final pending = Completer<Map<String, dynamic>>();
    var loads = 0;
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          catalogOnly: true,
          loadOverride: () {
            loads++;
            return pending.future;
          },
        ),
        'en',
      ),
    );
    await tester.pump();
    expect(loads, 1);
    final inspect = tester.widget<BattleCatalogCard>(card(CardId.radar)).onTap!;
    await tester.runAsync(() => store.bindAccount('load-second'));
    pending.complete(v216Deck(matches: 20));
    await tester.pumpAndSettle();
    inspect();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('battle-owned-count')), findsNothing);
    expect(find.text('24/24 cards owned'), findsNothing);
    expect(
      find.text('Your session changed. Reopen this screen to load your deck.'),
      findsOneWidget,
    );
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V216 same UID reentry rejects the earlier ownership epoch', (
    tester,
  ) async {
    final auth = TestAuth()..currentUser = TestUser('returning');
    final changes = StreamController<TestUser?>(sync: true);
    addTearDown(changes.close);
    final online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
      authChanges: changes.stream,
    );
    addTearDown(online.dispose);
    final oldLoad = Completer<Map<String, dynamic>>();
    final newLoad = Completer<Map<String, dynamic>>();
    var loads = 0;
    await tester.pumpWidget(
      app(
        LunoAccountScope(
          service: online,
          page: BattleDeckScreen(
            online: online,
            catalogOnly: true,
            loadOverride: () => ++loads == 1 ? oldLoad.future : newLoad.future,
          ),
        ),
        'en',
      ),
    );
    await tester.pump();
    final oldRevision = online.accountRevision;
    auth.currentUser = null;
    changes.add(null);
    await tester.pump();
    expect(find.byType(BattleDeckScreen), findsNothing);
    final returning = TestUser('returning');
    auth.currentUser = returning;
    changes.add(returning);
    await online.retry();
    await tester.pump();
    await tester.pump();
    expect(online.accountRevision, greaterThan(oldRevision));
    expect(loads, 2);
    oldLoad.complete(v216Deck(matches: 20));
    newLoad.complete(v216Deck());
    await tester.pumpAndSettle();
    expect(find.text('10/24 cards owned'), findsOneWidget);
    expect(find.text('24/24 cards owned'), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in ['tr', 'en']) {
    testWidgets('V216 next unlock summary uses its own OR targets $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          BattleDeckScreen(
            catalogOnly: true,
            loadOverride: () async => v216Deck(),
          ),
          language,
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('battle-unlock-progress')),
          matching: find.text(
            language == 'tr'
                ? 'Sıralı maç 0/1 VEYA Karşılama ödülü 0/1'
                : 'Ranked matches 0/1 OR Welcome reward 0/1',
          ),
        ),
        findsOneWidget,
      );
      noOverflow(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'V216 long canonical names fit narrow selected deck $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final deck = CardId.values.skip(14).toList();
        await tester.pumpWidget(
          app(
            BattleDeckScreen(
              loadOverride:
                  () async => response(
                    deck: deck.map((card) => card.wire).toList(),
                    owned: CardId.values.map((card) => card.wire).toList(),
                  ),
            ),
            language,
            textScale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('selected-deck-grid')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BattleSelectedDeckGrid>(
                find.byType(BattleSelectedDeckGrid),
              )
              .cards,
          deck,
        );
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('V216 timed out ownership cannot overwrite a successful retry', (
    tester,
  ) async {
    final stale = Completer<Map<String, dynamic>>();
    var loads = 0;
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          catalogOnly: true,
          loadOverride:
              () => ++loads == 1 ? stale.future : Future.value(v216Deck()),
        ),
        'en',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(
      find.text('Ownership unavailable. Cards are preview only.'),
      findsOneWidget,
    );
    final retry =
        tester
            .widgetList<IconButton>(find.byType(IconButton))
            .singleWhere((button) => button.tooltip == 'Retry')
            .onPressed!;
    retry();
    await tester.pumpAndSettle();
    expect(loads, 2);
    stale.complete(v216Deck(matches: 20));
    await tester.pumpAndSettle();
    expect(find.text('10/24 cards owned'), findsOneWidget);
    expect(find.text('24/24 cards owned'), findsNothing);
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('V216 save timeout keeps edits and ignores late acknowledgment', (
    tester,
  ) async {
    final stale = Completer<Map<String, dynamic>>();
    List<String>? submitted;
    var saves = 0;
    await tester.pumpWidget(
      app(
        BattleDeckScreen(
          loadOverride: () async => response(),
          saveOverride: (deck) {
            submitted = List.of(deck);
            return ++saves == 1
                ? stale.future
                : Future.value({'ok': true, 'deck': deck});
          },
        ),
        'en',
      ),
    );
    final save = await prepareChangedDeck(tester);
    save();
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('Deck saved'), findsNothing);
    expect(
      find.text(
        'Deck save could not be confirmed. Your draft is kept; check the save or retry.',
      ),
      findsOneWidget,
    );
    expect(find.text('Unsaved changes'), findsOneWidget);
    save();
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.text('Deck saved'), findsOneWidget);
    stale.complete({'ok': false, 'deck': submitted});
    await tester.pumpAndSettle();
    expect(find.text('Deck saved'), findsOneWidget);
    expect(
      find.text(
        'Deck save could not be confirmed. Your draft is kept; check the save or retry.',
      ),
      findsNothing,
    );
    noOverflow(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
