import '../data/permanent_purchase.dart';

/// Validate confirmation before applying shop state or showing reward feedback.
void validateShopActionResult(Map<String, dynamic> result, {String? outcome}) {
  if (result['ok'] != true ||
      result['state'] is! Map ||
      (outcome != null && result[outcome] is! bool)) {
    throw const FormatException('Unconfirmed shop action response');
  }
  if (outcome == 'granted' && result['granted'] == true) {
    final reward = result['reward'];
    final gold = reward is Map ? reward['gold'] : null;
    if (gold is! num ||
        !gold.isFinite ||
        gold <= 0 ||
        gold != gold.roundToDouble()) {
      throw const FormatException('Invalid daily reward response');
    }
  }
  if (outcome == 'opened') {
    final rewards = result['rewards'];
    if (rewards is! List || (result['opened'] == true && rewards.isEmpty)) {
      throw const FormatException('Invalid chest reward response');
    }
    for (final reward in rewards) {
      if (reward is! Map) {
        throw const FormatException('Invalid chest reward entry');
      }
      final type = reward['type'];
      final amount = reward['amount'];
      const currencyTypes = {'gold', 'gems'};
      const collectibleTypes = {
        'card',
        'battle_card',
        'emoji',
        'skin',
        'frame_shard',
        'bioframe_shard',
      };
      if ((!currencyTypes.contains(type) && !collectibleTypes.contains(type)) ||
          amount is! num ||
          !amount.isFinite ||
          amount <= 0 ||
          amount != amount.roundToDouble()) {
        throw const FormatException('Invalid chest reward amount or type');
      }
      if (collectibleTypes.contains(type)) {
        final id = reward['id'];
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException('Missing chest collectible identity');
        }
      }
    }
  }
}

void validatePermanentPurchaseResult(
  Map<String, dynamic> result,
  String itemId,
) {
  validateShopActionResult(result, outcome: 'purchased');
  final identity = permanentPurchaseIdentity(itemId);
  final transactionId = result['transactionId'], grant = result['grant'];
  if (identity == null ||
      result['itemId'] != itemId ||
      transactionId is! String ||
      transactionId.trim().isEmpty ||
      grant is! Map ||
      grant['kind'] != identity.$1 ||
      grant['id'] != identity.$2) {
    throw const FormatException('Unconfirmed permanent purchase receipt');
  }
  const inventoryFields = {
    'piece_set': 'ownedSets',
    'skin': 'ownedSkins',
    'emoji': 'ownedEmojis',
    'frame': 'ownedFrames',
    'bio_frame': 'ownedBioFrames',
    'costume': 'ownedCostumes',
    'costume_pack': 'ownedCostumes',
  };
  final inventory = (result['state'] as Map)['inventory'];
  final owned =
      inventory is Map ? inventory[inventoryFields[identity.$1]] : null;
  if (owned is! List ||
      (identity.$1 == 'costume_pack'
          ? owned.isEmpty
          : !owned.contains(identity.$2))) {
    throw const FormatException('Missing permanent item ownership');
  }
}
