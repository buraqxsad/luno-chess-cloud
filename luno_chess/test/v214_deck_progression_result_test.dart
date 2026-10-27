import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/services/battle_v1_deck_result.dart';

const milestones = <(CardId, int)>[
  (CardId.mine, 1),
  (CardId.breakSeal, 2),
  (CardId.fog, 3),
  (CardId.manaSabotage, 4),
  (CardId.cardBlock, 5),
  (CardId.rookBend, 6),
  (CardId.angryN, 8),
  (CardId.shadowPass, 9),
  (CardId.huntVow, 10),
  (CardId.watchVow, 12),
  (CardId.echo, 13),
  (CardId.shadowContract, 15),
  (CardId.fateExchange, 17),
  (CardId.boardSeal, 20),
];

Set<CardId> ownership(int count, {Set<CardId> historical = const {}}) => {
  ...starterDeck,
  ...milestones.where((e) => e.$2 <= count).map((e) => e.$1),
  ...historical,
};

Map<String, dynamic> response(int count, Set<CardId> owned) {
  final remaining = milestones.where((e) => !owned.contains(e.$1));
  return {
    'version': 1,
    'meaningfulMatches': count,
    'targetMatches': 20,
    'path': <dynamic>[
      for (final e in milestones)
        {'card': e.$1.wire, 'matches': e.$2, 'owned': owned.contains(e.$1)},
    ],
    'nextUnlock':
        remaining.isEmpty
            ? null
            : {'card': remaining.first.$1.wire, 'matches': remaining.first.$2},
  };
}

void main() {
  test('legacy response hides progress without inventing missing rewards', () {
    expect(parseBattleV1DeckProgression(null, owned: ownership(0)), isNull);
  });

  for (var count = 0; count <= 20; count++) {
    test('verified count $count exposes only public-safe bounded progress', () {
      final owned = ownership(count);
      final result =
          parseBattleV1DeckProgression(response(count, owned), owned: owned)!;
      expect(result.meaningfulMatches, count);
      expect(result.path.length, 14);
      expect(result.unlockedCardCount, owned.length);
      expect(result.complete, count == 20);
      expect(result.progress, inInclusiveRange(0, 1));
      if (count < 20) {
        expect(result.matchesToNextUnlock, greaterThan(0));
        expect(result.nextUnlock!.owned, isFalse);
      } else {
        expect(result.nextUnlock, isNull);
        expect(
          result.progressLabel(english: true),
          'All 24 battle cards unlocked',
        );
        expect(
          result.progressLabel(english: false),
          '24 savaş kartının tamamı açık',
        );
      }
    });
  }

  test(
    'historical ownership skips previously earned cards without deleting them',
    () {
      final owned = ownership(
        0,
        historical: {CardId.mine, CardId.fog, CardId.boardSeal},
      );
      final result =
          parseBattleV1DeckProgression(response(0, owned), owned: owned)!;
      expect(result.unlockedCardCount, 13);
      expect(result.nextUnlock!.card, CardId.breakSeal);
      expect(result.matchesToNextUnlock, 2);
      final all = ownership(20);
      expect(
        parseBattleV1DeckProgression(response(0, all), owned: all)!.complete,
        isTrue,
      );
    },
  );

  test('Turkish and English display copy reflects authoritative progress', () {
    final owned = ownership(6);
    final p = parseBattleV1DeckProgression(response(6, owned), owned: owned)!;
    expect(p.progressLabel(english: false), '6 / 20 anlamlı sıralı maç');
    expect(p.progressLabel(english: true), '6 / 20 meaningful ranked matches');
    expect(
      p.nextUnlockLabel('Öfkeli At', english: false),
      'Sıradaki: Öfkeli At · 2 anlamlı sıralı maç kaldı',
    );
    expect(
      p.nextUnlockLabel('Angry Knight', english: true),
      'Next: Angry Knight · 2 meaningful ranked matches remaining',
    );
    expect(
      p.qualificationLabel(english: true),
      contains('Wins are not required'),
    );
    expect(
      p.qualificationLabel(english: false),
      contains('Galibiyet şart değil'),
    );
    expect(p.qualificationLabel(english: true), contains('clock-expired loss'));
    expect(
      p.qualificationLabel(english: false),
      contains('Süre aşımıyla kayıp'),
    );
  });

  test(
    'malformed or ownership-conflicting progress never fabricates an unlock',
    () {
      final owned = ownership(0);
      final bad = <Object?>[
        [],
        {},
        {'version': 2},
        {...response(0, owned), 'version': 1.0},
        for (final count in [-1, 21, 1.5, '1'])
          {...response(0, owned), 'meaningfulMatches': count},
        {...response(0, owned), 'path': []},
        {...response(0, owned), 'targetMatches': 99},
        {...response(0, owned), 'targetMatches': 20.0},
        {...response(0, owned), 'nextUnlock': null},
        {
          ...response(0, owned),
          'nextUnlock': {'card': 'board_seal', 'matches': 20},
        },
        {
          ...response(0, owned),
          'nextUnlock': {'card': 'mine', 'matches': 1.0},
        },
      ];
      for (final value in bad) {
        expect(
          () => parseBattleV1DeckProgression(value, owned: owned),
          throwsFormatException,
        );
      }
      for (final patch in <Map<String, dynamic>>[
        {'card': 'bogus'},
        {'card': 'radar'},
        {'matches': 0},
        {'matches': 21},
        {'matches': 1.0},
        {'owned': true},
        {'owned': 'false'},
      ]) {
        final r = response(0, owned);
        (r['path'] as List)[0] = {...(r['path'] as List)[0] as Map, ...patch};
        expect(
          () => parseBattleV1DeckProgression(r, owned: owned),
          throwsFormatException,
        );
      }
      final duplicate = response(0, owned);
      (duplicate['path'] as List)[1] = {
        'card': 'mine',
        'matches': 2,
        'owned': false,
      };
      expect(
        () => parseBattleV1DeckProgression(duplicate, owned: owned),
        throwsFormatException,
      );
      expect(
        () => parseBattleV1DeckProgression(response(0, owned), owned: {}),
        throwsFormatException,
      );
      expect(
        () => parseBattleV1DeckProgression(response(1, owned), owned: owned),
        throwsFormatException,
      );
    },
  );

  test(
    'result is immutable and does not retain response or private metadata',
    () {
      final owned = ownership(0), raw = response(0, ownership(0));
      raw['uid'] = 'private';
      raw['message'] = 'must not be retained';
      final parsed = parseBattleV1DeckProgression(raw, owned: owned)!;
      (raw['path'] as List).clear();
      raw['meaningfulMatches'] = 20;
      expect(parsed.path.length, 14);
      expect(parsed.meaningfulMatches, 0);
      expect(() => parsed.path.clear(), throwsUnsupportedError);
    },
  );
}
