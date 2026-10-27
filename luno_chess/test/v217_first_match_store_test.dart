import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GameStore> fresh() async {
    final store = GameStore.createForTesting();
    await store.load();
    addTearDown(() async {
      await store.flush();
      store.dispose();
    });
    return store;
  }

  Map<String, dynamic> ownedState(GameStore store, String outcome) => {
    GameStore.serverStateOwnerKey: store.accountUid,
    GameStore.serverStateEpochKey: store.serverStateEpoch,
    'stats': {outcome: 1},
  };

  for (final outcome in ['wins', 'losses', 'draws']) {
    test(
      'unseen owned online $outcome repairs and persists onboarding',
      () async {
        final store = await fresh();
        await store.bindAccount('first');
        final inventory =
            store.data.toJson()..removeWhere(
              (key, _) =>
                  {'wins', 'losses', 'draws', 'gamesPlayed'}.contains(key),
            );
        store.applyServerState(ownedState(store, outcome));
        expect(store.firstSessionPhase, 'firstCompleted');
        expect(store.needsFirstSessionMatch, isFalse);
        expect(store.firstSessionMatchesStarted, 1);
        final after =
            store.data.toJson()..removeWhere(
              (key, _) =>
                  {'wins', 'losses', 'draws', 'gamesPlayed'}.contains(key),
            );
        expect(after, inventory, reason: 'No local match rewards are minted');
        store.applyServerState(ownedState(store, outcome));
        expect(store.firstSessionMatchesStarted, 1);
        expect(store.data.gamesPlayed, 1);
        await store.flush();
        final restored = await fresh();
        expect(restored.firstSessionPhase, 'firstCompleted');
        await restored.bindAccount('second');
        expect(restored.firstSessionPhase, 'none');
        await restored.bindAccount('first');
        expect(restored.firstSessionPhase, 'firstCompleted');
      },
    );
  }

  test(
    'persisted career result repairs an explicit stale false marker',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'accountUid': 'first',
          'gamesPlayed': 1,
          'wins': 1,
          'firstSessionMatchesStarted': 0,
          'firstSessionMatchCompleted': false,
        }),
      });
      final store = await fresh();
      expect(store.firstSessionPhase, 'firstCompleted');
      expect(store.firstSessionMatchesStarted, 1);
      await store.flush();
      final restored = await fresh();
      expect(restored.needsFirstSessionMatch, isFalse);
    },
  );

  test(
    'foreign, stale, missing and malformed evidence cannot complete',
    () async {
      final store = await fresh();
      await store.bindAccount('first');
      final oldState = ownedState(store, 'wins');
      await store.bindAccount('second');
      store.applyServerState(oldState);
      expect(store.firstSessionPhase, 'none');
      await store.bindAccount('first');
      store.applyServerState(oldState);
      expect(store.firstSessionPhase, 'none');
      store.applyServerState({
        GameStore.serverStateOwnerKey: 'first',
        GameStore.serverStateEpochKey: store.serverStateEpoch,
        'stats': {'wins': 0, 'losses': -1, 'draws': '1'},
        'onboardingRewardClaimedAt': 1234,
        'firstSessionMatchCompleted': true,
      });
      expect(store.firstSessionPhase, 'none');
      store.applyServerState({'gold': store.data.gold});
      expect(
        store.firstSessionPhase,
        'none',
        reason: 'No finished match evidence',
      );
    },
  );

  test('tutorial skip persists but is not match completion evidence', () async {
    final store = await fresh();
    await store.bindAccount('first');
    await store.completeIntroduction(store.accountBindingRevision);
    await store.flush();
    final restored = await fresh();
    expect(restored.hasCompletedTutorial, isTrue);
    expect(restored.needsFirstSessionMatch, isTrue);
    final before = restored.data.toJson();
    final revision = restored.accountBindingRevision;
    expect(restored.recordFirstSessionMatchStart(revision), 1);
    expect(restored.recordFirstSessionMatchCompletion(revision), isTrue);
    expect(restored.recordFirstSessionMatchCompletion(revision), isFalse);
    expect(restored.data.toJson(), before);
    await restored.bindAccount('second');
    expect(restored.recordFirstSessionMatchCompletion(revision), isFalse);
    expect(restored.needsFirstSessionMatch, isTrue);
    await restored.bindAccount('first');
    expect(restored.firstSessionPhase, 'firstCompleted');
  });
}
