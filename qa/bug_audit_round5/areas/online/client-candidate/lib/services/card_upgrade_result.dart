Map<String, dynamic> validateCardUpgradeResult(
  Map<String, dynamic> result,
  String family,
  int targetLevel,
) {
  final state = result['state'];
  final levels = state is Map ? state['cardLevel'] : null;
  final confirmed = levels is Map ? levels[family] : null;
  // A retry may return a newer level, but must never downgrade the request.
  if (targetLevel < 2 ||
      targetLevel > 3 ||
      result['ok'] != true ||
      result['family'] != family ||
      result['targetLevel'] != targetLevel ||
      state is! Map ||
      confirmed is! int ||
      confirmed < targetLevel ||
      confirmed > 3) {
    throw const FormatException('Unconfirmed card upgrade');
  }
  return Map<String, dynamic>.from(state);
}
