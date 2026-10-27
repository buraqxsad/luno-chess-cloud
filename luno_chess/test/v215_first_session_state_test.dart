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
    addTearDown(store.dispose);
    await store.load();
    return store;
  }

  test('start abandon retry never becomes second or earns inventory', () async {
    final store = await fresh();
    final before = store.data.toJson();
    final revision = store.accountBindingRevision;
    expect(store.firstSessionPhase, 'none');
    for (var attempt = 0; attempt < 20; attempt++) {
      expect(store.recordFirstSessionMatchStart(revision), 1);
      expect(store.firstSessionPhase, 'firstStarted');
      expect(store.needsFirstSessionMatch, isTrue);
    }
    expect(store.data.toJson(), before);
    await store.flush();
    final restored = await fresh();
    expect(restored.firstSessionPhase, 'firstStarted');
    expect(restored.needsFirstSessionMatch, isTrue);
  });

  test(
    'completion explicit once, then second start, restart persists',
    () async {
      final store = await fresh();
      final revision = store.accountBindingRevision;
      final before = store.data.toJson();
      expect(store.recordFirstSessionMatchCompletion(revision), isFalse);
      expect(store.recordFirstSessionMatchStart(revision), 1);
      expect(store.recordFirstSessionMatchCompletion(revision), isTrue);
      expect(store.firstSessionPhase, 'firstCompleted');
      expect(store.recordFirstSessionMatchCompletion(revision), isFalse);
      await store.flush();
      final restored = await fresh();
      expect(restored.firstSessionPhase, 'firstCompleted');
      expect(restored.needsFirstSessionMatch, isFalse);
      expect(
        restored.recordFirstSessionMatchStart(restored.accountBindingRevision),
        2,
      );
      expect(restored.firstSessionPhase, 'secondStarted');
      expect(
        restored.recordFirstSessionMatchStart(restored.accountBindingRevision),
        0,
      );
      expect(restored.data.toJson(), PlayerData.fromJson(before).toJson());
    },
  );

  test('completion and start callbacks cannot cross account', () async {
    final store = await fresh();
    await store.bindAccount('first');
    final old = store.accountBindingRevision;
    store.recordFirstSessionMatchStart(old);
    await store.bindAccount('second');
    expect(store.recordFirstSessionMatchCompletion(old), isFalse);
    expect(store.recordFirstSessionMatchStart(old), 0);
    expect(store.firstSessionPhase, 'none');
    await store.bindAccount('first');
    expect(store.firstSessionPhase, 'firstStarted');
    store.recordFirstSessionMatchCompletion(store.accountBindingRevision);
    await store.bindAccount('second');
    expect(store.firstSessionMatchCompleted, isFalse);
    await store.bindAccount('first');
    expect(store.firstSessionPhase, 'firstCompleted');
  });

  for (final starts in [1, 2]) {
    test(
      'V214 $starts started attempts without results remain incomplete',
      () async {
        SharedPreferences.setMockInitialValues({
          'luno_player_v1': jsonEncode({
            ...PlayerData.initial().toJson(),
            'accountUid': 'legacy',
            'tutorialCompleted': true,
            'firstSessionMatchesStarted': starts,
          }),
        });
        final store = await fresh();
        expect(store.needsFirstSessionMatch, isTrue);
        expect(
          store.recordFirstSessionMatchStart(store.accountBindingRevision),
          1,
        );
      },
    );
  }
  test('legacy recorded career results retain completed journey', () async {
    SharedPreferences.setMockInitialValues({
      'luno_player_v1': jsonEncode({
        ...PlayerData.initial().toJson(),
        'firstSessionMatchesStarted': 1,
        'gamesPlayed': 1,
      }),
    });
    final store = await fresh();
    expect(store.firstSessionMatchCompleted, isTrue);
  });
}
