import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_deck_account_test.dart' show app, response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v217_player_journey_support.dart' show journeyAwait, journeyPump;
import 'v214_active_deck_test.dart' show active, reply;

Future<void> _waitForOffer(WidgetTester tester) async {
  for (var index = 0; index < 28; index++) {
    await journeyPump(tester);
    if (find
        .byKey(const ValueKey('first-offline-practice-offer'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
  fail('Offline practice offer did not appear within the bounded test wait');
}

Future<void> _drainOfflineRecovery(WidgetTester tester) async {
  // The all-503 fixture leaves at most the existing 500 ms / 1 s API backoffs.
  for (var attempt = 0; attempt < 2; attempt++) {
    await tester.pump(const Duration(seconds: 1));
    await journeyPump(tester);
  }
}

void main() {
  setupPracticeTestAssets();
  final store = GameStore.instance;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await store.load();
  });

  for (final language in ['tr', 'en']) {
    for (final failure in ['fresh-bootstrap', 'deck']) {
      for (final accept in [false, true]) {
        testWidgets('first offline offer $language $failure accept=$accept '
            'does not substitute an active deck or grant progress', (
          tester,
        ) async {
          final uid = failure == 'fresh-bootstrap' ? null : 'offline-first';
          await journeyAwait(tester, () => store.bindAccount(uid));
          store
            ..hasCompletedTutorial = true
            ..firstSessionMatchesStarted = 0;
          final before = Map<String, dynamic>.from(store.data.toJson());
          final trophies = store.rankTrophies;
          final auth =
              TestAuth()..currentUser = uid == null ? null : TestUser(uid);
          final paths = <String>[];
          final online = LunoOnlineService.forTesting(
            auth: auth,
            bootstrap: () async {
              if (failure == 'fresh-bootstrap') {
                throw TimeoutException('Test offline bootstrap');
              }
            },
            client: MockClient((request) async {
              paths.add(request.url.path.split('/').last);
              return http.Response(
                '{"ok":false,"error":"network-unavailable"}',
                503,
              );
            }),
            appCheck: () async => 'test-attestation',
          );
          addTearDown(online.dispose);
          await tester.pumpWidget(app(HomeScreen(online: online), language));
          await tester.pump();
          final action =
              tester
                  .widget<InkWell>(
                    find.byKey(const ValueKey('home-primary-battle')),
                  )
                  .onTap!;
          action();
          action();
          await _waitForOffer(tester);
          expect(
            find.byKey(const ValueKey('first-offline-practice-offer')),
            findsOneWidget,
          );
          expect(find.byType(BattleV1Screen), findsNothing);
          expect(
            find.text(
              language == 'en' ? 'Offline practice?' : 'Çevrimdışı antrenman?',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              language == 'en'
                  ? 'No trophies, spendable rewards or server progression'
                  : 'Kupa, harcanabilir ödül veya sunucu ilerlemesi',
            ),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(
              ValueKey(
                accept
                    ? 'first-offline-practice-start'
                    : 'first-offline-practice-cancel',
              ),
            ),
          );
          await journeyPump(tester);
          if (accept) {
            expect(find.byType(BattlePracticeCampaign), findsOneWidget);
            final campaign = tester.widget<BattlePracticeCampaign>(
              find.byType(BattlePracticeCampaign),
            );
            expect(campaign.replay, isTrue);
            final game = tester.widget<BattleV1Screen>(
              find.byType(BattleV1Screen),
            );
            expect(game.practiceStage, isNotNull);
            expect(game.local, isFalse);
            expect(game.matchId, isNull);
            final dynamic state = tester.state(find.byType(BattleV1Screen));
            expect(state.localSession, isNotNull);
            state.localSession.resign();
            await journeyPump(tester);
          } else {
            expect(find.byType(HomeScreen), findsOneWidget);
            expect(find.byType(BattlePracticeCampaign), findsNothing);
            expect(find.byType(BattleV1Screen), findsNothing);
          }
          expect(store.data.toJson(), before);
          expect(store.rankTrophies, trophies);
          expect(store.firstSessionMatchesStarted, 0);
          expect(store.firstSessionMatchCompleted, isFalse);
          expect(
            find.byKey(const ValueKey('claim-welcome-reward')),
            findsNothing,
          );
          expect(
            paths.where(
              (path) => {
                'claimOnboardingReward',
                'setBattleV1Deck',
                'submitBattleV1Action',
                'recordMatchResult',
              }.contains(path),
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          if (failure == 'deck' && !accept) {
            await _drainOfflineRecovery(tester);
          }
          await journeyAwait(tester, store.flush);
          expect(store.data.toJson(), before);
          expect(store.rankTrophies, trophies);
          expect(
            paths.where(
              (path) => path != 'getBattleV1Deck' && path != 'getBattleV1',
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('account change dismisses an unresolved offline offer', (
    tester,
  ) async {
    await journeyAwait(tester, () => store.bindAccount(null));
    store
      ..hasCompletedTutorial = true
      ..firstSessionMatchesStarted = 0;
    final auth = TestAuth()..currentUser = null;
    final online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async => throw TimeoutException('Test offline bootstrap'),
      appCheck: () async => null,
      client: MockClient((_) async => throw StateError('No HTTP expected')),
    );
    addTearDown(online.dispose);
    await tester.pumpWidget(app(HomeScreen(online: online), 'en'));
    await tester.pump();
    tester
        .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
        .onTap!();
    await _waitForOffer(tester);
    await journeyAwait(tester, () => store.bindAccount('changed-owner'));
    await journeyPump(tester);
    expect(
      find.byKey(const ValueKey('first-offline-practice-offer')),
      findsNothing,
    );
    expect(find.byType(BattlePracticeCampaign), findsNothing);
    expect(find.byType(BattleV1Screen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await journeyAwait(tester, store.flush);
    expect(tester.takeException(), isNull);
  });

  for (final boundary in [
    'covered',
    'disposed',
    'background',
    'account',
    'mismatched-auth',
  ]) {
    testWidgets('pending first entry rejects $boundary before offline offer', (
      tester,
    ) async {
      await journeyAwait(tester, () => store.bindAccount(null));
      store
        ..hasCompletedTutorial = true
        ..firstSessionMatchesStarted = 0;
      final entered = Completer<void>();
      final pending = Completer<void>();
      final auth = TestAuth()..currentUser = null;
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {
          if (!entered.isCompleted) entered.complete();
          await pending.future;
        },
        appCheck: () async => null,
        client: MockClient((_) async => throw StateError('No HTTP expected')),
      );
      addTearDown(online.dispose);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(app(HomeScreen(online: online), 'en'));
      await tester.pump();
      tester
          .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
          .onTap!();
      await journeyAwait(tester, () => entered.future);
      final nav = Navigator.of(tester.element(find.byType(HomeScreen)));
      switch (boundary) {
        case 'covered':
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('entry-cover')),
              ),
            ),
          );
        case 'disposed':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case 'account':
          await journeyAwait(tester, () => store.bindAccount('departed-entry'));
        case 'mismatched-auth':
          auth.currentUser = TestUser('different-owner');
          await journeyAwait(tester, () => store.bindAccount('departed-entry'));
      }
      pending.completeError(TimeoutException('Test offline bootstrap'));
      await journeyPump(tester);
      expect(
        find.byKey(const ValueKey('first-offline-practice-offer')),
        findsNothing,
      );
      expect(
        find.byType(BattlePracticeCampaign, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await journeyAwait(tester, store.flush);
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in ['first-guest', 'restored-auth']) {
    testWidgets('initial $mode binding can still offer reward-free practice', (
      tester,
    ) async {
      const uid = 'initial-offline-owner';
      await journeyAwait(tester, () async {
        await store.bindAccount('parking-$mode');
        await store.bindAccount(mode == 'first-guest' ? null : uid);
      });
      store
        ..hasCompletedTutorial = true
        ..firstSessionMatchesStarted = 0;
      final auth = TestAuth()..currentUser = null;
      final authChanges = StreamController<User?>.broadcast(sync: true);
      addTearDown(authChanges.close);
      final entered = Completer<void>();
      final pending = Completer<void>();
      final paths = <String>[];
      final online = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: authChanges.stream,
        bootstrap: () async {
          if (!entered.isCompleted) entered.complete();
          await pending.future;
        },
        appCheck: () async => 'test-attestation',
        client: MockClient((request) async {
          paths.add(request.url.path.split('/').last);
          return http.Response(
            '{"ok":false,"error":"network-unavailable"}',
            503,
          );
        }),
      );
      addTearDown(online.dispose);
      await tester.pumpWidget(
        app(
          ListenableBuilder(
            listenable: store,
            builder:
                (_, _) => HomeScreen(
                  key: ValueKey(store.accountBindingRevision),
                  online: online,
                ),
          ),
          'en',
        ),
      );
      await tester.pump();
      tester
          .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
          .onTap!();
      await journeyAwait(tester, () => entered.future);
      final entryRevision = store.accountBindingRevision;
      final authRevision = online.accountRevision;
      auth.currentUser = TestUser(uid);
      authChanges.add(auth.currentUser);
      await journeyAwait(tester, () => store.bindAccount(uid));
      expect(
        store.accountBindingRevision,
        entryRevision + (mode == 'first-guest' ? 1 : 0),
      );
      expect(online.accountRevision, authRevision + 1);
      final before = Map<String, dynamic>.from(store.data.toJson());
      final trophies = store.rankTrophies;
      pending.complete();
      await _waitForOffer(tester);
      expect(
        find.byKey(const ValueKey('first-offline-practice-offer')),
        findsOneWidget,
      );
      expect(find.byType(BattleV1Screen), findsNothing);
      expect(paths.where((path) => path == 'getBattleV1Deck'), isNotEmpty);
      await tester.tap(
        find.byKey(const ValueKey('first-offline-practice-cancel')),
      );
      await journeyPump(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(BattlePracticeCampaign), findsNothing);
      expect(find.byType(BattleV1Screen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _drainOfflineRecovery(tester);
      await journeyAwait(tester, store.flush);
      expect(store.data.toJson(), before);
      expect(store.rankTrophies, trophies);
      expect(store.firstSessionMatchesStarted, 0);
      expect(store.firstSessionMatchCompleted, isFalse);
      expect(
        paths.where(
          (path) => path != 'getBattleV1Deck' && path != 'getBattleV1',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final boundary in ['covered', 'disposed', 'background']) {
    testWidgets('saved offline consent cannot launch after $boundary', (
      tester,
    ) async {
      await journeyAwait(tester, () => store.bindAccount(null));
      store
        ..hasCompletedTutorial = true
        ..firstSessionMatchesStarted = 0;
      final online = LunoOnlineService.forTesting(
        auth: TestAuth()..currentUser = null,
        bootstrap: () async => throw TimeoutException('Test offline bootstrap'),
        appCheck: () async => null,
        client: MockClient((_) async => throw StateError('No HTTP expected')),
      );
      addTearDown(online.dispose);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(app(HomeScreen(online: online), 'en'));
      await tester.pump();
      tester
          .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
          .onTap!();
      await _waitForOffer(tester);
      final accept =
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('first-offline-practice-start')),
              )
              .onPressed!;
      final nav = Navigator.of(tester.element(find.byType(HomeScreen)));
      switch (boundary) {
        case 'covered':
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('offer-cover')),
              ),
            ),
          );
          await journeyPump(tester);
        case 'disposed':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await journeyPump(tester);
      }
      accept();
      await journeyPump(tester);
      expect(
        find.byType(BattlePracticeCampaign, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await journeyAwait(tester, store.flush);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'late bootstrap cannot replace an accepted offline practice route',
    (tester) async {
      await journeyAwait(tester, () => store.bindAccount(null));
      store
        ..hasCompletedTutorial = true
        ..firstSessionMatchesStarted = 0;
      final pending = Completer<void>();
      final entered = Completer<void>();
      final online = LunoOnlineService.forTesting(
        auth: TestAuth()..currentUser = null,
        bootstrap: () async {
          if (!entered.isCompleted) entered.complete();
          await pending.future;
        },
        appCheck: () async => null,
        client: MockClient((_) async => throw StateError('No HTTP expected')),
      );
      addTearDown(online.dispose);
      await tester.pumpWidget(app(HomeScreen(online: online), 'en'));
      await tester.pump();
      tester
          .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
          .onTap!();
      await journeyAwait(tester, () => entered.future);
      await tester.pump(const Duration(seconds: 13));
      await _waitForOffer(tester);
      await tester.tap(
        find.byKey(const ValueKey('first-offline-practice-start')),
      );
      await journeyPump(tester);
      expect(find.byType(BattlePracticeCampaign), findsOneWidget);
      pending.complete();
      await journeyPump(tester);
      expect(find.byType(BattlePracticeCampaign), findsOneWidget);
      expect(find.byType(BattleV1Screen, skipOffstage: false), findsOneWidget);
      expect(
        tester
            .widget<BattleV1Screen>(find.byType(BattleV1Screen))
            .practiceStage,
        isNotNull,
      );
      expect(store.firstSessionMatchesStarted, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await journeyAwait(tester, store.flush);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirmed custom deck still enters normal AI without an offer', (
    tester,
  ) async {
    await journeyAwait(tester, () => store.bindAccount('confirmed-entry'));
    store
      ..hasCompletedTutorial = true
      ..firstSessionMatchesStarted = 0;
    var deckReads = 0;
    final online = LunoOnlineService.forTesting(
      auth: TestAuth()..currentUser = TestUser('confirmed-entry'),
      bootstrap: () async {},
      appCheck: () async => 'test-attestation',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/getBattleV1Deck')) {
          deckReads++;
          return reply(
            response(deck: active.map((card) => card.wire).toList()),
          );
        }
        throw StateError('Unexpected normal entry request');
      }),
    );
    addTearDown(online.dispose);
    await tester.pumpWidget(app(HomeScreen(online: online), 'en'));
    await tester.pump();
    tester
        .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
        .onTap!();
    for (var index = 0; index < 8; index++) {
      await journeyPump(tester);
    }
    expect(find.byType(BattleV1Screen), findsOneWidget);
    final game = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
    expect(game.practiceStage, isNull);
    expect(game.deckOnline, same(online));
    expect(online.cachedBattleDeck!.deck, active);
    expect(deckReads, 1);
    expect(
      find.byKey(const ValueKey('first-offline-practice-offer')),
      findsNothing,
    );
    expect(find.byType(BattlePracticeCampaign), findsNothing);
    expect(store.firstSessionMatchesStarted, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await journeyAwait(tester, store.flush);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account rejection does not become an offline-access bypass', (
    tester,
  ) async {
    await journeyAwait(tester, () => store.bindAccount(null));
    store
      ..hasCompletedTutorial = true
      ..firstSessionMatchesStarted = 0;
    final online = LunoOnlineService.forTesting(
      auth: TestAuth()..currentUser = null,
      bootstrap:
          () async => throw const LunoApiException('account-deleted', 403),
      appCheck: () async => null,
      client: MockClient((_) async => throw StateError('No HTTP expected')),
    );
    addTearDown(online.dispose);
    await tester.pumpWidget(app(HomeScreen(online: online), 'en'));
    await tester.pump();
    tester
        .widget<InkWell>(find.byKey(const ValueKey('home-primary-battle')))
        .onTap!();
    await journeyPump(tester);
    expect(online.accountFailure, isNotNull);
    expect(
      find.byKey(const ValueKey('first-offline-practice-offer')),
      findsNothing,
    );
    expect(find.byType(BattlePracticeCampaign), findsNothing);
    expect(find.byType(BattleV1Screen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await journeyAwait(tester, store.flush);
    expect(tester.takeException(), isNull);
  });
}
