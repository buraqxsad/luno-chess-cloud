class ProfileMatchStats {
  final int wins;
  final int losses;
  final int draws;
  final int games;

  ProfileMatchStats({
    required int wins,
    required int games,
    int losses = 0,
    int draws = 0,
  }) : wins = _nonNegative(wins),
       losses = _nonNegative(losses),
       draws = _nonNegative(draws),
       games = _total(games, wins, losses, draws);

  static int _nonNegative(int value) => value < 0 ? 0 : value;

  static int _total(int games, int wins, int losses, int draws) {
    final classified =
        _nonNegative(wins) + _nonNegative(losses) + _nonNegative(draws);
    return games > classified ? games : classified;
  }

  // Missing legacy results are not evidence of a draw.
  int get unclassified => games - wins - losses - draws;
  int get winRate => games == 0 ? 0 : (wins * 100 / games).round();
}
