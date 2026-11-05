import 'dart:async';

import 'package:flutter/foundation.dart';

/// Mirrors PRODUCT_CATALOG only; none of these IDs grant Luno Pass access.
const lunoBillingCatalog = <String, LunoBillingProductKind>{
  'luno_premium_month': LunoBillingProductKind.membership,
  'luno_premium_year': LunoBillingProductKind.membership,
  'luno_gold_1000': LunoBillingProductKind.consumable,
  'luno_gold_5500': LunoBillingProductKind.consumable,
  'luno_gold_15000': LunoBillingProductKind.consumable,
  'luno_gem_80': LunoBillingProductKind.consumable,
  'luno_gem_500': LunoBillingProductKind.consumable,
  'luno_gem_1500': LunoBillingProductKind.consumable,
  'luno_bundle_starter': LunoBillingProductKind.consumable,
  'luno_bundle_pro': LunoBillingProductKind.consumable,
};

enum LunoBillingProductKind { membership, consumable }

enum LunoBillingStatus {
  idle,
  loading,
  unavailable,
  purchasing,
  pending,
  verifying,
  queued,
  verified,
  canceled,
  error,
}

enum LunoPlayPurchaseStatus { pending, purchased, restored, canceled, error }

@immutable
class LunoBillingOwner {
  const LunoBillingOwner(this.uid, this.accountRevision);
  final String uid;
  final int accountRevision;

  bool sameAccount(LunoBillingOwner? other) =>
      other != null &&
      uid == other.uid &&
      accountRevision == other.accountRevision;
}

@immutable
class LunoBillingProduct {
  const LunoBillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.localizedPrice,
    required this.rawPrice,
    required this.currencyCode,
    this.billingPeriod,
    this.basePlanId,
    this.storeProduct,
  });

  final String id;
  final String title;
  final String description;
  final String localizedPrice;
  final double rawPrice;
  final String currencyCode;
  final String? billingPeriod;
  final String? basePlanId;
  final Object? storeProduct;
  LunoBillingProductKind? get kind => lunoBillingCatalog[id];
}

@immutable
class LunoBillingProductQuery {
  const LunoBillingProductQuery(this.products, this.missingProductIds);
  final List<LunoBillingProduct> products;
  final Set<String> missingProductIds;
}

/// Transport-only receipt. Never pass this object to UI events or telemetry.
@immutable
class LunoPlayPurchase {
  const LunoPlayPurchase({
    required this.productId,
    required this.status,
    this.purchaseToken = '',
    this.obfuscatedAccountId,
  });
  final String productId;
  final LunoPlayPurchaseStatus status;
  final String purchaseToken;
  final String? obfuscatedAccountId;

  @override
  String toString() => 'LunoPlayPurchase($productId, ${status.name}, redacted)';
}

/// Codes are fixed by the adapters/service, never raw Play/HTTP error text.
class LunoBillingFailure implements Exception {
  const LunoBillingFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
  @override
  String toString() => 'LunoBillingFailure($code)';
}

@immutable
class LunoBillingEvent {
  const LunoBillingEvent(this.status, {this.productId, this.errorCode});
  final LunoBillingStatus status;
  final String? productId;
  final String? errorCode;
}

@immutable
class LunoBillingSnapshot {
  LunoBillingSnapshot(this.owner, Map<String, dynamic> state)
    : state = Map.unmodifiable(state);
  final LunoBillingOwner owner;

  /// Unmodified server projection, including online-service owner/epoch stamps.
  final Map<String, dynamic> state;
}

abstract interface class LunoPlayBillingPort {
  Stream<List<LunoPlayPurchase>> get purchaseStream;
  Future<bool> isAvailable();
  Future<LunoBillingProductQuery> queryProducts(Set<String> ids);
  Future<bool> launch(LunoBillingProduct product, String obfuscatedAccountId);
  Future<List<LunoPlayPurchase>> queryOwned(String obfuscatedAccountId);
}

abstract interface class LunoBillingBackend implements Listenable {
  LunoBillingOwner? get currentOwner;
  bool get readyForBilling;
  Future<Map<String, dynamic>> verify(
    LunoBillingOwner owner,
    String productId,
    String purchaseToken,
  );
  Future<Map<String, dynamic>> getPlayerState(LunoBillingOwner owner);
}
