import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass.dart';

void main() {
  test('Pass claims support RTDB numeric-key maps and dense arrays', () {
    expect(passClaimedLevels({'1': 1000, '2': 2000, '4': true}), {1, 2, 4});
    expect(passClaimedLevels([null, 1000, 2000, null, true]), {1, 2, 4});
    expect(passClaimedLevels([null, null, 2000]), {2});
    expect(passClaimedLevels({}), isEmpty);
    expect(passClaimedLevels([]), isEmpty);
  });

  test('absent or malformed claim markers never hide an unclaimed reward', () {
    expect(
      passClaimedLevels({
        '0': 1000,
        '1': false,
        '2': null,
        '3': 0,
        '4': -1,
        '5': 1.5,
        '6': double.infinity,
        '7': double.nan,
        '8': '1000',
        '09': 1000,
        '+10': 1000,
        '1.0': 1000,
        '31': 1000,
        '30': 1000,
      }),
      {30},
    );
    for (final value in [null, false, 123, 'claimed']) {
      expect(passClaimedLevels(value), isEmpty);
    }
  });
}
