import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'luno_billing_models.dart';

/// Android-only. Server fulfillment owns acknowledgement and consumption.
class LunoGooglePlayBillingAdapter implements LunoPlayBillingPort {
  LunoGooglePlayBillingAdapter({
    InAppPurchase? purchases,
    InAppPurchaseAndroidPlatformAddition? android,
    bool? supported,
  }) : _purchasesOverride = purchases,
       _androidOverride = android,
       _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final InAppPurchase? _purchasesOverride;
  final InAppPurchaseAndroidPlatformAddition? _androidOverride;
  final bool _supported;
  InAppPurchase get _purchases => _purchasesOverride ?? InAppPurchase.instance;
  InAppPurchaseAndroidPlatformAddition get _android =>
      _androidOverride ??
      _purchases.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();

  void _requireAndroid() {
    if (!_supported) throw const LunoBillingFailure('unsupported-platform');
  }

  @override
  Stream<List<LunoPlayPurchase>> get purchaseStream {
    if (!_supported) return const Stream.empty();
    return _purchases.purchaseStream.map(
      (batch) => batch.map(_receipt).toList(growable: false),
    );
  }

  @override
  Future<bool> isAvailable() async {
    if (!_supported) return false;
    try {
      return await _purchases.isAvailable();
    } catch (_) {
      throw const LunoBillingFailure('store-unavailable', retryable: true);
    }
  }

  @override
  Future<LunoBillingProductQuery> queryProducts(Set<String> ids) async {
    _requireAndroid();
    try {
      final response = await _purchases.queryProductDetails(ids);
      if (response.error != null) {
        throw const LunoBillingFailure('product-query-failed', retryable: true);
      }
      final candidates = <String, List<LunoBillingProduct>>{};
      for (final details in response.productDetails) {
        if (!ids.contains(details.id) ||
            !lunoBillingCatalog.containsKey(details.id)) {
          continue;
        }
        final product = _product(details);
        if (product != null) {
          candidates.putIfAbsent(details.id, () => []).add(product);
        }
      }
      // Ambiguous plans are not silently selected or priced as a trial.
      final products = candidates.values
          .where((plans) => plans.length == 1)
          .map((plans) => plans.single)
          .toList(growable: false);
      return LunoBillingProductQuery(
        List.unmodifiable(products),
        Set.unmodifiable(ids.difference(products.map((p) => p.id).toSet())),
      );
    } on LunoBillingFailure {
      rethrow;
    } catch (_) {
      throw const LunoBillingFailure('product-query-failed', retryable: true);
    }
  }

  LunoBillingProduct? _product(ProductDetails details) {
    String? period;
    String? plan;
    if (lunoBillingCatalog[details.id] == LunoBillingProductKind.membership) {
      if (details is! GooglePlayProductDetails) return null;
      final index = details.subscriptionIndex;
      final offers = details.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) {
        return null;
      }
      final offer = offers[index];
      if (offer.offerId != null ||
          offer.installmentPlanDetails != null ||
          offer.pricingPhases.length != 1) {
        return null;
      }
      period = offer.pricingPhases.single.billingPeriod;
      final expected = details.id == 'luno_premium_month' ? 'P1M' : 'P1Y';
      if (period != expected || details.offerToken == null) return null;
      plan = offer.basePlanId;
    }
    if (details.price.isEmpty ||
        details.currencyCode.isEmpty ||
        !details.rawPrice.isFinite ||
        details.rawPrice <= 0) {
      return null;
    }
    return LunoBillingProduct(
      id: details.id,
      title: details.title,
      description: details.description,
      localizedPrice: details.price,
      rawPrice: details.rawPrice,
      currencyCode: details.currencyCode,
      billingPeriod: period,
      basePlanId: plan,
      storeProduct: details,
    );
  }

  @override
  Future<bool> launch(
    LunoBillingProduct product,
    String obfuscatedAccountId,
  ) async {
    _requireAndroid();
    final details = product.storeProduct;
    if (details is! ProductDetails ||
        details.id != product.id ||
        product.kind == null) {
      throw const LunoBillingFailure('product-unavailable');
    }
    final param = GooglePlayPurchaseParam(
      productDetails: details,
      applicationUserName: obfuscatedAccountId,
    );
    try {
      if (product.kind == LunoBillingProductKind.consumable) {
        return await _purchases.buyConsumable(
          purchaseParam: param,
          autoConsume: false,
        );
      }
      return await _purchases.buyNonConsumable(purchaseParam: param);
    } catch (_) {
      throw const LunoBillingFailure('purchase-launch-failed');
    }
  }

  @override
  Future<List<LunoPlayPurchase>> queryOwned(String obfuscatedAccountId) async {
    _requireAndroid();
    try {
      // Generic restore overwrites pending with restored; this API preserves it.
      final response = await _android.queryPastPurchases(
        applicationUserName: obfuscatedAccountId,
      );
      if (response.error != null) {
        throw const LunoBillingFailure('restore-query-failed', retryable: true);
      }
      return response.pastPurchases.map(_receipt).toList(growable: false);
    } on LunoBillingFailure {
      rethrow;
    } catch (_) {
      throw const LunoBillingFailure('restore-query-failed', retryable: true);
    }
  }

  LunoPlayPurchase _receipt(PurchaseDetails purchase) => LunoPlayPurchase(
    productId: purchase.productID,
    status: switch (purchase.status) {
      PurchaseStatus.pending => LunoPlayPurchaseStatus.pending,
      PurchaseStatus.purchased => LunoPlayPurchaseStatus.purchased,
      PurchaseStatus.restored => LunoPlayPurchaseStatus.restored,
      PurchaseStatus.canceled => LunoPlayPurchaseStatus.canceled,
      PurchaseStatus.error => LunoPlayPurchaseStatus.error,
    },
    purchaseToken:
        purchase.verificationData.source == 'google_play'
            ? purchase.verificationData.serverVerificationData
            : '',
    obfuscatedAccountId:
        purchase is GooglePlayPurchaseDetails
            ? purchase.billingClientPurchase.obfuscatedAccountId
            : null,
  );
}
