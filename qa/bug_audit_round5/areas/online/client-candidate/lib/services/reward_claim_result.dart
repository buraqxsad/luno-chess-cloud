/// Returns whether this request granted a reward, before callers apply state.
bool validateRewardClaimResult(Map<String, dynamic> result) {
  if (result['ok'] != true ||
      result['granted'] is! bool ||
      result['state'] is! Map ||
      result['reward'] is! Map) {
    throw const FormatException('Unconfirmed reward claim');
  }
  return result['granted'] == true;
}
