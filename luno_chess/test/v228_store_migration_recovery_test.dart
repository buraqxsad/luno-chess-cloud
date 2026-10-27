import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (key, invalid) in [
    ('luno_player_schema_v2', 'broken schema'),
    ('luno_username_chosen_v1', 'not a bool'),
    ('luno_tutorial_completed_v1', 7),
    ('luno_tutorial_step_v1', false),
  ]) {
    test('malformed $key cannot discard a valid legacy profile', () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'username': 'legacy_player',
          'gold': 8765,
          'bio': 'legacy biography',
          'usernameChosen': true,
          'tutorialCompleted': true,
          'tutorialStep': 7,
        }),
        key: invalid,
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.data.username, 'legacy_player');
      expect(store.data.gold, 8765);
      expect(store.data.bio, 'legacy biography');
      expect(store.hasChosenUsername, true);
      expect(store.hasCompletedTutorial, true);
      expect(store.tutorialStep, 7);
      await store.bindAccount('A');
      final snapshot =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'luno_player_v1',
                )!,
              )
              as Map;
      expect(snapshot['accountUid'], 'A');
      expect(snapshot['bio'], 'legacy biography');
      expect(snapshot['gold'], 8765);
    });
  }

  test('malformed schema metadata preserves a known active account', () async {
    SharedPreferences.setMockInitialValues({
      'luno_player_v1': jsonEncode({
        ...PlayerData.initial().toJson(),
        'accountUid': 'A',
        'bio': 'owned biography',
        'usernameChosen': true,
        'tutorialCompleted': true,
      }),
      'luno_player_schema_v2': false,
    });
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.load();
    expect(store.accountUid, 'A');
    expect(store.data.bio, 'owned biography');
    expect(store.hasChosenUsername, true);
    expect(store.hasCompletedTutorial, true);
  });

  test(
    'valid legacy auxiliary values retain their existing priority',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'usernameChosen': true,
          'tutorialCompleted': true,
          'tutorialStep': 7,
        }),
        'luno_username_chosen_v1': false,
        'luno_tutorial_completed_v1': false,
        'luno_tutorial_step_v1': 2,
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.hasChosenUsername, false);
      expect(store.hasCompletedTutorial, false);
      expect(store.tutorialStep, 2);
    },
  );
}
