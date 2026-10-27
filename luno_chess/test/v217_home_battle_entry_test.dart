import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'battle_deck_account_test.dart' show app, response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v214_active_deck_test.dart' show reply, active;
import 'v217_player_journey_support.dart' show journeyAwait, journeyPump;

void main() {
  setupPracticeTestAssets();
  setUp(() async => SharedPreferences.getInstance());
  final store = GameStore.instance;
  setUpAll(store.load);
  for (final mode in [
    'known',
    'first-guest',
    'restored-auth',
    'switch',
    'covered',
  ]) {
    testWidgets('first Home battle preparation respects $mode and double tap', (
      tester,
    ) async {
      final auth = TestAuth();
      final authChanges = StreamController<User?>.broadcast(sync: true);
      addTearDown(authChanges.close);
      final pending = Completer<void>();
      final entered = Completer<void>();
      await journeyAwait(tester, () async {
        await store.bindAccount('parking-$mode');
        await store.bindAccount(mode == 'first-guest' ? null : 'first');
      });
      store
        ..hasCompletedTutorial = true
        ..hasChosenUsername = true
        ..firstSessionMatchesStarted = 0;
      if (mode == 'first-guest' || mode == 'restored-auth') {
        auth.currentUser = null;
      }
      var bootstraps = 0, reads = 0;
      final online = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: authChanges.stream,
        bootstrap: () async {
          bootstraps++;
          if (!entered.isCompleted) entered.complete();
          await pending.future;
        },
        client: MockClient((_) async {
          reads++;
          return reply(response(deck: active.map((c) => c.wire).toList()));
        }),
        appCheck: () async => 'check',
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
      final tap =
          tester
              .widget<InkWell>(
                find.byKey(const ValueKey('home-primary-battle')),
              )
              .onTap!;
      final entryUid = store.accountUid;
      final entryRevision = store.accountBindingRevision;
      final entryAuthRevision = online.accountRevision;
      tap();
      tap();
      await journeyAwait(tester, () => entered.future);
      await tester.pump();
      expect(find.byType(BattleV1Screen), findsNothing);
      expect(bootstraps, 1);
      final nav = Navigator.of(tester.element(find.byType(HomeScreen)));
      if (mode == 'switch') {
        auth.currentUser = TestUser('second');
        authChanges.add(auth.currentUser);
        await journeyAwait(tester, () => store.bindAccount('second'));
      } else if (mode == 'covered') {
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          ),
        );
      }
      if (mode == 'first-guest' || mode == 'restored-auth') {
        auth.currentUser = TestUser('first');
        authChanges.add(auth.currentUser);
        await journeyAwait(tester, () => store.bindAccount('first'));
      }
      pending.complete();
      for (var i = 0; i < 8; i++) {
        await journeyPump(tester);
      }
      if (mode == 'switch' || mode == 'covered') {
        expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
        expect(store.firstSessionMatchesStarted, 0);
      } else {
        expect(
          find.byType(BattleV1Screen),
          findsOneWidget,
          reason:
              'uid=${store.accountUid}, auth=${online.user?.uid}, '
              'cache=${online.cachedBattleDeck != null}, error=${online.lastError}, '
              'revision=${store.accountBindingRevision}, reads=$reads, '
              'ready=${online.ready}, loading=${online.loading}, '
              'entry=$entryUid/$entryRevision/$entryAuthRevision, '
              'authRevision=${online.accountRevision}',
        );
        expect(reads, 1);
        expect(store.firstSessionMatchesStarted, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await journeyAwait(tester, store.flush);
    });
  }
}
