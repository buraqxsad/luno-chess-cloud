import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/season_clock.dart';

void main() {
  const server = 1800000000000;
  const week = 7 * 86400000;
  test('modern epoch milliseconds preserve the full season duration', () {
    expect(
      seasonRemainingMillis({
        'serverTime': server,
        'seasonEndAt': server + week,
      }),
      week,
    );
  });
  test(
    'monotonic elapsed time reduces remaining time without device dates',
    () {
      final season = {'serverTime': server, 'seasonEndAt': server + week};
      expect(
        seasonRemainingMillis(season, elapsedMilliseconds: 3600000),
        week - 3600000,
      );
      expect(seasonRemainingMillis(season, elapsedMilliseconds: week + 1), 0);
      expect(seasonRemainingMillis(season, elapsedMilliseconds: -1), week);
    },
  );
  test('expired missing and non-finite timestamps are safe', () {
    expect(
      seasonRemainingMillis({'serverTime': server, 'seasonEndAt': server - 1}),
      0,
    );
    expect(seasonRemainingMillis({}), 0);
    expect(
      seasonRemainingMillis({'serverTime': double.nan, 'seasonEndAt': server}),
      0,
    );
    expect(
      seasonRemainingMillis({
        'serverTime': server,
        'seasonEndAt': double.infinity,
      }),
      0,
    );
  });
}
