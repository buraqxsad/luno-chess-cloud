/// Server epoch milliseconds must not use the bounded score/currency parser.
/// Elapsed time is monotonic so device date changes cannot move the deadline.
int seasonRemainingMillis(
  Map<String, dynamic> season, {
  int elapsedMilliseconds = 0,
}) {
  int timestamp(Object? value) =>
      value is num && value.isFinite && value > 0
          ? value.clamp(0, 8640000000000000).toInt()
          : 0;
  final end = timestamp(season['seasonEndAt']);
  final server = timestamp(season['serverTime']);
  if (end == 0 || server == 0) return 0;
  final elapsed = elapsedMilliseconds < 0 ? 0 : elapsedMilliseconds;
  return (end - server - elapsed).clamp(0, 8640000000000000).toInt();
}
