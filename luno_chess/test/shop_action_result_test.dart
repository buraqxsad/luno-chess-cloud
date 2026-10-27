import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/shop_action_result.dart';

void main() {
  test('chest rejects empty grants and malformed reward entries', () {
    for (final rewards in [
      [],
      [null],
      ['gold'],
      [
        {'type': 'gold', 'amount': -1},
      ],
      [
        {'type': 'gold', 'amount': double.nan},
      ],
      [
        {'type': 'gold', 'amount': 1.5},
      ],
      [
        {'type': 'unknown', 'amount': 1},
      ],
      [
        {'type': 'card', 'amount': 1},
      ],
      [
        {'type': 'battle_card', 'amount': 1},
      ],
      [
        {'type': 'skin', 'id': ' ', 'amount': 1},
      ],
    ]) {
      expect(
        () => validateShopActionResult({
          'ok': true,
          'state': {},
          'opened': true,
          'rewards': rewards,
        }, outcome: 'opened'),
        throwsFormatException,
      );
    }
    for (final type in [
      'gold',
      'gems',
      'card',
      'battle_card',
      'emoji',
      'skin',
      'frame_shard',
      'bioframe_shard',
    ]) {
      expect(
        () => validateShopActionResult({
          'ok': true,
          'state': {},
          'opened': true,
          'rewards': [
            {'type': type, 'amount': 1, 'id': 'item'},
          ],
        }, outcome: 'opened'),
        returnsNormally,
      );
    }
    expect(
      () => validateShopActionResult({
        'ok': true,
        'state': {},
        'opened': false,
        'rewards': [],
      }, outcome: 'opened'),
      returnsNormally,
    );
  });
  for (final outcome in <String?>[null, 'purchased', 'granted', 'opened']) {
    test('$outcome rejects unconfirmed shop responses', () {
      for (final result in <Map<String, dynamic>>[
        {},
        {'ok': false, 'state': {}, if (outcome != null) outcome: true},
        {'ok': true, if (outcome != null) outcome: true},
        {'ok': true, 'state': [], if (outcome != null) outcome: true},
        if (outcome != null) {'ok': true, 'state': {}, outcome: 'true'},
      ]) {
        expect(
          () => validateShopActionResult(result, outcome: outcome),
          throwsFormatException,
        );
      }
      for (final committed in [true, false]) {
        expect(
          () => validateShopActionResult({
            'ok': true,
            'state': {},
            if (outcome != null) outcome: committed,
            'reward': {'gold': 100},
            'rewards': [
              {'type': 'gold', 'amount': 100},
            ],
          }, outcome: outcome),
          returnsNormally,
        );
      }
    });
  }
  test('daily grant rejects missing, fractional and invalid gold', () {
    for (final gold in [null, '100', 0, -1, 1.5, double.nan, double.infinity]) {
      expect(
        () => validateShopActionResult({
          'ok': true,
          'state': {},
          'granted': true,
          'reward': {'gold': gold},
        }, outcome: 'granted'),
        throwsFormatException,
      );
    }
    expect(
      () => validateShopActionResult({
        'ok': true,
        'state': {},
        'granted': false,
        'reward': {},
      }, outcome: 'granted'),
      returnsNormally,
    );
  });
  test('chest requires a rewards list', () {
    expect(
      () => validateShopActionResult({
        'ok': true,
        'state': {},
        'opened': true,
      }, outcome: 'opened'),
      throwsFormatException,
    );
  });
}
