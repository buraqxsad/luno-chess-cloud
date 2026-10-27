import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/card_upgrade_result.dart';

void main() {
  Map<String, dynamic> response([int level = 2]) => {
    'ok': true,
    'family': 'trap',
    'targetLevel': 2,
    'state': {
      'cardLevel': {'trap': level},
      'gold': 500,
    },
  };

  test('accepts confirmed upgrade and already-applied retry', () {
    expect(validateCardUpgradeResult(response(), 'trap', 2)['gold'], 500);
    expect(validateCardUpgradeResult(response(3), 'trap', 2)['cardLevel'], {
      'trap': 3,
    });
  });
  test('rejects wrong family, target and unsuccessful replies', () {
    for (final change in [
      {'ok': false},
      {'family': 'radar'},
      {'targetLevel': 3},
      {'state': null},
      {'state': <String, dynamic>{}},
    ]) {
      expect(
        () => validateCardUpgradeResult({...response(), ...change}, 'trap', 2),
        throwsFormatException,
      );
    }
  });
  test('rejects absent, fractional, stale and invalid levels', () {
    for (final level in [null, 1, 4, '2', 2.5, double.nan]) {
      final result = response();
      result['state'] = {
        'cardLevel': {'trap': level},
      };
      expect(
        () => validateCardUpgradeResult(result, 'trap', 2),
        throwsFormatException,
      );
    }
    for (final target in [0, 1, 4]) {
      expect(
        () => validateCardUpgradeResult(response(), 'trap', target),
        throwsFormatException,
      );
    }
  });
}
