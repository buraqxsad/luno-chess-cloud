import 'shop_action_result.dart';
import '../data/pass_purchase.dart';

/// Require an explicit server outcome before applying state or announcing a reward.
void validatePassActionResult(Map<String, dynamic> result, String outcome) {
  if (result['ok'] != true ||
      result[outcome] is! bool ||
      result['state'] is! Map) {
    throw const FormatException('Unconfirmed Pass action response');
  }
  if (outcome == 'opened') {
    validateShopActionResult(result, outcome: 'opened');
  }
}

void validatePassPremiumPurchaseResult(
  Map<String, dynamic> result,
  String seasonId,
) {
  validatePassActionResult(result, 'purchased');
  final current = result['currentSeasonId'],
      transaction = result['transactionId'],
      grant = result['grant'];
  if (result['itemId'] != 'pass:premium' ||
      result['seasonId'] != seasonId ||
      !validPassPurchaseSeason(seasonId) ||
      !validPassPurchaseSeason(current) ||
      result['idempotent'] is! bool ||
      result['passActive'] is! bool ||
      result['passActive'] != (seasonId == current) ||
      transaction is! String ||
      transaction.trim().isEmpty ||
      grant is! Map ||
      grant['kind'] != 'pass_premium' ||
      grant['id'] != 'premium') {
    throw const FormatException('Unconfirmed season-bound Premium purchase');
  }
  final state = result['state'] as Map,
      pass = state['passState'],
      economy = state['economy'];
  final periods = economy is Map ? economy['periods'] : null,
      gems = state['gems'];
  if (pass is! Map ||
      pass['seasonKey'] != 'ranked-$current-v2' ||
      pass['premium'] is! bool ||
      (result['passActive'] == true && pass['premium'] != true) ||
      periods is! Map ||
      periods['seasonId'] != current ||
      gems is! num ||
      !gems.isFinite ||
      gems < 0 ||
      gems != gems.roundToDouble()) {
    throw const FormatException('Invalid current Pass state');
  }
}
