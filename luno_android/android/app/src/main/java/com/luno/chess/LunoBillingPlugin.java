package com.luno.chess;

import android.text.TextUtils;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryProductDetailsResult;
import com.android.billingclient.api.QueryPurchasesParams;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

@CapacitorPlugin(name = "LunoBilling")
public class LunoBillingPlugin extends Plugin implements PurchasesUpdatedListener {

    private static final Set<String> ALLOWED_PRODUCTS = new HashSet<>(
        Arrays.asList(
            "luno_gold_1000",
            "luno_gold_5500",
            "luno_gold_15000",
            "luno_gem_80",
            "luno_gem_500",
            "luno_gem_1500",
            "luno_premium_month",
            "luno_premium_year",
            "luno_bundle_starter",
            "luno_bundle_pro"
        )
    );

    private final Object connectionLock = new Object();
    private final Object purchaseLock = new Object();
    private final List<ReadyRequest> readyQueue = new ArrayList<>();

    private BillingClient billingClient;
    private boolean connecting;
    private PluginCall pendingPurchaseCall;
    private String pendingProductId;

    private static final class ReadyRequest {
        final PluginCall call;
        final Runnable action;

        ReadyRequest(PluginCall call, Runnable action) {
            this.call = call;
            this.action = action;
        }
    }

    @Override
    public void load() {
        // Billing is initialized on the first purchase call. Connecting during
        // Activity startup can crash vendor devices with a missing Play Store.
    }

    @PluginMethod
    public void isReady(PluginCall call) {
        JSObject result = new JSObject();
        result.put("ready", billingClient != null && billingClient.isReady());
        call.resolve(result);
    }

    @PluginMethod
    public void connect(PluginCall call) {
        whenReady(call, () -> {
            JSObject result = new JSObject();
            result.put("ready", true);
            call.resolve(result);
        });
    }

    @PluginMethod
    public void getProducts(PluginCall call) {
        whenReady(call, () -> queryProductCatalog(call));
    }

    @PluginMethod
    public void restorePurchases(PluginCall call) {
        whenReady(call, () -> queryOwnedPurchases(call));
    }

    @PluginMethod
    public void purchase(PluginCall call) {
        String productId = call.getString("productId");
        String accountId = call.getString("accountId");
        if (TextUtils.isEmpty(productId) || !ALLOWED_PRODUCTS.contains(productId)) {
            call.reject("Bilinmeyen Google Play urunu.");
            return;
        }
        String accountHash = obfuscateAccountId(accountId);
        if (accountHash == null) {
            call.reject("Guvenli oyuncu kimligi hazir degil.");
            return;
        }

        synchronized (purchaseLock) {
            if (pendingPurchaseCall != null) {
                call.reject("Baska bir satin alma islemi devam ediyor.");
                return;
            }
            pendingPurchaseCall = call;
            pendingProductId = productId;
        }

        whenReady(call, () -> queryAndLaunch(productId, accountHash, call));
    }

    private void queryAndLaunch(String productId, String accountHash, PluginCall call) {
        String productType = isSubscription(productId)
            ? BillingClient.ProductType.SUBS
            : BillingClient.ProductType.INAPP;

        QueryProductDetailsParams.Product product = QueryProductDetailsParams.Product
            .newBuilder()
            .setProductId(productId)
            .setProductType(productType)
            .build();
        QueryProductDetailsParams params = QueryProductDetailsParams
            .newBuilder()
            .setProductList(Collections.singletonList(product))
            .build();

        billingClient.queryProductDetailsAsync(
            params,
            (BillingResult result, QueryProductDetailsResult detailsResult) -> {
                if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    rejectPending(call, billingMessage("Urun bilgisi alinamadi", result));
                    return;
                }

                List<ProductDetails> detailsList = detailsResult.getProductDetailsList();
                if (detailsList == null || detailsList.isEmpty()) {
                    rejectPending(call, "Urun Google Play hesabinda etkin degil.");
                    return;
                }
                launchBillingFlow(call, detailsList.get(0), productType, accountHash);
            }
        );
    }

    private void queryProductCatalog(PluginCall call) {
        List<QueryProductDetailsParams.Product> products = new ArrayList<>();
        for (String productId : ALLOWED_PRODUCTS) {
            products.add(
                QueryProductDetailsParams.Product
                    .newBuilder()
                    .setProductId(productId)
                    .setProductType(
                        isSubscription(productId)
                            ? BillingClient.ProductType.SUBS
                            : BillingClient.ProductType.INAPP
                    )
                    .build()
            );
        }
        QueryProductDetailsParams params = QueryProductDetailsParams
            .newBuilder()
            .setProductList(products)
            .build();
        billingClient.queryProductDetailsAsync(
            params,
            (BillingResult result, QueryProductDetailsResult detailsResult) -> {
                if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    call.reject(billingMessage("Urun katalogu alinamadi", result));
                    return;
                }
                JSArray available = new JSArray();
                List<ProductDetails> details = detailsResult.getProductDetailsList();
                if (details != null) {
                    for (ProductDetails item : details) {
                        available.put(productPayload(item));
                    }
                }
                JSArray unavailable = new JSArray();
                if (detailsResult.getUnfetchedProductList() != null) {
                    for (int index = 0; index < detailsResult.getUnfetchedProductList().size(); index++) {
                        unavailable.put(detailsResult.getUnfetchedProductList().get(index).getProductId());
                    }
                }
                JSObject payload = new JSObject();
                payload.put("ready", true);
                payload.put("products", available);
                payload.put("unavailableProductIds", unavailable);
                call.resolve(payload);
            }
        );
    }

    private JSObject productPayload(ProductDetails details) {
        JSObject payload = new JSObject();
        payload.put("productId", details.getProductId());
        payload.put("productType", details.getProductType());
        payload.put("name", details.getName());
        payload.put("description", details.getDescription());

        if (BillingClient.ProductType.SUBS.equals(details.getProductType())) {
            List<ProductDetails.SubscriptionOfferDetails> offers = details.getSubscriptionOfferDetails();
            if (offers != null && !offers.isEmpty()) {
                ProductDetails.SubscriptionOfferDetails offer = offers.get(0);
                List<ProductDetails.PricingPhase> phases = offer.getPricingPhases().getPricingPhaseList();
                if (phases != null && !phases.isEmpty()) {
                    ProductDetails.PricingPhase phase = phases.get(phases.size() - 1);
                    payload.put("formattedPrice", phase.getFormattedPrice());
                    payload.put("currency", phase.getPriceCurrencyCode());
                    payload.put("priceAmountMicros", phase.getPriceAmountMicros());
                    payload.put("billingPeriod", phase.getBillingPeriod());
                }
                payload.put("basePlanId", offer.getBasePlanId());
                payload.put("offerId", offer.getOfferId());
            }
            return payload;
        }

        List<ProductDetails.OneTimePurchaseOfferDetails> offers = details.getOneTimePurchaseOfferDetailsList();
        ProductDetails.OneTimePurchaseOfferDetails offer =
            offers != null && !offers.isEmpty()
                ? offers.get(0)
                : details.getOneTimePurchaseOfferDetails();
        if (offer != null) {
            payload.put("formattedPrice", offer.getFormattedPrice());
            payload.put("currency", offer.getPriceCurrencyCode());
            payload.put("priceAmountMicros", offer.getPriceAmountMicros());
        }
        return payload;
    }

    private void queryOwnedPurchases(PluginCall call) {
        List<JSObject> purchases = new ArrayList<>();
        queryOwnedType(BillingClient.ProductType.INAPP, purchases, () ->
            queryOwnedType(BillingClient.ProductType.SUBS, purchases, () -> {
                JSArray items = new JSArray();
                for (JSObject purchase : purchases) {
                    items.put(purchase);
                }
                JSObject payload = new JSObject();
                payload.put("purchases", items);
                call.resolve(payload);
            }, call)
        , call);
    }

    private void queryOwnedType(
        String productType,
        List<JSObject> result,
        Runnable next,
        PluginCall call
    ) {
        QueryPurchasesParams params = QueryPurchasesParams
            .newBuilder()
            .setProductType(productType)
            .build();
        billingClient.queryPurchasesAsync(params, (billingResult, purchases) -> {
            if (billingResult.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                call.reject(billingMessage("Satin alma haklari okunamadi", billingResult));
                return;
            }
            if (purchases != null) {
                for (Purchase purchase : purchases) {
                    for (String productId : purchase.getProducts()) {
                        if (ALLOWED_PRODUCTS.contains(productId)) {
                            result.add(purchasePayload(purchase, productId));
                        }
                    }
                }
            }
            next.run();
        });
    }

    private void launchBillingFlow(
        PluginCall call,
        ProductDetails details,
        String productType,
        String accountHash
    ) {
        BillingFlowParams.ProductDetailsParams.Builder detailsParams =
            BillingFlowParams.ProductDetailsParams
                .newBuilder()
                .setProductDetails(details);

        String offerToken = selectOfferToken(details, productType);
        if (!TextUtils.isEmpty(offerToken)) {
            detailsParams.setOfferToken(offerToken);
        } else if (BillingClient.ProductType.SUBS.equals(productType)) {
            rejectPending(call, "Bu abonelik icin etkin bir Google Play teklifi yok.");
            return;
        }

        BillingFlowParams flowParams = BillingFlowParams
            .newBuilder()
            .setProductDetailsParamsList(
                Collections.singletonList(detailsParams.build())
            )
            .setObfuscatedAccountId(accountHash)
            .build();

        getActivity().runOnUiThread(
            () -> {
                BillingResult result = billingClient.launchBillingFlow(
                    getActivity(),
                    flowParams
                );
                if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    rejectPending(
                        call,
                        billingMessage("Google Play odemesi acilamadi", result)
                    );
                }
            }
        );
    }

    private String selectOfferToken(ProductDetails details, String productType) {
        if (BillingClient.ProductType.SUBS.equals(productType)) {
            List<ProductDetails.SubscriptionOfferDetails> offers =
                details.getSubscriptionOfferDetails();
            return offers == null || offers.isEmpty()
                ? null
                : offers.get(0).getOfferToken();
        }

        List<ProductDetails.OneTimePurchaseOfferDetails> offers =
            details.getOneTimePurchaseOfferDetailsList();
        if (offers != null && !offers.isEmpty()) {
            return offers.get(0).getOfferToken();
        }
        ProductDetails.OneTimePurchaseOfferDetails offer =
            details.getOneTimePurchaseOfferDetails();
        return offer == null ? null : offer.getOfferToken();
    }

    @Override
    public void onPurchasesUpdated(
        BillingResult billingResult,
        List<Purchase> purchases
    ) {
        PluginCall call;
        String requestedProductId;
        synchronized (purchaseLock) {
            call = pendingPurchaseCall;
            requestedProductId = pendingProductId;
        }

        if (billingResult.getResponseCode() == BillingClient.BillingResponseCode.USER_CANCELED) {
            if (call != null) {
                rejectPending(call, "Satin alma iptal edildi.");
            }
            return;
        }

        if (
            billingResult.getResponseCode() != BillingClient.BillingResponseCode.OK ||
            purchases == null ||
            purchases.isEmpty()
        ) {
            if (call != null) {
                rejectPending(
                    call,
                    billingMessage("Satin alma tamamlanamadi", billingResult)
                );
            }
            return;
        }

        Purchase purchase = findPurchase(purchases, requestedProductId);
        if (purchase == null) {
            if (call != null) {
                rejectPending(call, "Google Play farkli bir urun dondurdu.");
            }
            return;
        }

        JSObject payload = purchasePayload(purchase, requestedProductId);
        if (call != null) {
            clearPending(call);
            call.resolve(payload);
        } else {
            notifyListeners("purchaseUpdated", payload, true);
        }
    }

    private Purchase findPurchase(List<Purchase> purchases, String productId) {
        for (Purchase purchase : purchases) {
            if (productId == null || purchase.getProducts().contains(productId)) {
                return purchase;
            }
        }
        return null;
    }

    private JSObject purchasePayload(Purchase purchase, String productId) {
        JSObject payload = new JSObject();
        payload.put("productId", productId);
        payload.put("purchaseToken", purchase.getPurchaseToken());
        payload.put("orderId", purchase.getOrderId());
        payload.put("purchaseState", purchase.getPurchaseState());
        payload.put(
            "pending",
            purchase.getPurchaseState() == Purchase.PurchaseState.PENDING
        );
        payload.put("acknowledged", purchase.isAcknowledged());
        payload.put("autoRenewing", purchase.isAutoRenewing());
        payload.put("signature", purchase.getSignature());
        payload.put("originalJson", purchase.getOriginalJson());
        payload.put("verified", false);
        payload.put("requiresServerVerification", true);
        return payload;
    }

    private boolean isSubscription(String productId) {
        return productId.startsWith("luno_premium_");
    }

    private String obfuscateAccountId(String accountId) {
        if (TextUtils.isEmpty(accountId) || accountId.length() > 128) {
            return null;
        }
        try {
            byte[] digest = MessageDigest
                .getInstance("SHA-256")
                .digest(accountId.getBytes(StandardCharsets.UTF_8));
            StringBuilder value = new StringBuilder(digest.length * 2);
            for (byte current : digest) {
                value.append(String.format(java.util.Locale.ROOT, "%02x", current & 0xff));
            }
            return value.toString();
        } catch (NoSuchAlgorithmException ignored) {
            return null;
        }
    }

    private void whenReady(PluginCall call, Runnable action) {
        try {
            ensureBillingClient();
        } catch (RuntimeException error) {
            call.reject("Google Play odeme servisi baslatilamadi.", error);
            return;
        }
        boolean runNow;
        boolean shouldConnect = false;
        synchronized (connectionLock) {
            runNow = billingClient != null && billingClient.isReady();
            if (!runNow) {
                readyQueue.add(new ReadyRequest(call, action));
                if (!connecting) {
                    connecting = true;
                    shouldConnect = true;
                }
            }
        }

        if (runNow) {
            action.run();
        } else if (shouldConnect) {
            beginConnection();
        }
    }

    private void ensureBillingClient() {
        synchronized (connectionLock) {
            if (billingClient != null) {
                return;
            }
            billingClient = BillingClient
                .newBuilder(getContext())
                .setListener(this)
                .enablePendingPurchases(
                    PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
                )
                .enableAutoServiceReconnection()
                .build();
        }
    }

    private void startConnection() {
        synchronized (connectionLock) {
            if (
                billingClient == null ||
                billingClient.isReady() ||
                connecting
            ) {
                return;
            }
            connecting = true;
        }
        beginConnection();
    }

    private void beginConnection() {
        try {
            billingClient.startConnection(
                new BillingClientStateListener() {
                @Override
                public void onBillingSetupFinished(BillingResult result) {
                    List<ReadyRequest> requests;
                    synchronized (connectionLock) {
                        connecting = false;
                        requests = new ArrayList<>(readyQueue);
                        readyQueue.clear();
                    }

                    if (result.getResponseCode() == BillingClient.BillingResponseCode.OK) {
                        for (ReadyRequest request : requests) {
                            request.action.run();
                        }
                        return;
                    }

                    String message = billingMessage(
                        "Google Play magazasina baglanilamadi",
                        result
                    );
                    for (ReadyRequest request : requests) {
                        rejectPending(request.call, message);
                    }
                }

                @Override
                public void onBillingServiceDisconnected() {
                    synchronized (connectionLock) {
                        connecting = false;
                    }
                }
                }
            );
        } catch (RuntimeException error) {
            List<ReadyRequest> requests;
            synchronized (connectionLock) {
                connecting = false;
                requests = new ArrayList<>(readyQueue);
                readyQueue.clear();
            }
            for (ReadyRequest request : requests) {
                rejectPending(request.call, "Google Play odeme servisi kullanilamiyor.");
            }
        }
    }

    private String billingMessage(String prefix, BillingResult result) {
        String debug = result == null ? "" : result.getDebugMessage();
        int code = result == null ? -1 : result.getResponseCode();
        return TextUtils.isEmpty(debug)
            ? prefix + " (" + code + ")."
            : prefix + " (" + code + "): " + debug;
    }

    private void rejectPending(PluginCall call, String message) {
        clearPending(call);
        call.reject(message);
    }

    private void clearPending(PluginCall call) {
        synchronized (purchaseLock) {
            if (pendingPurchaseCall == call) {
                pendingPurchaseCall = null;
                pendingProductId = null;
            }
        }
    }

    @Override
    protected void handleOnDestroy() {
        synchronized (connectionLock) {
            for (ReadyRequest request : readyQueue) {
                request.call.reject("Google Play baglantisi kapandi.");
            }
            readyQueue.clear();
            connecting = false;
        }
        synchronized (purchaseLock) {
            if (pendingPurchaseCall != null) {
                pendingPurchaseCall.reject("Satin alma penceresi kapandi.");
            }
            pendingPurchaseCall = null;
            pendingProductId = null;
        }
        if (billingClient != null) {
            billingClient.endConnection();
            billingClient = null;
        }
        super.handleOnDestroy();
    }
}
