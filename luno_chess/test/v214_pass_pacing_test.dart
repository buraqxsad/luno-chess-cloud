import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass.dart';

void main() {
  int total(int version) => List.generate(
    kPassMaxLevel,
    (index) => passPrem(index + 1, rewardVersion: version),
  ).fold(0, (sum, tier) => sum + tier.gems);

  test('legacy and purchased preview retains the advertised 540 gems', () {
    expect(total(kPassLegacyRewardVersion), 540);
    expect(passPrem(1).gems, 18);
    for (final invalid in <Object?>[null, '', 0, 3, 2.1, true]) {
      expect(normalizePassRewardVersion(invalid), kPassLegacyRewardVersion);
    }
  });

  test('future 330 premium plus 120 free recoups exactly the 450 price', () {
    final free = List.generate(
      30,
      (i) => passFree(i + 1),
    ).fold<int>(0, (sum, tier) => sum + tier.gems);
    expect(free, 120);
    expect(total(kPassCurrentRewardVersion), 330);
    expect(free + total(kPassCurrentRewardVersion), kPassPremiumCost);
  });

  test('version change preserves gold and every content milestone', () {
    for (var level = 1; level <= 30; level++) {
      final old = passPrem(level);
      final current = passPrem(level, rewardVersion: 2);
      expect(current.gold, old.gold);
      expect(current.kind, old.kind);
      expect(current.key, old.key);
      expect(current.name, old.name);
    }
  });

  test(
    'outside-track reward requests cannot preview negative or extra tiers',
    () {
      for (final level in [-1, 0, 31, 100]) {
        expect(() => passFree(level), throwsRangeError);
        expect(() => passPrem(level), throwsRangeError);
      }
    },
  );
}
