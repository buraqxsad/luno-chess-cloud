import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('legacy and malformed snapshots conservatively retain paid rewards', () {
    for (final raw in [null, 0, 3, '2', false]) {
      final data = PlayerData.fromJson({
        ...PlayerData.initial().toJson(),
        'passRewardVersion': raw,
        'premium': true,
        'passPremClaimed': [1, 3],
        'gems': 880,
      });
      expect(data.passRewardVersion, 1);
      expect(data.gems, 880);
      expect(data.passPremClaimed, {1, 3});
      expect(passPrem(2, rewardVersion: data.passRewardVersion).gems, 18);
    }
  });
  test(
    'future server reward version persists and stays account scoped',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.bindAccount('future');
      store.applyServerState({
        'passState': {
          'rewardVersion': 2,
          'premium': true,
          'level': 5,
          'xp': 12,
          'claimed': {
            'free': {'1': true},
            'premium': {'2': true},
          },
        },
      });
      expect(store.data.passRewardVersion, 2);
      expect(passPrem(6, rewardVersion: store.data.passRewardVersion).gems, 11);
      expect(store.data.passXp, 1262);
      await store.save();
      await store.bindAccount('other');
      expect(store.data.passRewardVersion, 1);
      await store.bindAccount('future');
      expect(store.data.passRewardVersion, 2);
      expect(store.data.passPremClaimed, {2});
      expect(PlayerData.fromJson(store.data.toJson()).passRewardVersion, 2);
    },
  );
  test(
    'unversioned authoritative season resets preview to its legacy budget',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      store.applyServerState({
        'passState': {'rewardVersion': 2},
      });
      store.applyServerState({
        'passState': {'premium': true},
      });
      expect(store.data.passRewardVersion, 1);
    },
  );
}
