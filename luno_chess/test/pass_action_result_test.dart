import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/pass_action_result.dart';

void main() {
  test('Pass chests reject malformed reward payloads', () {
    for (final rewards in [
      null,
      [],
      [null],
      [
        {'type': 'gold', 'amount': -1},
      ],
      [
        {'type': 'card', 'amount': 1},
      ],
    ]) {
      expect(
        () => validatePassActionResult({
          'ok': true,
          'opened': true,
          'state': {},
          'rewards': rewards,
        }, 'opened'),
        throwsFormatException,
      );
    }
    expect(
      () => validatePassActionResult({
        'ok': true,
        'opened': false,
        'state': {},
        'rewards': [],
      }, 'opened'),
      returnsNormally,
    );
  });
  for (final outcome in ['purchased', 'granted', 'opened']) {
    test('$outcome requires explicit server confirmation', () {
      for (final result in <Map<String, dynamic>>[
        {},
        {'ok': true, 'state': {}},
        {'ok': true, outcome: 'true', 'state': {}},
        {'ok': false, outcome: true, 'state': {}},
        {'ok': true, outcome: true},
        {'ok': true, outcome: true, 'state': []},
      ]) {
        expect(
          () => validatePassActionResult(result, outcome),
          throwsFormatException,
        );
      }
      for (final committed in [true, false]) {
        expect(
          () => validatePassActionResult({
            'ok': true,
            outcome: committed,
            'state': {},
            if (outcome == 'opened')
              'rewards': [
                {'type': 'gold', 'amount': 100},
              ],
          }, outcome),
          returnsNormally,
        );
      }
    });
  }
}
