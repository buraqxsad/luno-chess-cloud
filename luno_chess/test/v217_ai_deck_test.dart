import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'battle_deck_account_test.dart' show response, app;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show warm;
import 'online_request_session_test.dart' show TestUser;
import 'v214_active_deck_test.dart' show setup, active, reply;

void main() {
  setupPracticeTestAssets();

  test(
    'cold AI deck loads server-confirmed custom deck after restart',
    () async {
      for (var restart = 0; restart < 2; restart++) {
        var reads = 0;
        final (store, online, _) = await setup((_) async {
          reads++;
          return reply(response(deck: active.map((c) => c.wire).toList()));
        });
        expect(online.cachedBattleDeck, isNull);
        expect((await online.resolveAiBattleDeck()).deck, active);
        expect(reads, 1);
        online.dispose();
        store.dispose();
      }
    },
  );

  test(
    'confirmed session deck works offline without another request',
    () async {
      var offline = false, reads = 0;
      final (store, online, _) = await setup((_) async {
        reads++;
        if (offline) throw http.ClientException('offline');
        return reply(response(deck: active.map((c) => c.wire).toList()));
      });
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await online.getBattleV1Deck();
      offline = true;
      expect((await online.resolveAiBattleDeck()).deck, active);
      expect(reads, 1);
    },
  );

  test(
    'pending save blocks AI; rejected save preserves confirmed deck',
    () async {
      final save = Completer<http.Response>();
      final entered = Completer<void>();
      final (store, online, _) = await setup((request) async {
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          return reply(response());
        }
        entered.complete();
        return save.future;
      });
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await online.getBattleV1Deck();
      final writing = online.setBattleV1Deck(
        active.map((c) => c.wire).toList(),
      );
      await entered.future;
      await expectLater(
        online.resolveAiBattleDeck(),
        throwsA(isA<Exception>()),
      );
      final rejected = expectLater(writing, throwsA(isA<Exception>()));
      save.complete(http.Response('{"error":"not-owned"}', 409));
      await rejected;
      expect((await online.resolveAiBattleDeck()).deck, starterDeck);
    },
  );

  test('old account load cannot supply the next AI account', () async {
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    final (store, online, auth) = await setup((_) async {
      entered.complete();
      return pending.future;
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    final loading = online.resolveAiBattleDeck();
    await entered.future;
    auth.currentUser = TestUser('second');
    final rejected = expectLater(loading, throwsA(isA<Exception>()));
    pending.complete(reply(response(deck: active.map((c) => c.wire).toList())));
    await rejected;
    expect(online.cachedBattleDeck, isNull);
  });

  testWidgets('AI waits for deck then rematches with newly confirmed save', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    final (store, online, _) = await setup((request) async {
      if (request.url.path.endsWith('/getBattleV1Deck')) {
        entered.complete();
        return pending.future;
      }
      return reply({'ok': true, 'deck': active.map((c) => c.wire).toList()});
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    await tester.pumpWidget(app(BattleV1Screen(deckOnline: online), 'tr'));
    await tester.runAsync(() => entered.future);
    final dynamic state = tester.state(find.byType(BattleV1Screen));
    expect(state.localSession, isNull);
    pending.complete(reply(response()));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final session = state.localSession as BattleV1LocalSession;
    expect(
      session.view.rules.arsenals[PieceColor.white]!.toSet(),
      starterDeck.toSet(),
    );
    await online.setBattleV1Deck(active.map((c) => c.wire).toList());
    session.resign();
    await tester.pump();
    final command = find.byKey(const ValueKey('local-rematch'));
    await tester.ensureVisible(command);
    await tester.tap(command);
    await tester.pump();
    final rematch = state.localSession as BattleV1LocalSession;
    expect(identical(rematch, session), false);
    expect(
      rematch.view.rules.arsenals[PieceColor.white]!.toSet(),
      active.toSet(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hung AI deck load releases retry without starting a match', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    final (store, online, _) = await setup((_) {
      if (!entered.isCompleted) entered.complete();
      return pending.future;
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    await tester.pumpWidget(app(BattleV1Screen(deckOnline: online), 'tr'));
    await tester.runAsync(() => entered.future);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    final dynamic state = tester.state(find.byType(BattleV1Screen));
    expect(state.localSession, isNull);
    expect(find.byKey(const ValueKey('ai-deck-retry')), findsOneWidget);
    pending.complete(http.Response('{"error":"deck-unavailable"}', 400));
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(state.localSession, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 768.0]) {
      testWidgets(
        'unavailable cold AI has explicit retry $language $width large text',
        (tester) async {
          tester.view.physicalSize = Size(width, width == 768 ? 1024 : 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var offline = true;
          final (store, online, _) = await setup((_) async {
            if (offline) {
              return http.Response('{"error":"deck-unavailable"}', 400);
            }
            return reply(response(deck: active.map((c) => c.wire).toList()));
          });
          addTearDown(store.dispose);
          addTearDown(online.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            app(
              RepaintBoundary(
                key: boundary,
                child: BattleV1Screen(deckOnline: online),
              ),
              language,
              textScale: 2,
            ),
          );
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
          final dynamic state = tester.state(find.byType(BattleV1Screen));
          expect(state.localSession, isNull);
          expect(
            find.byKey(const ValueKey('ai-deck-unavailable')),
            findsOneWidget,
          );
          final retry = find.byKey(const ValueKey('ai-deck-retry'));
          final copy = find.byKey(const ValueKey('ai-deck-unavailable'));
          expect(tester.getRect(copy).top, greaterThanOrEqualTo(0));
          expect(
            tester.getRect(copy).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          expect(
            tester.getRect(retry).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          expect(retry.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await warm(tester);
          await tester.pump();
          await tester.runAsync(() async {
            final render =
                tester.element(find.byKey(boundary)).renderObject!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('qa/v217/visual').create(recursive: true);
            await File(
              'qa/v217/visual/ai-deck-$language-${width.toInt()}-text200.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
          offline = false;
          await tester.tap(retry);
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
          expect(
            (state.localSession as BattleV1LocalSession)
                .view
                .rules
                .arsenals[PieceColor.white]!
                .toSet(),
            active.toSet(),
          );
          expect(
            find.byKey(const ValueKey('ai-deck-unavailable')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
