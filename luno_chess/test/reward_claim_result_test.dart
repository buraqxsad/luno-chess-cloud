import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/reward_claim_result.dart';

void main() {
  test('new and duplicate claims are distinguished', () {
    for (final granted in [true, false]) {
      expect(
        validateRewardClaimResult({
          'ok': true,
          'granted': granted,
          'state': {},
          'reward': {},
        }),
        granted,
      );
    }
  });
  test('missing or wrongly typed confirmation fails closed', () {
    final valid = <String, dynamic>{
      'ok': true,
      'granted': true,
      'state': {},
      'reward': {},
    };
    for (final field in valid.keys) {
      final missing = Map<String, dynamic>.from(valid)..remove(field);
      expect(() => validateRewardClaimResult(missing), throwsFormatException);
    }
    for (final invalid in [
      {...valid, 'ok': false},
      {...valid, 'granted': 'true'},
      {...valid, 'state': []},
      {...valid, 'reward': []},
    ]) {
      expect(() => validateRewardClaimResult(invalid), throwsFormatException);
    }
  });
}
