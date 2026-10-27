import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/profile_update_result.dart';

void main() {
  const submitted = {'country': 'JP', 'avatarEmoji': 'av_knight', 'bio': ''};

  test('profile confirmation accepts an explicitly cleared biography', () {
    final state = {
      'profile': {...submitted},
    };
    expect(
      validateProfileUpdateResult({'ok': true, 'state': state}, submitted),
      state,
    );
  });

  test('profile confirmation rejects missing or unsuccessful responses', () {
    for (final response in <Map<String, dynamic>>[
      {},
      {
        'ok': false,
        'state': {'profile': submitted},
      },
      {'ok': true},
      {'ok': true, 'state': {}},
      {
        'ok': true,
        'state': {'profile': {}},
      },
    ]) {
      expect(
        () => validateProfileUpdateResult(response, submitted),
        throwsFormatException,
      );
    }
  });

  test('every submitted field must be confirmed without stale values', () {
    for (final key in submitted.keys) {
      for (final value in [null, 1, 'stale']) {
        expect(
          () => validateProfileUpdateResult({
            'ok': true,
            'state': {
              'profile': {...submitted, key: value},
            },
          }, submitted),
          throwsFormatException,
        );
      }
    }
  });
}
