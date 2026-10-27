class BattleWelcomeReward {
  final bool granted;
  const BattleWelcomeReward._(this.granted);

  factory BattleWelcomeReward.fromResponse(Map<String, dynamic> response) {
    final welcome = response['welcome'], reward = response['reward'];
    if (response['ok'] != true ||
        response['granted'] is! bool ||
        response['idempotent'] is! bool ||
        welcome is! Map ||
        welcome['version'] != 1 ||
        welcome['claimed'] != true ||
        welcome['card'] != 'mine' ||
        welcome['eligibility'] != 'account_welcome' ||
        reward is! Map ||
        reward['gold'] != 500 ||
        reward.keys.any((key) => key != 'gold') ||
        response['state'] is! Map) {
      throw const FormatException('Unconfirmed welcome reward');
    }
    return BattleWelcomeReward._(response['granted'] == true);
  }
}
