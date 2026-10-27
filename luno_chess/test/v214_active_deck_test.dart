import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/deck_metrics.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show noOverflow, shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v214_social_safety_ui_test.dart' show capture;

final active = [...starterDeck.take(9), CardId.fog];
http.Response reply(Object body) => http.Response(jsonEncode(body), 200);

Future<(GameStore, LunoOnlineService, TestAuth)> setup(
  Future<http.Response> Function(http.Request) request,
) async {
  final store = GameStore.createForTesting();
  await store.load();
  final auth = TestAuth();
  final online = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: auth,
    playerStore: store,
    appCheck: () async => 'check',
    client: MockClient(request),
  );
  await online.start();
  return (store, online, auth);
}

void main() {
  setupPracticeTestAssets();
  test('cache contains only confirmed current-account V1 decks', () async {
    var malformed = false;
    final (store, online, auth) = await setup(
      (_) async => reply(
        malformed
            ? {'ok': true}
            : response(deck: active.map((c) => c.wire).toList()),
      ),
    );
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    expect(online.cachedBattleDeck, isNull);
    await online.getBattleV1Deck();
    expect(online.cachedBattleDeck!.deck, active);
    malformed = true;
    await expectLater(online.getBattleV1Deck(), throwsFormatException);
    expect(online.cachedBattleDeck!.deck, active);
    auth.currentUser = TestUser('other');
    expect(online.cachedBattleDeck, isNull);
    auth.currentUser = null;
    expect(online.cachedBattleDeck, isNull);
    auth.currentUser = TestUser('first');
    await store.bindAccount('other');
    expect(online.cachedBattleDeck, isNull);
  });
  test('late deck read cannot overwrite a newer confirmed save', () async {
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    var reads = 0;
    final (store, online, _) = await setup((request) async {
      if (request.url.path.endsWith('/getBattleV1Deck')) {
        if (++reads == 1) return reply(response());
        entered.complete();
        return pending.future;
      }
      final body = jsonDecode(request.body) as Map;
      return reply({'ok': true, 'deck': body['deck']});
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    await online.getBattleV1Deck();
    final stale = online.getBattleV1Deck();
    await entered.future;
    await online.setBattleV1Deck(active.map((c) => c.wire).toList());
    expect(online.cachedBattleDeck!.deck, active);
    pending.complete(reply(response()));
    await stale;
    expect(online.cachedBattleDeck!.deck, active);
  });
  test('reads during a save cannot replace its confirmed deck', () async {
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    final (store, online, _) = await setup((request) async {
      if (request.url.path.endsWith('/getBattleV1Deck')) {
        return reply(response());
      }
      entered.complete();
      return pending.future;
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    await online.getBattleV1Deck();
    final saved = online.setBattleV1Deck(active.map((c) => c.wire).toList());
    await entered.future;
    await online.getBattleV1Deck();
    await expectLater(
      online.setBattleV1Deck(starterDeck.map((c) => c.wire).toList()),
      throwsStateError,
    );
    pending.complete(
      reply({'ok': true, 'deck': active.map((c) => c.wire).toList()}),
    );
    await saved;
    expect(online.cachedBattleDeck!.deck, active);
  });
  test(
    'malformed saves preserve confirmed cache and reject duplicate cards',
    () async {
      final (store, online, _) = await setup(
        (request) async => reply(
          request.url.path.endsWith('/getBattleV1Deck')
              ? response()
              : {'ok': true, 'deck': starterDeck.map((c) => c.wire).toList()},
        ),
      );
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await online.getBattleV1Deck();
      await expectLater(
        online.setBattleV1Deck(active.map((c) => c.wire).toList()),
        throwsFormatException,
      );
      expect(online.cachedBattleDeck!.deck, starterDeck);
      await expectLater(
        online.setBattleV1Deck(List.filled(10, 'radar')),
        throwsFormatException,
      );
      expect(online.cachedBattleDeck!.deck, starterDeck);
    },
  );
  test(
    'read started during pending save stays stale after save completes',
    () async {
      final readPending = Completer<http.Response>();
      final savePending = Completer<http.Response>();
      final enteredRead = Completer<void>(), enteredSave = Completer<void>();
      var reads = 0;
      final (store, online, _) = await setup((request) async {
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          if (++reads == 1) return reply(response());
          enteredRead.complete();
          return readPending.future;
        }
        enteredSave.complete();
        return savePending.future;
      });
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await online.getBattleV1Deck();
      final saved = online.setBattleV1Deck(active.map((c) => c.wire).toList());
      await enteredSave.future;
      final stale = online.getBattleV1Deck();
      await enteredRead.future;
      savePending.complete(
        reply({'ok': true, 'deck': active.map((c) => c.wire).toList()}),
      );
      await saved;
      readPending.complete(reply(response()));
      await stale;
      expect(online.cachedBattleDeck!.deck, active);
    },
  );
  test(
    'departed-account reply cannot create a cache for the next account',
    () async {
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      final (store, online, auth) = await setup((_) {
        entered.complete();
        return pending.future;
      });
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      final result = online.getBattleV1Deck();
      await entered.future;
      auth.currentUser = TestUser('other');
      final rejected = expectLater(result, throwsA(isA<Exception>()));
      pending.complete(
        reply(response(deck: active.map((c) => c.wire).toList())),
      );
      await rejected;
      expect(online.cachedBattleDeck, isNull);
    },
  );
  test(
    'AI uses active deck; hotseat is symmetric; Academy remains curated',
    () {
      for (var seed = 0; seed < 20; seed++) {
        final ai = BattleV1LocalSession(
          activeDeck: active,
          random: Random(seed),
        );
        expect(
          ai.view.rules.arsenals[PieceColor.white]!.toSet(),
          active.toSet(),
        );
        expect(
          ai.view.rules.arsenals[PieceColor.black]!.toSet(),
          starterDeck.toSet(),
        );
        ai.dispose();
        final local = BattleV1LocalSession(
          hotseat: true,
          activeDeck: active,
          random: Random(seed),
        );
        for (final side in PieceColor.values) {
          expect(local.view.rules.arsenals[side]!.toSet(), starterDeck.toSet());
        }
        local.dispose();
        final curated = [...starterDeck.take(9), CardId.mine];
        final academy = BattleV1LocalSession(
          practice: true,
          practiceDeck: curated,
          activeDeck: active,
        );
        expect(
          academy.view.rules.arsenals[PieceColor.white]!.toSet(),
          curated.toSet(),
        );
        academy.dispose();
      }
      final fallback = BattleV1LocalSession();
      expect(
        fallback.view.rules.arsenals[PieceColor.white]!.toSet(),
        starterDeck.toSet(),
      );
      fallback.dispose();
      expect(
        () => BattleV1LocalSession(activeDeck: [CardId.radar]),
        throwsArgumentError,
      );
    },
  );
  test(
    'mana curve follows canonical card costs without composition restrictions',
    () {
      final stats = BattleDeckMetrics.fromCards(active);
      expect(stats.count, 10);
      expect(
        stats.totalMana,
        active.fold<int>(
          0,
          (total, card) => total + cardDefinitions[card]!.cost,
        ),
      );
      expect(stats.curve.reduce((a, b) => a + b), 10);
      for (var bucket = 0; bucket < 4; bucket++) {
        expect(
          stats.curve[bucket],
          active
              .where(
                (card) =>
                    (cardDefinitions[card]!.cost - 1).clamp(0, 3) == bucket,
              )
              .length,
        );
      }
      expect(BattleDeckMetrics.fromCards([]).average, 0);
      final draft = BattleDeckMetrics.fromCards([CardId.freeze]);
      expect(draft.isCompleteDeck, isFalse);
      expect(draft.heavy, isFalse);
    },
  );
  for (final language in ['tr', 'en']) {
    for (final width in [320, 390, 768]) {
      testWidgets(
        'active deck preview $language $width text150 with retry and cache',
        (tester) async {
          tester.view.physicalSize = Size(
            width.toDouble(),
            width == 320 ? 568 : 1024,
          );
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var fail = false;
          final (store, online, _) =
              (await tester.runAsync(
                () => setup(
                  (_) async => reply(
                    fail
                        ? {'ok': true}
                        : response(deck: active.map((c) => c.wire).toList()),
                  ),
                ),
              ))!;
          addTearDown(store.dispose);
          addTearDown(online.dispose);
          await tester.runAsync(online.getBattleV1Deck);
          fail = true;
          await tester.pumpWidget(
            shell(
              PlayModeScreen(online: online, playerStore: store),
              language: language,
              scale: 1.5,
              reduced: true,
            ),
          );
          await tester.pumpAndSettle();
          noOverflow(tester);
          expect(
            find.text(language == 'tr' ? 'AKTİF DESTEN' : 'ACTIVE DECK'),
            findsOneWidget,
          );
          expect(online.cachedBattleDeck!.deck, active);
          expect(
            find.byKey(const ValueKey('battle-deck-retry')),
            findsOneWidget,
          );
          await capture(tester, 'deck-cached-$language-$width-150');
          fail = false;
          await tester.tap(find.byKey(const ValueKey('battle-deck-retry')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('battle-deck-retry')), findsNothing);
          expect(
            find.text(language == 'tr' ? 'AKTİF DESTEN' : 'ACTIVE DECK'),
            findsOneWidget,
          );
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'loading deck preview is bounded and no stale response owns a disposed screen',
    (tester) async {
      final pending = Completer<http.Response>();
      final (store, online, _) =
          (await tester.runAsync(() => setup((_) => pending.future)))!;
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await tester.pumpWidget(
        shell(
          PlayModeScreen(online: online, playerStore: store),
          language: 'en',
          reduced: true,
        ),
      );
      await tester.pump();
      expect(find.text('Loading your deck...'), findsOneWidget);
      expect(find.text('STARTER DECK'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pending.complete(reply(response()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
