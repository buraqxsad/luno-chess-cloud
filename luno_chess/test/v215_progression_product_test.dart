import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/services/battle_v1_deck_result.dart';
import 'package:luno_chess/services/battle_welcome_reward.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'v214_deck_progression_result_test.dart' show milestones, ownership;

Map<String, dynamic> modernProgress(int count, int days, bool welcome) {
  final owned = {
    ...ownership(count),
    if (welcome) CardId.mine,
    if (days >= 2) CardId.breakSeal,
    if (days >= 3) CardId.fog,
  };
  final path = [
    for (final item in milestones)
      {
        'card': item.$1.wire,
        'matches': item.$2,
        'owned': owned.contains(item.$1),
        'requirements': {
          'anyOf': [
            {'kind': 'ranked_matches', 'current': count, 'target': item.$2},
            if (item.$1 == CardId.mine)
              {
                'kind': 'welcome_claim',
                'current': welcome ? 1 : 0,
                'target': 1,
              },
            if (item.$1 == CardId.breakSeal || item.$1 == CardId.fog)
              {'kind': 'daily_claim_days', 'current': days, 'target': item.$2},
          ],
        },
      },
  ];
  return {
    'version': 2,
    'meaningfulMatches': count,
    'targetMatches': 20,
    'early': {'welcomeClaimed': welcome, 'distinctDailyClaims': days},
    'path': path,
    'nextUnlock': path.where((item) => item['owned'] == false).firstOrNull,
  };
}

void main() {
  for (var count = 0; count <= 20; count++) {
    for (var days = 0; days <= 3; days++) {
      for (final welcome in [false, true]) {
        test('early OR progression $count/$days/$welcome', () {
          final raw = modernProgress(count, days, welcome);
          final owned = {
            ...ownership(count),
            if (welcome) CardId.mine,
            if (days >= 2) CardId.breakSeal,
            if (days >= 3) CardId.fog,
          };
          final result = parseBattleV1DeckProgression(raw, owned: owned)!;
          expect(result.unlockedCardCount, owned.length);
          expect(result.hasEarlyUnlocks, isTrue);
          expect(result.path, hasLength(14));
          expect(result.path.map((entry) => entry.card).toSet(), hasLength(14));
          for (final entry in result.path.where((entry) => !entry.owned)) {
            expect(
              entry.requirements.every((r) => r.current < r.target),
              isTrue,
            );
          }
        });
      }
    }
  }
  test('unlock conditions are exact OR choices in both languages', () {
    final result =
        parseBattleV1DeckProgression(
          modernProgress(0, 0, false),
          owned: ownership(0),
        )!;
    expect(
      result.path.first.conditionLabel(english: true),
      '1 meaningful ranked matches OR Claim the one-time welcome reward',
    );
    expect(
      result.path.first.conditionLabel(english: false),
      contains(' VEYA '),
    );
    expect(
      result.path[1].conditionLabel(english: true),
      contains('2 different UTC days'),
    );
    expect(
      result.path[2].conditionLabel(english: true),
      contains('3 different UTC days'),
    );
  });
  test(
    'inconsistent or malformed early requirements cannot show fake ownership',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (raw) => (raw['early'] as Map)['distinctDailyClaims'] = 4,
        (raw) => (raw['early'] as Map)['welcomeClaimed'] = true,
        (raw) =>
            ((raw['path'][0]['requirements']['anyOf'] as List)[0]
                    as Map)['current'] =
                20,
        (raw) =>
            ((raw['path'][0]['requirements']['anyOf'] as List)[0]
                    as Map)['kind'] =
                'offline_wins',
      ]) {
        final raw =
            jsonDecode(jsonEncode(modernProgress(0, 0, false)))
                as Map<String, dynamic>;
        mutate(raw);
        expect(
          () => parseBattleV1DeckProgression(raw, owned: ownership(0)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'welcome receipt accepts confirmed fresh/replayed gift, never local win flags',
    () {
      Map<String, dynamic> response(bool granted) => {
        'ok': true,
        'granted': granted,
        'idempotent': !granted,
        'welcome': {
          'version': 1,
          'claimed': true,
          'card': 'mine',
          'eligibility': 'account_welcome',
        },
        'reward': {'gold': 500},
        'state': {'gold': 1750},
      };
      expect(BattleWelcomeReward.fromResponse(response(true)).granted, isTrue);
      expect(
        BattleWelcomeReward.fromResponse(response(false)).granted,
        isFalse,
      );
      expect(
        () =>
            BattleWelcomeReward.fromResponse({'ok': true, 'wonOffline': true}),
        throwsFormatException,
      );
      final forged = response(true)..['reward'] = {'gold': 500, 'gems': 999};
      expect(
        () => BattleWelcomeReward.fromResponse(forged),
        throwsFormatException,
      );
    },
  );
  test(
    'Premium membership and seasonal paid Pass are separate persisted projections',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.bindAccount('member');
      store.applyServerState({
        'membership': {'active': true, 'expiresAt': 2000000000000},
        'passState': {'premium': false},
      });
      expect(store.data.isMembershipActive, isTrue);
      expect(store.data.premium, isFalse);
      final restored = PlayerData.fromJson(store.data.toJson());
      expect(restored.isMembershipActive, isTrue);
      expect(restored.premiumUntil, 2000000000000);
      store.applyServerState({
        'membership': {'active': false, 'expiresAt': 1000},
        'passState': {'premium': true},
      });
      expect(store.data.isMembershipActive, isFalse);
      expect(store.data.premium, isTrue);
      await store.bindAccount('other');
      expect(store.data.isMembershipActive, isFalse);
      expect(store.data.premium, isFalse);
    },
  );
}
