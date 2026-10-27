bool validPassPurchaseSeason(Object? value) =>
    value is String && RegExp(r'^s[1-9][0-9]{0,8}$').hasMatch(value);

class PassPremiumPurchase {
  const PassPremiumPurchase({required this.seasonId, required this.requestId});
  final String seasonId;
  final String requestId;

  bool get isValid =>
      validPassPurchaseSeason(seasonId) &&
      RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(requestId);

  factory PassPremiumPurchase.fromJson(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        value['version'] != 1 ||
        value['seasonId'] is! String ||
        value['requestId'] is! String) {
      throw const FormatException('Invalid Premium purchase journal');
    }
    final result = PassPremiumPurchase(
      seasonId: value['seasonId'] as String,
      requestId: value['requestId'] as String,
    );
    if (!result.isValid) {
      throw const FormatException('Invalid Premium purchase journal');
    }
    return result;
  }
  Map<String, Object> toJson() => {
    'version': 1,
    'seasonId': seasonId,
    'requestId': requestId,
  };
}
