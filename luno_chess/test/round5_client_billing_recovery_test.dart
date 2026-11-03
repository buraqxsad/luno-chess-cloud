import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_billing_service.dart';

import 'luno_billing_service_test.dart' as fixture;

class _CatalogPlay extends fixture.FakePlay {
  int catalogQueries = 0;
  bool rejectCatalog = false;

  @override
  Future<LunoBillingProductQuery> queryProducts(Set<String> ids) async {
    catalogQueries++;
    if (rejectCatalog) {
      throw const LunoBillingFailure('product-query-failed', retryable: true);
    }
    return super.queryProducts(ids);
  }
}

void main() {
  late _CatalogPlay play;
  late fixture.FakeBackend backend;
  late LunoBillingService billing;

  setUp(() {
    play = _CatalogPlay();
    backend = fixture.FakeBackend();
    billing = LunoBillingService(play: play, backend: backend);
  });

  tearDown(() async {
    billing.dispose();
    backend.dispose();
    await play.controller.close();
  });

  test('healthy repeated starts share the existing catalog', () async {
    await billing.start();
    await billing.start();
    expect(play.catalogQueries, 1);
    expect(play.listeners, 1);
    expect(billing.products.keys, contains(fixture.goldId));
    expect(await billing.purchase(fixture.goldId), isTrue);
  });

  for (final retry in ['start', 'restore']) {
    test('transient initial catalog error recovers through $retry', () async {
      play.rejectCatalog = true;
      await billing.start();
      expect(billing.available, isTrue);
      expect(billing.products, isEmpty);
      expect(billing.errorCode, 'product-query-failed');
      expect(play.catalogQueries, 1);
      play.rejectCatalog = false;
      if (retry == 'start') {
        await billing.start();
      } else {
        await billing.restore();
      }
      expect(
        billing.products.keys,
        contains(fixture.goldId),
        reason: 'The recovered store must make its localized products usable.',
      );
      expect(play.catalogQueries, 2);
      expect(play.listeners, 1);
      expect(await billing.purchase(fixture.goldId), isTrue);
    });
  }

  test(
    'ownership restore remains usable while the catalog query is unavailable',
    () async {
      play.rejectCatalog = true;
      await billing.start();
      play.owned = [fixture.receipt(token: 'round5-owned-catalog-offline')];
      await billing.restore();
      expect(backend.verifications, 1);
      expect(billing.latestSnapshot, isNotNull);
      expect(billing.queuedVerificationCount, 0);
      expect(play.launches, 0);
    },
  );

  test('current owned pending snapshot remains locked', () async {
    await billing.start();
    play.owned = [fixture.receipt(status: LunoPlayPurchaseStatus.pending)];
    await billing.restore();
    expect(billing.productStatuses[fixture.goldId], LunoBillingStatus.pending);
    expect(backend.verifications, 0);
    await expectLater(
      billing.purchase(fixture.goldId),
      throwsA(isA<LunoBillingFailure>()),
    );
    expect(play.launches, 0);
  });

  test(
    'late completed ownership receipt still verifies after a newer pending stream',
    () async {
      await billing.start();
      final owned = Completer<List<LunoPlayPurchase>>();
      play.ownedOverride = () => owned.future;
      final restoring = billing.restore();
      await fixture.flush();
      play.emit([
        fixture.receipt(
          token: 'round5-new-pending',
          status: LunoPlayPurchaseStatus.pending,
        ),
      ]);
      owned.complete([fixture.receipt(token: 'round5-old-paid')]);
      await restoring;
      expect(backend.verifications, 1);
      expect(billing.queuedVerificationCount, 0);
      expect(play.launches, 0);
    },
  );

  test(
    'pending query cannot undo a verification already running at query start',
    () async {
      await billing.start();
      final verification = Completer<Map<String, dynamic>>();
      backend.verifyOverride = (_, _, _) => verification.future;
      play.emit([fixture.receipt(token: 'round5-inflight-before-restore')]);
      await fixture.flush();
      expect(
        billing.productStatuses[fixture.goldId],
        LunoBillingStatus.verifying,
      );
      final owned = Completer<List<LunoPlayPurchase>>();
      play.ownedOverride = () => owned.future;
      final restoring = billing.restore();
      await fixture.flush();
      verification.complete(fixture.verified);
      await fixture.flush();
      expect(
        billing.productStatuses[fixture.goldId],
        LunoBillingStatus.verified,
      );
      owned.complete([
        fixture.receipt(
          token: 'round5-inflight-before-restore',
          status: LunoPlayPurchaseStatus.pending,
        ),
      ]);
      await restoring;
      expect(
        billing.productStatuses[fixture.goldId],
        LunoBillingStatus.verified,
      );
      expect(await billing.purchase(fixture.goldId), isTrue);
    },
  );

  for (final token in ['round5-paid-consumable', '']) {
    test(
      'delayed owned pending snapshot cannot replace a live verified token; pending token=$token',
      () async {
        await billing.start();
        final owned = Completer<List<LunoPlayPurchase>>();
        play.ownedOverride = () => owned.future;
        final restoring = billing.restore();
        await fixture.flush();
        play.emit([fixture.receipt(token: 'round5-paid-consumable')]);
        await fixture.flush();
        expect(
          billing.productStatuses[fixture.goldId],
          LunoBillingStatus.verified,
        );
        expect(backend.verifications, 1);
        owned.complete([
          fixture.receipt(token: token, status: LunoPlayPurchaseStatus.pending),
        ]);
        await restoring;
        expect(
          billing.productStatuses[fixture.goldId],
          LunoBillingStatus.verified,
          reason:
              'An older ownership query must not relock the paid consumable.',
        );
        expect(billing.queuedVerificationCount, 0);
        expect(await billing.purchase(fixture.goldId), isTrue);
      },
    );
  }
}
