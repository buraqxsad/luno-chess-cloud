import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/profile_match_stats.dart';

void main() {
  test('legacy unknown results do not become draws', () {
    final stats = ProfileMatchStats(wins: 3, losses: 1, draws: 2, games: 10);
    expect(stats.draws, 2);
    expect(stats.unclassified, 4);
    expect(stats.games, 10);
    expect(stats.winRate, 30);
  });

  test('missing or stale total does not erase known victories', () {
    for (final total in [-1, 0, 2]) {
      final stats = ProfileMatchStats(wins: 8, games: total);
      expect(stats.wins, 8);
      expect(stats.games, 8);
      expect(stats.winRate, 100);
    }
  });

  test('all count combinations remain nonnegative and consistent', () {
    for (final wins in [-10, 0, 1, 17, 100]) {
      for (final losses in [-4, 0, 3, 50]) {
        for (final draws in [-1, 0, 2, 9]) {
          for (final games in [-5, 0, 6, 100, 1000]) {
            final stats = ProfileMatchStats(
              wins: wins,
              losses: losses,
              draws: draws,
              games: games,
            );
            expect(
              stats.games,
              stats.wins + stats.losses + stats.draws + stats.unclassified,
            );
            expect(stats.unclassified, greaterThanOrEqualTo(0));
            expect(stats.winRate, inInclusiveRange(0, 100));
          }
        }
      }
    }
  });
}
