import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:luno_chess/services/luno_billing_models.dart';
import 'package:luno_chess/services/luno_google_play_billing_adapter.dart';

class FakePurchases extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  List<ProductDetails> details = [];
  IAPError? queryError;
  PurchaseParam? param;
  bool? autoConsumed;
  int completions = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: details, notFoundIDs: [], error: queryError);
  @override
  Future<bool> buyConsumable({required PurchaseParam purchaseParam, bool autoConsume = true}) async {
    param = purchaseParam;
    autoConsumed = autoConsume;
    return true;
  }
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    param = purchaseParam;
    return true;
  }
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async { completions++; }
}

class FakeAndroid extends Fake implements InAppPurchaseAndroidPlatformAddition {
  List<GooglePlayPurchaseDetails> owned = [];
  String? queryAccount;
  int consumptions = 0;
  @override
  Future<QueryPurchaseDetailsResponse> queryPastPurchases({String? applicationUserName}) async {
    queryAccount = applicationUserName;
    return QueryPurchaseDetailsResponse(pastPurchases: owned);
  }
  @override
  Future<BillingResultWrapper> consumePurchase(PurchaseDetails purchase) async {
    consumptions++;
    return const BillingResultWrapper(responseCode: BillingResponse.ok);
  }
}

List<GooglePlayProductDetails> subscriptionPlans({
  String id = 'luno_premium_month',
  String period = 'P1M',
  int basePlans = 1,
  bool trial = false,
}) => GooglePlayProductDetails.fromProductDetails(ProductDetailsWrapper(
  description: 'Membership', name: 'Premium', productId: id,
  productType: ProductType.subs, title: 'Premium (Luno)',
  subscriptionOfferDetails: List.generate(basePlans, (index) =>
    SubscriptionOfferDetailsWrapper(
      basePlanId: 'plan-$index', offerId: trial ? 'trial' : null,
      offerTags: const [], offerIdToken: 'store-offer-$index',
      pricingPhases: [PricingPhaseWrapper(
        billingCycleCount: 0, billingPeriod: period, formattedPrice: 'TRY 129,99',
        priceAmountMicros: 129990000, priceCurrencyCode: 'TRY',
        recurrenceMode: RecurrenceMode.infiniteRecurring,
      )],
    )),
));

GooglePlayPurchaseDetails ownedPurchase(PurchaseStateWrapper state) =>
    GooglePlayPurchaseDetails.fromPurchase(PurchaseWrapper(
      orderId: 'order', packageName: 'com.luno.chess', purchaseTime: 1,
      purchaseToken: 'private-owned-token', signature: '',
      products: const ['luno_gold_1000'], isAutoRenewing: false,
      originalJson: '{}', isAcknowledged: false, purchaseState: state,
      obfuscatedAccountId: 'hashed-owner',
    )).single;

void main() {
  late FakePurchases purchases;
  late FakeAndroid android;
  late LunoGooglePlayBillingAdapter adapter;
  setUp(() {
    purchases = FakePurchases();
    android = FakeAndroid();
    adapter = LunoGooglePlayBillingAdapter(purchases: purchases, android: android, supported: true);
  });
  tearDown(() async { await purchases.updates.close(); });

  test('adapter returns real localized price from one regular monthly base plan', () async {
    purchases.details = subscriptionPlans();
    final result = await adapter.queryProducts({'luno_premium_month', 'luno_premium_year'});
    expect(result.products.single.localizedPrice, 'TRY 129,99');
    expect(result.products.single.rawPrice, 129.99);
    expect(result.products.single.currencyCode, 'TRY');
    expect(result.products.single.billingPeriod, 'P1M');
    expect(result.missingProductIds, {'luno_premium_year'});
    await adapter.launch(result.products.single, 'sha256-owner');
    expect(purchases.param!.applicationUserName, 'sha256-owner');
    expect(purchases.param!.productDetails, same(purchases.details.single));
    expect(purchases.completions, 0);
    expect(android.consumptions, 0);
  });

  test('yearly base plan is not mistaken for monthly pricing', () async {
    purchases.details = subscriptionPlans(id: 'luno_premium_year', period: 'P1Y');
    final result = await adapter.queryProducts({'luno_premium_year'});
    expect(result.products.single.billingPeriod, 'P1Y');
  });

  for (final kind in ['trial', 'ambiguous', 'wrong-period']) {
    test('rejects $kind membership price rather than guessing a plan', () async {
      purchases.details = subscriptionPlans(
        trial: kind == 'trial', basePlans: kind == 'ambiguous' ? 2 : 1,
        period: kind == 'wrong-period' ? 'P1Y' : 'P1M',
      );
      final result = await adapter.queryProducts({'luno_premium_month'});
      expect(result.products, isEmpty);
      expect(result.missingProductIds, {'luno_premium_month'});
    });
  }

  test('consumables explicitly disable autoConsume and never acknowledge locally', () async {
    purchases.details = [ProductDetails(id: 'luno_gold_1000', title: 'Gold',
      description: '1000', price: 'TRY 49,99', rawPrice: 49.99, currencyCode: 'TRY')];
    final result = await adapter.queryProducts({'luno_gold_1000'});
    expect(await adapter.launch(result.products.single, 'sha256-owner'), true);
    expect(purchases.autoConsumed, false);
    expect(purchases.param!.applicationUserName, 'sha256-owner');
    expect(purchases.completions, 0);
    expect(android.consumptions, 0);
  });

  test('owned query preserves pending state and account metadata', () async {
    android.owned = [ownedPurchase(PurchaseStateWrapper.pending)];
    final owned = await adapter.queryOwned('sha256-owner');
    expect(android.queryAccount, 'sha256-owner');
    expect(owned.single.status, LunoPlayPurchaseStatus.pending);
    expect(owned.single.obfuscatedAccountId, 'hashed-owner');
    expect(owned.single.toString(), isNot(contains(owned.single.purchaseToken)));
    expect(android.consumptions, 0);
    expect(purchases.completions, 0);
  });

  test('stream maps only Google Play tokens and never completes a stream receipt', () async {
    final batches = <List<LunoPlayPurchase>>[];
    final subscription = adapter.purchaseStream.listen(batches.add);
    purchases.updates.add([ownedPurchase(PurchaseStateWrapper.purchased)]);
    expect(batches.single.single.status, LunoPlayPurchaseStatus.purchased);
    expect(batches.single.single.purchaseToken.isNotEmpty, true);
    expect(purchases.completions, 0);
    expect(android.consumptions, 0);
    await subscription.cancel();
  });

  test('raw store errors are sanitized even when they contain receipt text', () async {
    purchases.queryError = IAPError(source: 'google_play', code: 'private-owned-token',
      message: 'private-owned-token');
    await expectLater(adapter.queryProducts({'luno_gold_1000'}),
      throwsA(isA<LunoBillingFailure>().having((e) => e.toString(),
        'redacted error', isNot(contains('private-owned-token')))));
  });

  test('unsupported platform never opens an Apple or web purchase flow', () async {
    adapter = LunoGooglePlayBillingAdapter(purchases: purchases, supported: false);
    expect(await adapter.isAvailable(), false);
    await expectLater(adapter.queryOwned('sha256-owner'),
      throwsA(isA<LunoBillingFailure>()));
  });
}
