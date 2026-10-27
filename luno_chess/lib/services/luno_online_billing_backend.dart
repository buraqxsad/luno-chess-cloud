import 'package:flutter/foundation.dart';

import 'luno_billing_models.dart';
import 'luno_online_service.dart';

/// Reuses existing Firebase Auth, App Check, request IDs and bounded API retries.
class LunoOnlineBillingBackend implements LunoBillingBackend {
  LunoOnlineBillingBackend(this.online);
  final LunoOnlineService online;

  @override
  LunoBillingOwner? get currentOwner {
    final uid = online.user?.uid;
    if (uid == null ||
        online.authTransitioning ||
        online.accountFailure != null) {
      return null;
    }
    return LunoBillingOwner(uid, online.accountRevision);
  }

  @override
  bool get readyForBilling => currentOwner != null && online.ready;

  @override
  void addListener(VoidCallback listener) => online.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => online.removeListener(listener);

  void _guard(LunoBillingOwner owner) {
    if (!owner.sameAccount(currentOwner)) {
      throw const LunoBillingFailure('session-changed');
    }
  }

  Future<Map<String, dynamic>> _call(
    LunoBillingOwner owner,
    String path,
    Map<String, dynamic> payload,
  ) async {
    _guard(owner);
    try {
      final result = await online.api(path, payload);
      _guard(owner);
      return result;
    } on LunoBillingFailure {
      rethrow;
    } on LunoApiException catch (error) {
      const safeCodes = {
        'account-mismatch',
        'purchase-token-used',
        'purchase-revoked',
        'purchase-not-active',
        'purchase-not-complete',
        'purchase-product-mismatch',
        'account-deleted',
        'account-deletion-in-progress',
        'session-changed',
      };
      throw LunoBillingFailure(
        safeCodes.contains(error.code)
            ? error.code
            : 'verification-unavailable',
        retryable:
            error.code == 'purchase-not-complete' ||
            LunoOnlineService.isRetryableFailure(error),
      );
    } catch (_) {
      // No arbitrary exception string can expose a purchase token.
      throw const LunoBillingFailure(
        'verification-unavailable',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> verify(
    LunoBillingOwner owner,
    String productId,
    String purchaseToken,
  ) => _call(owner, '/verifyPurchase', {
    'productId': productId,
    'purchaseToken': purchaseToken,
  });

  @override
  Future<Map<String, dynamic>> getPlayerState(LunoBillingOwner owner) =>
      _call(owner, '/getPlayerState', const {});
}
