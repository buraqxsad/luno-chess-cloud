import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  setupPracticeTestAssets();
  testWidgets(
    'piece selection serializes rapid taps without unconfirmed equip on timeout',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      store.data = PlayerData.initial();
      store.data.ownedPieceSets.addAll(['ottoman', 'roma']);
      final boot = Completer<void>();
      var bootCalls = 0, requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () {
          bootCalls++;
          return boot.future;
        },
        auth: TestAuth(),
        appCheck: () async => 'test-only',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: PieceCostumeScreen(online: online, playerStore: store),
        ),
      );
      await tester.pumpAndSettle();
      Finder tile(String id) => find.byWidgetPredicate((w) {
        if (w.runtimeType.toString() != '_PieceSetTile') return false;
        return (w as dynamic).id == id;
      });
      await tester.scrollUntilVisible(
        tile('roma'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final VoidCallback selectFirst =
          (tester.widget(tile('ottoman')) as dynamic).onTap;
      final VoidCallback selectSecond =
          (tester.widget(tile('roma')) as dynamic).onTap;
      selectFirst();
      selectSecond();
      expect(store.data.pieceSet, 'luno');
      await tester.pump();
      expect(bootCalls, 1);
      expect((tester.widget(tile('roma')) as dynamic).onTap, isNull);
      await tester.scrollUntilVisible(
        tile('ottoman'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      expect((tester.widget(tile('ottoman')) as dynamic).saving, isTrue);
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(store.data.pieceSet, 'luno');
      expect(store.accountUid, 'first');
      expect(store.data.ownedPieceSets, containsAll(['ottoman', 'roma']));
      expect(requests, 0);
      expect((tester.widget(tile('ottoman')) as dynamic).saving, isFalse);
      expect(find.text('Taş seti sunucuya kaydedilemedi.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      selectFirst();
      expect(store.data.pieceSet, 'luno');
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    'current-tr', 'current-en', 'account', 'same-uid', 'epoch',
    'newer', 'covered', 'disposed', 'store', 'online',
  ]) {
    testWidgets('piece selection bootstrap timeout respects $scenario ownership', (
      tester,
    ) async {
      GameStore createStore() => GameStore.createForTesting()
        ..loaded = true
        ..accountUid = 'first'
        ..data = (PlayerData.initial()
          ..ownedPieceSets.addAll(['ottoman', 'roma']));
      final store = createStore();
      final auth = TestAuth();
      final boot = Completer<void>();
      var bootCalls = 0, requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () {
          bootCalls++;
          return boot.future;
        },
        auth: auth,
        appCheck: () async => 'test-only',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      addTearDown(online.dispose);
      addTearDown(store.dispose);
      Widget page({GameStore? owner, LunoOnlineService? service}) => shell(
        PieceCostumeScreen(online: service ?? online, playerStore: owner ?? store),
        language: scenario == 'current-en' ? 'en' : 'tr',
        reduced: true,
      );
      await tester.pumpWidget(page());
      final button = find.byKey(const ValueKey('costume-equip-ottoman'));
      await tester.ensureVisible(button);
      await tester.pump();
      tester.widget<LunoButton>(button).onPressed!();
      await tester.pump();
      expect(bootCalls, 1);
      expect(tester.widget<LunoButton>(button).loading, isTrue);
      final originalEpoch = store.serverStateEpoch;
      final originalRevision = store.accountBindingRevision;
      var visibleStore = store;

      if (scenario == 'account') {
        auth.currentUser = TestUser('second');
        await store.bindAccount('second');
      }
      if (scenario == 'same-uid') {
        await store.bindAccount('second');
        await store.bindAccount('first');
        expect(store.accountUid, 'first');
        expect(store.accountBindingRevision, greaterThan(originalRevision));
      }
      if (scenario == 'epoch') store.invalidateServerStates();
      if (scenario == 'newer') store.data.pieceSet = 'roma';
      if (scenario == 'covered') {
        Navigator.of(tester.element(find.byType(PieceCostumeScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (scenario == 'disposed') await tester.pumpWidget(const SizedBox());
      if (scenario == 'store') {
        visibleStore = createStore();
        addTearDown(visibleStore.dispose);
        expect(visibleStore.serverStateEpoch, originalEpoch);
        expect(visibleStore.accountBindingRevision, originalRevision);
        await tester.pumpWidget(page(owner: visibleStore));
      }
      if (scenario == 'online') {
        final replacement = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
        );
        addTearDown(replacement.dispose);
        expect(replacement.accountRevision, online.accountRevision);
        await tester.pumpWidget(page(service: replacement));
      }

      final expectedSet = visibleStore.data.pieceSet;
      final expectedOwned = Set<String>.of(visibleStore.data.ownedPieceSets);
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(bootCalls, 1);
      expect(requests, 0);
      expect(online.loading, isTrue);
      expect(visibleStore.data.pieceSet, expectedSet);
      expect(visibleStore.data.ownedPieceSets, expectedOwned);
      final current = scenario.startsWith('current-');
      expect(
        find.byType(SnackBar, skipOffstage: false),
        current ? findsOneWidget : findsNothing,
      );
      if (current) {
        expect(find.text(scenario == 'current-en'
            ? 'Could not save your piece set.'
            : 'Taş seti sunucuya kaydedilemedi.'), findsOneWidget);
        expect(store.serverStateEpoch, originalEpoch);
        expect(store.accountBindingRevision, originalRevision);
      }
      if (current || ['epoch', 'newer', 'store', 'online'].contains(scenario)) {
        expect(tester.widget<LunoButton>(button).loading, isFalse);
        expect(tester.widget<LunoButton>(button).onPressed, isNotNull);
      }

      boot.complete();
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(online.loading, isFalse);
      expect(visibleStore.data.pieceSet, expectedSet);
      expect(visibleStore.data.ownedPieceSets, expectedOwned);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['tr', 'en']) {
    testWidgets('piece selection request timeout preserves confirmed state $language', (
      tester,
    ) async {
      final store = GameStore.createForTesting();
      await store.bindAccount('first');
      store.data = PlayerData.initial()..ownedPieceSets.add('ottoman');
      final reply = Completer<http.Response>();
      var requests = 0;
      final paths = <String>[];
      final requestIds = <String?>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        appCheck: () async => 'test-only',
        client: MockClient((request) {
          requests++;
          paths.add(request.url.path);
          requestIds.add(request.headers['X-Luno-Request-Id']);
          return reply.future;
        }),
      );
      addTearDown(online.dispose);
      addTearDown(store.dispose);
      await online.start();
      await tester.pumpWidget(shell(
        PieceCostumeScreen(online: online, playerStore: store),
        language: language, reduced: true,
      ));
      final button = find.byKey(const ValueKey('costume-equip-ottoman'));
      await tester.ensureVisible(button);
      await tester.pump();
      tester.widget<LunoButton>(button).onPressed!();
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20 && requests == 0; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(requests, 1);
      expect(paths, [endsWith('/updateProfile')]);
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(store.data.pieceSet, 'luno');
      expect(store.data.ownedPieceSets, contains('ottoman'));
      expect(tester.widget<LunoButton>(button).loading, isFalse);
      expect(find.text(language == 'en'
          ? 'Could not save your piece set.'
          : 'Taş seti sunucuya kaydedilemedi.'), findsOneWidget);
      reply.complete(http.Response(
        '{"ok":true,"state":{"inventory":{"activePieceSet":"ottoman"}}}', 200,
      ));
      await tester.runAsync(() async =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(store.data.pieceSet, 'luno');
      // The service retries the timed-out transport with the same mutation ID.
      expect(requests, 2);
      expect(paths, everyElement(endsWith('/updateProfile')));
      expect(requestIds, everyElement(isNotNull));
      expect(requestIds.toSet(), hasLength(1));
      expect(find.text('Kuşanıldı. Taşların sonraki maç için hazır.'), findsNothing);
      expect(find.text('Equipped. Your pieces are ready for the next battle.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('piece selection retries shared bootstrap and equips only on confirmation', (
    tester,
  ) async {
    final store = GameStore.createForTesting();
    await store.bindAccount('first');
    store.data = PlayerData.initial()..ownedPieceSets.addAll(['ottoman', 'roma']);
    final boot = Completer<void>();
    final reply = Completer<http.Response>();
    var bootCalls = 0, requests = 0;
    final paths = <String>[];
    final online = LunoOnlineService.forTesting(
      bootstrap: () {
        bootCalls++;
        return boot.future;
      },
      auth: TestAuth(),
      appCheck: () async => 'test-only',
      client: MockClient((request) {
        requests++;
        paths.add(request.url.path);
        return reply.future;
      }),
    );
    addTearDown(online.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(shell(
      PieceCostumeScreen(online: online, playerStore: store), reduced: true,
    ));
    final button = find.byKey(const ValueKey('costume-equip-ottoman'));
    await tester.ensureVisible(button);
    await tester.pump();
    tester.widget<LunoButton>(button).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
    expect(find.text('Taş seti sunucuya kaydedilemedi.'), findsOneWidget);
    expect(tester.widget<LunoButton>(button).loading, isFalse);
    expect(store.data.pieceSet, 'luno');

    final retry = tester.widget<LunoButton>(button).onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(bootCalls, 1);
    expect(requests, 0);
    expect(tester.widget<LunoButton>(button).loading, isTrue);
    boot.complete();
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20 && requests == 0; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(bootCalls, 1);
    expect(requests, 1);
    expect(paths, [endsWith('/updateProfile')]);
    expect(store.data.pieceSet, 'luno');
    reply.complete(http.Response(
      '{"ok":true,"state":{"inventory":{"activePieceSet":"ottoman",'
      '"ownedSets":["std","ottoman","roma"]}}}', 200,
    ));
    await tester.runAsync(() async =>
        Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(store.data.pieceSet, 'ottoman');
    expect(requests, 1);
    expect(store.data.ownedPieceSets, containsAll(['ottoman', 'roma']));
    expect(find.text('Taş seti sunucuya kaydedilemedi.'), findsNothing);
    expect(find.text('Kuşanıldı. Taşların sonraki maç için hazır.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
