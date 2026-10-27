import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_billing_service.dart';

const goldId = 'luno_gold_1000';
const monthId = 'luno_premium_month';
const yearId = 'luno_premium_year';
const verified = <String, dynamic>{
  'ok': true,
  'verified': true,
  'entitlementGranted': true,
  'idempotent': false,
};

String accountHash(String uid) => sha256.convert(utf8.encode(uid)).toString();

LunoPlayPurchase receipt({
  String id = goldId,
  String token = 'private-play-receipt',
  LunoPlayPurchaseStatus status = LunoPlayPurchaseStatus.purchased,
  String? account,
}) => LunoPlayPurchase(
  productId: id,
  purchaseToken: token,
  status: status,
  obfuscatedAccountId: account,
);

LunoBillingProduct product(String id) => LunoBillingProduct(
  id: id,
  title: id,
  description: 'Store description',
  localizedPrice: 'TRY 129,99',
  rawPrice: 129.99,
  currencyCode: 'TRY',
);

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakePlay implements LunoPlayBillingPort {
  FakePlay() {
    controller = StreamController<List<LunoPlayPurchase>>.broadcast(
      sync: true,
      onListen: () => listeners++,
      onCancel: () => listeners--,
    );
  }
  late final StreamController<List<LunoPlayPurchase>> controller;
  bool available = true;
  int listeners = 0;
  int ownedQueries = 0;
  int launches = 0;
  String? launchedAccount;
  String? launchedProduct;
  List<LunoPlayPurchase> owned = [];
  List<LunoBillingProduct> catalog = [
    product(goldId),
    product(monthId),
    product(yearId),
  ];
  Future<bool> Function()? availabilityOverride;
  Future<bool> Function()? launchOverride;
  Future<List<LunoPlayPurchase>> Function()? ownedOverride;
  @override
  Stream<List<LunoPlayPurchase>> get purchaseStream => controller.stream;
  @override
  Future<bool> isAvailable() =>
      availabilityOverride?.call() ?? Future.value(available);
  @override
  Future<LunoBillingProductQuery> queryProducts(Set<String> ids) async =>
      LunoBillingProductQuery(
        catalog,
        ids.difference(catalog.map((p) => p.id).toSet()),
      );
  @override
  Future<bool> launch(LunoBillingProduct product, String account) {
    launches++;
    launchedAccount = account;
    launchedProduct = product.id;
    return launchOverride?.call() ?? Future.value(true);
  }

  @override
  Future<List<LunoPlayPurchase>> queryOwned(String account) async {
    ownedQueries++;
    return ownedOverride == null ? owned : await ownedOverride!();
  }

  void emit(List<LunoPlayPurchase> batch) => controller.add(batch);
}

class FakeBackend extends ChangeNotifier implements LunoBillingBackend {
  LunoBillingOwner? account = const LunoBillingOwner('account-a', 1);
  bool ready = true;
  int verifications = 0;
  int refreshes = 0;
  final List<String> verifiedProducts = [];
  Future<Map<String, dynamic>> Function(LunoBillingOwner, String, String)?
  verifyOverride;
  Future<Map<String, dynamic>> Function(LunoBillingOwner)? stateOverride;
  @override
  LunoBillingOwner? get currentOwner => account;
  @override
  bool get readyForBilling => ready && account != null;
  @override
  Future<Map<String, dynamic>> verify(
    LunoBillingOwner owner,
    String id,
    String token,
  ) async {
    verifications++;
    verifiedProducts.add(id);
    return verifyOverride == null
        ? verified
        : await verifyOverride!(owner, id, token);
  }

  @override
  Future<Map<String, dynamic>> getPlayerState(LunoBillingOwner owner) async {
    refreshes++;
    return stateOverride == null
        ? {
          'ok': true,
          'state': {
            'uid': owner.uid,
            'gold': 1000,
            'membership': {'active': verifiedProducts.contains(monthId)},
            'passState': {'premium': false},
            '__serverOwner': owner.uid,
            '__serverEpoch': 77,
          },
        }
        : await stateOverride!(owner);
  }

  void switchAccount(LunoBillingOwner? next, {bool isReady = true}) {
    account = next;
    ready = isReady;
    notifyListeners();
  }
}

void main() {
  late FakePlay play;
  late FakeBackend backend;
  late LunoBillingService billing;
  test(
    'concurrent starts retain one owner, listener and initialization',
    () async {
      final available = Completer<bool>();
      play.availabilityOverride = () => available.future;
      final first = billing.start();
      final owner = billing.owner;
      final second = billing.start();
      expect(second, same(first));
      expect(billing.owner, same(owner));
      expect(play.listeners, 1);
      available.complete(true);
      await first;
      await second;
      expect(play.ownedQueries, 1);
      expect(billing.isCurrent(owner!), true);
    },
  );

  test(
    'restored active membership cannot launch a second subscription',
    () async {
      backend.stateOverride =
          (owner) async => {
            'ok': true,
            'state': {
              'uid': owner.uid,
              'membership': {'active': true},
            },
          };
      await billing.start();
      await expectLater(
        billing.purchase(yearId),
        throwsA(isA<LunoBillingFailure>()),
      );
      expect(play.launches, 0);
    },
  );
  setUp(() {
    play = FakePlay();
    backend = FakeBackend();
    billing = LunoBillingService(play: play, backend: backend);
  });
  tearDown(() async {
    billing.dispose();
    backend.dispose();
    await play.controller.close();
  });

  test(
    'listener binds before the first store await and owned recovery',
    () async {
      final available = Completer<bool>();
      play.availabilityOverride = () => available.future;
      final start = billing.start();
      expect(play.listeners, 1);
      play.emit([receipt()]);
      await flush();
      expect(backend.verifications, 1);
      available.complete(true);
      await start;
      expect(play.ownedQueries, 1);
      expect(billing.products[monthId]!.localizedPrice, 'TRY 129,99');
      expect(billing.missingProductIds, contains('luno_gem_500'));
    },
  );

  test(
    'start requires authenticated readiness and can bind on later readiness',
    () async {
      backend.switchAccount(null);
      expect(billing.start, throwsA(isA<LunoBillingFailure>()));
      expect(play.listeners, 0);
      backend.switchAccount(
        const LunoBillingOwner('account-b', 2),
        isReady: false,
      );
      expect(play.listeners, 0);
      backend.switchAccount(const LunoBillingOwner('account-b', 2));
      await flush();
      expect(play.listeners, 1);
      expect(billing.owner!.uid, 'account-b');
    },
  );

  test(
    'all ten backend products are supported, no Pass SKU or price fallback',
    () async {
      await billing.start();
      expect(lunoBillingCatalog.length, 10);
      expect(lunoBillingCatalog.keys.any((id) => id.contains('pass')), false);
      expect(
        () => billing.products[goldId] = product(goldId),
        throwsUnsupportedError,
      );
      await expectLater(
        billing.purchase('luno_gem_500'),
        throwsA(isA<LunoBillingFailure>()),
      );
      expect(play.launches, 0);
    },
  );

  for (final id in [monthId, yearId, goldId]) {
    test('launch $id binds sha256(uid) and never grants by launch', () async {
      await billing.start();
      final initial = backend.refreshes;
      expect(await billing.purchase(id), true);
      expect(play.launchedAccount, accountHash('account-a'));
      expect(play.launchedProduct, id);
      expect(backend.verifications, 0);
      expect(backend.refreshes, initial);
      expect(billing.productStatuses[id], LunoBillingStatus.purchasing);
      await expectLater(
        billing.purchase(id),
        throwsA(isA<LunoBillingFailure>()),
      );
      expect(play.launches, 1);
    });
  }

  test(
    'pending, canceled and error do not verify or project entitlements',
    () async {
      await billing.start();
      final baseline = backend.refreshes;
      for (final status in [
        LunoPlayPurchaseStatus.pending,
        LunoPlayPurchaseStatus.canceled,
        LunoPlayPurchaseStatus.error,
      ]) {
        play.emit([receipt(status: status)]);
        await flush();
        expect(billing.productStatuses[goldId], switch (status) {
          LunoPlayPurchaseStatus.pending => LunoBillingStatus.pending,
          LunoPlayPurchaseStatus.canceled => LunoBillingStatus.canceled,
          _ => LunoBillingStatus.error,
        });
      }
      expect(backend.verifications, 0);
      expect(backend.refreshes, baseline);
    },
  );

  test('empty-product cancellation resolves the active Android flow', () async {
    await billing.start();
    await billing.purchase(goldId);
    play.emit([
      receipt(id: '', token: '', status: LunoPlayPurchaseStatus.canceled),
    ]);
    expect(billing.productStatuses[goldId], LunoBillingStatus.canceled);
    expect(await billing.purchase(goldId), true);
  });

  test(
    'strict verified grant projects only subsequent owner-guarded server state',
    () async {
      await billing.start();
      final updates = <LunoBillingSnapshot>[];
      final subscription = billing.snapshots.listen(updates.add);
      play.emit([receipt(id: monthId)]);
      await flush();
      expect(backend.verifications, 1);
      expect(updates.single.state['membership'], {'active': true});
      expect(updates.single.state['passState'], {'premium': false});
      expect(updates.single.state['__serverEpoch'], 77);
      expect(billing.isCurrent(updates.single.owner), true);
      expect(billing.productStatuses[monthId], LunoBillingStatus.verified);
      await expectLater(
        billing.purchase(yearId),
        throwsA(isA<LunoBillingFailure>()),
      );
      await subscription.cancel();
    },
  );

  for (final response in <Map<String, dynamic>>[
    {'ok': true, 'verified': true},
    {'ok': true, 'entitlementGranted': true},
    {'verified': true, 'entitlementGranted': true},
    {'ok': true, 'verified': true, 'entitlementGranted': false},
    {'ok': true, 'verified': 'true', 'entitlementGranted': true},
  ]) {
    test(
      'incomplete verification flags cannot trigger a state projection: $response',
      () async {
        await billing.start();
        final baseline = backend.refreshes;
        backend.verifyOverride = (_, _, _) async => response;
        play.emit([receipt()]);
        await flush();
        expect(backend.refreshes, baseline);
        expect(billing.productStatuses[goldId], LunoBillingStatus.error);
        expect(billing.errorCode, 'verification-rejected');
      },
    );
  }

  test(
    'duplicate stream events coalesce in-flight, completed and cross-product token replay',
    () async {
      await billing.start();
      final pending = Completer<Map<String, dynamic>>();
      backend.verifyOverride = (_, _, _) => pending.future;
      play.emit([receipt(), receipt(), receipt(id: monthId)]);
      await flush();
      expect(backend.verifications, 1);
      pending.complete({...verified, 'idempotent': true});
      await flush();
      play.emit([receipt(), receipt(id: monthId)]);
      await flush();
      expect(backend.verifications, 1);
      expect(billing.queuedVerificationCount, 0);
      expect(billing.productStatuses[goldId], LunoBillingStatus.verified);
    },
  );

  test(
    'transient verification waits in memory and duplicate events do not retry',
    () async {
      await billing.start();
      backend.verifyOverride =
          (_, _, _) async =>
              throw const LunoBillingFailure(
                'verification-unavailable',
                retryable: true,
              );
      play.emit([receipt()]);
      await flush();
      expect(backend.verifications, 1);
      play.emit([receipt(), receipt()]);
      await flush();
      expect(backend.verifications, 1);
      expect(billing.queuedVerificationCount, 1);
      expect(billing.productStatuses[goldId], LunoBillingStatus.queued);
      backend.verifyOverride = null;
      await billing.retryQueued();
      expect(backend.verifications, 2);
      expect(billing.queuedVerificationCount, 0);
    },
  );

  test(
    'state refresh failure retries projection, not grant or consume',
    () async {
      await billing.start();
      backend.stateOverride =
          (_) async =>
              throw const LunoBillingFailure(
                'verification-unavailable',
                retryable: true,
              );
      play.emit([receipt()]);
      await flush();
      expect(backend.verifications, 1);
      expect(billing.errorCode, 'state-refresh-required');
      backend.stateOverride = null;
      await billing.retryQueued();
      expect(backend.verifications, 1);
      expect(billing.queuedVerificationCount, 0);
    },
  );

  test(
    'process restart recovers unconsumed owned purchases without local tokens',
    () async {
      await billing.start();
      backend.verifyOverride =
          (_, _, _) async =>
              throw const LunoBillingFailure(
                'verification-unavailable',
                retryable: true,
              );
      play.emit([receipt()]);
      await flush();
      expect(billing.queuedVerificationCount, 1);
      billing.dispose();
      billing = LunoBillingService(play: play, backend: backend);
      play.owned = [receipt(status: LunoPlayPurchaseStatus.restored)];
      backend.verifyOverride = null;
      await billing.start();
      expect(backend.verifications, 2);
      expect(billing.productStatuses[goldId], LunoBillingStatus.verified);
    },
  );

  test(
    'restore refreshes consumed server grants even when Play owns nothing',
    () async {
      await billing.start();
      final before = backend.refreshes;
      await billing.restore();
      expect(backend.refreshes, before + 1);
      expect(backend.verifications, 0);
      expect(billing.latestSnapshot!.state['gold'], 1000);
    },
  );

  test(
    'restore revalidates completed subscription token rather than local authority',
    () async {
      await billing.start();
      final subscription = receipt(id: monthId);
      play.emit([subscription]);
      await flush();
      play.owned = [subscription];
      await billing.restore();
      expect(backend.verifications, 2);
      expect(billing.queuedVerificationCount, 0);
    },
  );

  test('restore leaves Play pending purchase unverified', () async {
    play.owned = [receipt(status: LunoPlayPurchaseStatus.pending)];
    await billing.start();
    expect(backend.verifications, 0);
    expect(billing.productStatuses[goldId], LunoBillingStatus.pending);
  });

  test('mismatched Play account cannot be verified for new owner', () async {
    await billing.start();
    play.emit([receipt(account: accountHash('account-b'))]);
    await flush();
    expect(backend.verifications, 0);
    expect(billing.errorCode, 'account-mismatch');
  });

  test(
    'verification response after account switch is discarded, listener stops on loss',
    () async {
      await billing.start();
      final pending = Completer<Map<String, dynamic>>();
      backend.verifyOverride = (_, _, _) => pending.future;
      final oldOwner = billing.owner!;
      play.emit([receipt()]);
      await flush();
      final refreshes = backend.refreshes;
      backend.switchAccount(null);
      await flush();
      expect(play.listeners, 0);
      expect(billing.isCurrent(oldOwner), false);
      expect(billing.queuedVerificationCount, 0);
      pending.complete(verified);
      await flush();
      expect(backend.refreshes, refreshes);
      expect(billing.latestSnapshot, isNull);
    },
  );

  test(
    'delayed state cannot apply across same-UID auth revision change',
    () async {
      await billing.start();
      final state = Completer<Map<String, dynamic>>();
      backend.stateOverride = (_) => state.future;
      final oldOwner = billing.owner!;
      play.emit([receipt()]);
      await flush();
      backend.switchAccount(
        const LunoBillingOwner('account-a', 2),
        isReady: false,
      );
      state.complete({
        'ok': true,
        'state': {'uid': 'account-a', 'gold': 9999},
      });
      await flush();
      expect(billing.isCurrent(oldOwner), false);
      expect(billing.latestSnapshot, isNull);
    },
  );

  test('server state UID mismatch is queued and never published', () async {
    await billing.start();
    final initial = billing.latestSnapshot;
    backend.stateOverride =
        (_) async => {
          'ok': true,
          'state': {'uid': 'account-b', 'gold': 9999},
        };
    play.emit([receipt()]);
    await flush();
    expect(billing.latestSnapshot, same(initial));
    expect(billing.queuedVerificationCount, 1);
    expect(billing.errorCode, 'state-refresh-required');
  });

  test(
    'stop/start invalidates old owner stamp even with same account revision',
    () async {
      await billing.start();
      final oldOwner = billing.latestSnapshot!.owner;
      await billing.stop();
      expect(play.listeners, 0);
      await billing.start();
      expect(billing.isCurrent(oldOwner), false);
      expect(billing.isCurrent(billing.owner!), true);
    },
  );

  test(
    'unavailable store has no fake products; explicit start retries safely',
    () async {
      play.available = false;
      await billing.start();
      expect(billing.status, LunoBillingStatus.unavailable);
      expect(billing.products, isEmpty);
      play.available = true;
      await billing.start();
      expect(billing.available, true);
      expect(play.listeners, 1);
    },
  );

  test(
    'tokens and arbitrary errors are absent from UI events and exception text',
    () async {
      await billing.start();
      final events = <LunoBillingEvent>[];
      final subscription = billing.events.listen(events.add);
      backend.verifyOverride = (_, _, token) async => throw StateError(token);
      final purchase = receipt();
      play.emit([purchase]);
      await flush();
      expect(purchase.toString().contains(purchase.purchaseToken), false);
      expect(
        events.map((e) => e.errorCode).whereType<String>(),
        everyElement(isNot(contains(purchase.purchaseToken))),
      );
      expect(billing.errorCode, 'billing-unavailable');
      await subscription.cancel();
    },
  );

  test(
    'bounded verification timeout queues and ignores its late result',
    () async {
      billing.dispose();
      billing = LunoBillingService(
        play: play,
        backend: backend,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await billing.start();
      final pending = Completer<Map<String, dynamic>>();
      backend.verifyOverride = (_, _, _) => pending.future;
      final baseline = backend.refreshes;
      play.emit([receipt()]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(billing.queuedVerificationCount, 1);
      expect(backend.verifications, 1);
      pending.complete(verified);
      await flush();
      expect(backend.refreshes, baseline);
    },
  );

  test('timed-out native launch remains locked until it settles', () async {
    billing.dispose();
    billing = LunoBillingService(
      play: play,
      backend: backend,
      storeTimeout: const Duration(milliseconds: 10),
    );
    await billing.start();
    final pending = Completer<bool>();
    play.launchOverride = () => pending.future;
    await expectLater(
      billing.purchase(goldId),
      throwsA(isA<LunoBillingFailure>()),
    );
    await expectLater(
      billing.purchase(monthId),
      throwsA(isA<LunoBillingFailure>()),
    );
    expect(play.launches, 1);
    pending.complete(true);
    await flush();
    play.launchOverride = null;
    expect(await billing.purchase(monthId), true);
  });
}
