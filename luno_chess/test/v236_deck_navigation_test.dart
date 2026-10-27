import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'battle_deck_account_test.dart' show app, response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v216_progression_ux_test.dart' show prepareChangedDeck;

Future<void> openDeck(
  WidgetTester tester,
  BattleDeckScreen screen, {
  String language = 'en',
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    app(
      Scaffold(
        body: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                child: const Text('open-deck'),
              ),
        ),
      ),
      language,
      textScale: textScale,
    ),
  );
  await tester.tap(find.text('open-deck'));
  await tester.pumpAndSettle();
}

Future<void> leaveDeck(WidgetTester tester, String source) async {
  if (source == 'header') {
    await tester.tap(find.byKey(const ValueKey('battle-deck-back')));
  } else if (source == 'system') {
    await tester.binding.handlePopRoute();
  } else {
    await Navigator.of(
      tester.element(find.byType(BattleDeckScreen)),
    ).maybePop();
  }
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String action) async {
  final button = find.byKey(ValueKey('battle-deck-leave-$action'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

List<CardId> draft(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(BattleDeckScreen));
  return List<CardId>.of(state.selected as List<CardId>);
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async => GameStore.instance.load());

  for (final source in ['header', 'system', 'navigator']) {
    for (final action in ['cancel', 'discard', 'save']) {
      testWidgets('$source back protects draft with $action', (tester) async {
        var writes = 0;
        await openDeck(
          tester,
          BattleDeckScreen(
            loadOverride: () async => response(),
            saveOverride: (deck) async {
              writes++;
              return {'ok': true, 'deck': deck};
            },
          ),
        );
        await prepareChangedDeck(tester);
        final changed = draft(tester);
        await leaveDeck(tester, source);
        expect(
          find.byKey(const ValueKey('battle-deck-leave-dialog')),
          findsOneWidget,
        );
        await choose(tester, action);
        expect(writes, action == 'save' ? 1 : 0);
        if (action == 'cancel') {
          expect(find.byType(BattleDeckScreen), findsOneWidget);
          expect(draft(tester), changed);
        } else {
          expect(find.text('open-deck'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('invalid nine-card draft explains disabled save in both exits', (
    tester,
  ) async {
    await openDeck(
      tester,
      BattleDeckScreen(loadOverride: () async => response()),
    );
    tester
        .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
        .onTap!(CardId.purify);
    await tester.pump();
    for (final source in ['header', 'system']) {
      await leaveDeck(tester, source);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('battle-deck-leave-dialog')),
          matching: find.textContaining('Choose exactly 10 cards (9/10).'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('battle-deck-leave-save')),
            )
            .onPressed,
        isNull,
      );
      await choose(tester, 'cancel');
      expect(draft(tester), hasLength(9));
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final source in ['header', 'system', 'navigator']) {
    testWidgets('clean deck leaves through $source without a prompt', (
      tester,
    ) async {
      await openDeck(
        tester,
        BattleDeckScreen(loadOverride: () async => response()),
      );
      await leaveDeck(tester, source);
      expect(find.text('open-deck'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('battle-deck-leave-dialog')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('pending save blocks both exits and repeated write callbacks', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    var writes = 0;
    late List<String> submitted;
    await openDeck(
      tester,
      BattleDeckScreen(
        loadOverride: () async => response(),
        saveOverride: (deck) {
          writes++;
          submitted = List.of(deck);
          return pending.future;
        },
      ),
    );
    final save = await prepareChangedDeck(tester);
    final changed = draft(tester);
    save();
    save();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('battle-deck-back')));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(BattleDeckScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('battle-deck-leave-dialog')),
      findsNothing,
    );
    expect(draft(tester), changed);
    expect(writes, 1);
    pending.complete({'ok': true, 'deck': submitted});
    await tester.pumpAndSettle();
    await leaveDeck(tester, 'system');
    expect(find.text('open-deck'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in ['tr', 'en']) {
    testWidgets('unsaved dialog fits compact large text $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openDeck(
        tester,
        BattleDeckScreen(loadOverride: () async => response()),
        language: language,
        textScale: 2,
      );
      tester
          .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
          .onTap!(CardId.purify);
      await tester.pump();
      await leaveDeck(tester, 'system');
      expect(tester.takeException(), isNull);
      await choose(tester, 'cancel');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('failed save retains draft and does not leave; retry can save', (
    tester,
  ) async {
    var writes = 0, reads = 0;
    await openDeck(
      tester,
      BattleDeckScreen(
        loadOverride: () async {
          reads++;
          return response();
        },
        saveOverride: (deck) async {
          if (++writes == 1) throw StateError('offline');
          return {'ok': true, 'deck': deck};
        },
      ),
    );
    await prepareChangedDeck(tester);
    final changed = draft(tester);
    await leaveDeck(tester, 'header');
    await choose(tester, 'save');
    expect(find.byType(BattleDeckScreen), findsOneWidget);
    expect(draft(tester), changed);
    expect(reads, 2, reason: 'A failed response must recheck the server deck');
    expect(
      find.byKey(const ValueKey('battle-deck-save-error')),
      findsOneWidget,
    );
    await leaveDeck(tester, 'system');
    await choose(tester, 'save');
    expect(writes, 2);
    expect(find.text('open-deck'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final failure in ['lost-response', 'malformed-response', 'timeout']) {
    testWidgets('$failure reconciles committed deck without a second write', (
      tester,
    ) async {
      var savedDeck = starterDeck.map((c) => c.wire).toList();
      var writes = 0, reads = 0;
      final pending = Completer<Map<String, dynamic>>();
      await openDeck(
        tester,
        BattleDeckScreen(
          loadOverride: () async {
            reads++;
            return response(deck: savedDeck);
          },
          saveOverride: (deck) async {
            writes++;
            savedDeck = List.of(deck);
            if (failure == 'timeout') return pending.future;
            if (failure == 'lost-response') throw StateError('response lost');
            return {
              'ok': true,
              'deck': ['radar'],
            };
          },
        ),
      );
      final save = await prepareChangedDeck(tester);
      save();
      await tester.pump();
      if (failure == 'timeout') {
        await tester.pump(const Duration(seconds: 15));
      }
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(writes, 1);
      expect(find.text('Deck saved'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('battle-deck-save-error')),
        findsNothing,
      );
      if (!pending.isCompleted) {
        pending.complete({'ok': true, 'deck': savedDeck});
      }
      await tester.pump();
      await leaveDeck(tester, 'system');
      expect(find.text('open-deck'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'failed reconciliation keeps draft and explicit recheck recovers',
    (tester) async {
      var reads = 0, writes = 0;
      late List<String> committed;
      await openDeck(
        tester,
        BattleDeckScreen(
          loadOverride: () async {
            if (++reads == 2) throw StateError('read offline');
            return response(deck: reads == 1 ? null : committed);
          },
          saveOverride: (deck) async {
            writes++;
            committed = List.of(deck);
            throw StateError('response lost');
          },
        ),
      );
      final save = await prepareChangedDeck(tester);
      final changed = draft(tester);
      save();
      await tester.pumpAndSettle();
      expect(draft(tester), changed);
      final check = find.byKey(const ValueKey('battle-deck-check-save'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(reads, 3);
      final dynamic state = tester.state(find.byType(BattleDeckScreen));
      expect(state.account.deck, changed);
      expect(state.error, isNull);
      expect(state.saving, isFalse);
      expect(draft(tester), changed);
      final mainScroll = find.byType(Scrollable).first;
      tester.state<ScrollableState>(mainScroll).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('battle-deck-save-status')),
        150,
        scrollable: mainScroll,
      );
      expect(find.text('Deck saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reconciliation refreshes rights without replacing an invalid draft',
    (tester) async {
      var reads = 0, writes = 0;
      await openDeck(
        tester,
        BattleDeckScreen(
          loadOverride:
              () async => response(
                owned:
                    ++reads == 1
                        ? null
                        : starterDeck.map((c) => c.wire).toList(),
              ),
          saveOverride: (_) async {
            writes++;
            throw StateError('save rejected');
          },
        ),
      );
      final save = await prepareChangedDeck(tester);
      final changed = draft(tester);
      save();
      await tester.pumpAndSettle();
      expect(draft(tester), changed);
      final saveButton = tester
          .widgetList<LunoButton>(find.byType(LunoButton))
          .singleWhere((button) => button.icon == Icons.save_rounded);
      expect(saveButton.onPressed, isNull);
      expect(reads, 2);
      final dynamic state = tester.state(find.byType(BattleDeckScreen));
      expect(state.account.deck, starterDeck);
      expect(state.account.owned, isNot(contains(CardId.fog)));
      expect(state.error, 'save');
      expect(state.saving, isFalse);
      final mainScroll = find.byType(Scrollable).first;
      tester.state<ScrollableState>(mainScroll).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('battle-deck-validation')),
        150,
        scrollable: mainScroll,
      );
      expect(find.text('Choose only cards you own.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('selected-deck-grid')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      tester
          .widget<BattleSelectedDeckGrid>(find.byType(BattleSelectedDeckGrid))
          .onTap!(CardId.fog);
      await tester.pumpAndSettle();
      expect(draft(tester), isNot(contains(CardId.fog)));
      expect(draft(tester), hasLength(9));
      expect(writes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final stage in ['dialog', 'write', 'reconcile']) {
    testWidgets('account switch invalidates draft and late $stage completion', (
      tester,
    ) async {
      final auth = TestAuth()..currentUser = TestUser('first');
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {},
      );
      addTearDown(online.dispose);
      final pending = Completer<Map<String, dynamic>>();
      var reads = 0, writes = 0;
      late List<String> submitted;
      await openDeck(
        tester,
        BattleDeckScreen(
          online: online,
          loadOverride: () async {
            if (++reads > 1 && stage == 'reconcile') return pending.future;
            return response();
          },
          saveOverride: (deck) async {
            writes++;
            submitted = List.of(deck);
            if (stage == 'reconcile') throw StateError('lost response');
            return pending.future;
          },
        ),
      );
      final save = await prepareChangedDeck(tester);
      if (stage == 'dialog') {
        await leaveDeck(tester, 'header');
      } else {
        save();
        await tester.pump();
      }
      auth.currentUser = TestUser('second');
      await online.retry();
      await tester.pumpAndSettle();
      pending.complete(
        stage == 'write' ? {'ok': true, 'deck': submitted} : response(),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('battle-deck-leave-dialog')),
        findsNothing,
      );
      expect(find.text('Deck saved'), findsNothing);
      expect(draft(tester), starterDeck);
      save();
      await tester.pump();
      expect(writes, stage == 'dialog' ? 0 : 1);
      expect(reads, stage == 'reconcile' ? 2 : 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
