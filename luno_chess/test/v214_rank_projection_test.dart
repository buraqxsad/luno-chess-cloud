import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/services/battle_v1_rank.dart';
import 'package:luno_chess/services/public_player_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow;
import 'v214_active_deck_test.dart' show setup, reply;
import 'v214_social_safety_ui_test.dart' show capture;

Map<String, dynamic> rank(String uid, int trophies) => {
  'protocolVersion': BattleV1Rank.protocolVersion,
  'uid': uid,
  'trophies': trophies,
  'arenaIdx': arenaIndexForTrophies(trophies),
};

Map<String, dynamic> state(GameStore store, int trophies) => {
  GameStore.serverStateOwnerKey: store.accountUid,
  GameStore.serverStateEpochKey: store.serverStateEpoch,
  'battleV1Rank': rank(store.accountUid!, trophies),
};

void main() {
  final singleton = GameStore.instance;
  setupPracticeTestAssets();
  setUpAll(singleton.load);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('projection validates all arena boundaries and round trips', () {
    for (final arena in kArenaCatalog) {
      for (final trophies in [
        arena.minTrophies,
        arena.maxTrophies ?? 1000000000,
      ]) {
        final parsed = BattleV1Rank.fromJson(
          rank('A', trophies),
          expectedUid: 'A',
        );
        expect(parsed.trophies, trophies);
        expect(parsed.arenaIdx, arena.index);
        expect(parsed.toJson(), rank('A', trophies));
      }
    }
  });

  test(
    'foreign protocol/owner and malformed rank never normalize into credit',
    () {
      for (final invalid in [
        null,
        {},
        {...rank('A', 612), 'uid': 'B'},
        {...rank('A', 612), 'protocolVersion': 'LEGACY'},
        {...rank('A', 612), 'trophies': -1},
        {...rank('A', 612), 'trophies': 1000000001},
        {...rank('A', 612), 'trophies': 612.5},
        {...rank('A', 612), 'trophies': '612'},
        {...rank('A', 612), 'trophies': double.nan},
        {...rank('A', 612), 'arenaIdx': -1},
        {...rank('A', 612), 'arenaIdx': 9},
        {...rank('A', 612), 'arenaIdx': 2},
      ]) {
        expect(
          () => BattleV1Rank.fromJson(invalid, expectedUid: 'A'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'confirmed active rank is separate from legacy inventory and rating',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('A');
      store.data
        ..trophies = 777
        ..arenaIdx = 3
        ..gold = 1234
        ..gems = 456;
      final legacy = store.data.toJson();
      store.applyServerState(state(store, 612));
      expect(store.rankTrophies, 612);
      expect(store.rankArenaIdx, 3);
      expect(store.data.toJson(), legacy);
      store.applyServerState({'gold': 1300});
      expect(store.rankTrophies, 612);
      expect(store.data.gold, 1300);
      store.applyServerState({
        ...state(store, 900),
        'battleV1Rank': rank('B', 900),
      });
      expect(store.rankTrophies, 612);
    },
  );

  test(
    'fresh V1 zero does not seed its rank from a historical veteran',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('A');
      store.data.trophies = 9000;
      store.applyServerState(state(store, 0));
      expect(store.rankTrophies, 0);
      expect(store.rankArenaIdx, 0);
      expect(store.data.trophies, 9000);
    },
  );

  test(
    'rank persists only with proven owner, survives restart, and erases',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.bindAccount('A');
      store.applyServerState(state(store, 612));
      await store.flush();
      final restored = GameStore.createForTesting();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.rankTrophies, 612);
      await restored.bindAccount('B');
      expect(restored.battleRank, isNull);
      await restored.bindAccount('A');
      expect(restored.rankTrophies, 612);
      await restored.eraseLocalAccount('A');
      expect(restored.battleRank, isNull);
      expect(restored.rankTrophies, 0);
    },
  );

  test('old epoch and departed account cannot install rank', () async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.bindAccount('A');
    final stale = state(store, 612);
    store.invalidateServerStates();
    store.applyServerState(stale);
    expect(store.battleRank, isNull);
    final departed = state(store, 900);
    await store.bindAccount('B');
    store.applyServerState(departed);
    expect(store.battleRank, isNull);
  });

  test('unowned or foreign persisted projection is not transplanted', () async {
    for (final snapshot in [
      {'battleV1Rank': rank('A', 612)},
      {'accountUid': 'B', 'battleV1Rank': rank('A', 612)},
    ]) {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode(snapshot),
      });
      final store = GameStore.createForTesting();
      await store.load();
      expect(store.battleRank, isNull);
      await store.bindAccount('C');
      expect(store.battleRank, isNull);
      store.dispose();
    }
  });

  test(
    'public projection wins over legacy but cannot leak unrelated fields',
    () {
      final row =
          parsePublicPlayerProfile('A', {
            'username': 'current_name',
            'trophies': 777,
            'battleV1Rank': {...rank('A', 612), 'purchaseToken': 'secret'},
            'gold': 999,
          })!;
      expect(row['trophies'], 612);
      expect(row['battleV1Rank'], rank('A', 612));
      expect(row.containsKey('gold'), isFalse);
      expect(
        () => parsePublicPlayerProfile('A', {
          'username': 'current_name',
          'battleV1Rank': rank('B', 612),
        }),
        throwsFormatException,
      );
    },
  );

  test('late online state cannot update a new account rank', () async {
    final pending = Completer<Map<String, dynamic>>();
    final entered = Completer<void>();
    final (store, online, _) = await setup((request) async {
      entered.complete();
      return reply(await pending.future);
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    final refresh = online.refreshState();
    await entered.future;
    await store.bindAccount('B');
    pending.complete({
      'ok': true,
      'state': {'battleV1Rank': rank('first', 612)},
    });
    await expectLater(refresh, throwsA(anything));
    expect(store.battleRank, isNull);
  });

  testWidgets('trophies query opts into V1, season query stays historical', (
    tester,
  ) async {
    final bodies = <Map>[];
    final (store, online, _) = await setup((request) async {
      bodies.add(jsonDecode(request.body) as Map);
      return reply({'ok': true, 'mode': bodies.last['mode'], 'results': []});
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    await tester.pumpWidget(shell(RankingScreen(online: online)));
    await tester.pumpAndSettle();
    expect(bodies.single['protocolVersion'], BattleV1Rank.protocolVersion);
    await tester.tap(find.text('SEZON'));
    await tester.pumpAndSettle();
    expect(bodies.last['mode'], 'season');
    expect(bodies.last.containsKey('protocolVersion'), isFalse);
    await tester.pumpWidget(const SizedBox());
    noOverflow(tester);
  });

  for (final language in ['tr', 'en']) {
    for (final page in ['home', 'profile', 'play', 'arenas']) {
      testWidgets(
        '$page displays confirmed rank, not legacy $language at 1.5',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.instance;
          await tester.runAsync(() async {
            await store.bindAccount(null);
            await store.bindAccount('rank_view');
          });
          store.data.trophies = 777;
          store.applyServerState(state(store, 612));
          store.firstSessionMatchesStarted = 2;
          final screen = switch (page) {
            'home' => const HomeScreen(),
            'profile' => const ProfileScreen(),
            'play' => const PlayModeScreen(),
            _ => const ArenasScreen(),
          };
          await tester.pumpWidget(
            shell(screen, language: language, scale: 1.5, reduced: true),
          );
          await tester.pump(const Duration(milliseconds: 600));
          if (page != 'arenas') {
            expect(find.text('12 / 400'), findsWidgets);
          } else {
            expect(
              find.text(language == 'tr' ? '612 kupa' : '612 trophies'),
              findsOneWidget,
            );
          }
          expect(find.text('777'), findsNothing);
          noOverflow(tester);
          await capture(tester, 'rank-projection-$page-$language-320');
          store.applyServerState(state(store, 42));
          await tester.pump();
          expect(store.rankTrophies, 42);
          expect(store.data.trophies, 777);
          noOverflow(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(store.flush);
        },
      );
    }
  }
}
