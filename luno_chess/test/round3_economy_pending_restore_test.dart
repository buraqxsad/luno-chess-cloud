import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_billing_service.dart';

import 'luno_billing_service_test.dart' as fixture;

void main() {
  late fixture.FakePlay play;
  late fixture.FakeBackend backend;
  late LunoBillingService billing;

  setUp(() {
    play = fixture.FakePlay();
    backend = fixture.FakeBackend();
    billing = LunoBillingService(play: play, backend: backend);
  });
  tearDown(() async {
    billing.dispose();
    backend.dispose();
    await play.controller.close();
  });

  for (final id in [fixture.goldId, fixture.monthId]) {
    test(
      'restore releases a canceled Play pending $id absent from current ownership',
      () async {
        await billing.start();
        expect(await billing.purchase(id), true);
        play.emit([
          fixture.receipt(id: id, status: LunoPlayPurchaseStatus.pending),
        ]);
        expect(billing.productStatuses[id], LunoBillingStatus.pending);
        expect(backend.verifications, 0);
        // The pending payment was canceled outside this running app. Play's
        // current ownership query is authoritative and no longer returns it.
        play.owned = [];
        await billing.restore();
        expect(
          billing.productStatuses[id],
          LunoBillingStatus.idle,
          reason:
              'A disappeared pending receipt must not lock new payments until process restart.',
        );
        expect(
          await billing.purchase(id == fixture.monthId ? fixture.yearId : id),
          true,
        );
        expect(play.launches, 2);
        expect(backend.verifications, 0);
      },
    );
  }

  test(
    'restore keeps a genuinely owned pending payment locked and unverified',
    () async {
      await billing.start();
      final pending = fixture.receipt(status: LunoPlayPurchaseStatus.pending);
      play.emit([pending]);
      play.owned = [pending];
      await billing.restore();
      expect(
        billing.productStatuses[fixture.goldId],
        LunoBillingStatus.pending,
      );
      await expectLater(
        billing.purchase(fixture.goldId),
        throwsA(isA<LunoBillingFailure>()),
      );
      expect(play.launches, 0);
      expect(backend.verifications, 0);
    },
  );

  test('a failed ownership query cannot release a pending payment', () async {
    await billing.start();
    play.emit([fixture.receipt(status: LunoPlayPurchaseStatus.pending)]);
    play.ownedOverride =
        () async =>
            throw const LunoBillingFailure(
              'restore-query-failed',
              retryable: true,
            );
    await expectLater(billing.restore(), throwsA(isA<LunoBillingFailure>()));
    expect(billing.productStatuses[fixture.goldId], LunoBillingStatus.pending);
    await expectLater(
      billing.purchase(fixture.goldId),
      throwsA(isA<LunoBillingFailure>()),
    );
    expect(backend.verifications, 0);
  });

  test(
    'an empty old ownership query cannot erase a newer pending stream receipt',
    () async {
      await billing.start();
      play.emit([
        fixture.receipt(
          status: LunoPlayPurchaseStatus.pending,
          token: 'round3-old-pending',
        ),
      ]);
      final result = Completer<List<LunoPlayPurchase>>();
      play.ownedOverride = () => result.future;
      final restoring = billing.restore();
      await fixture.flush();
      play.emit([
        fixture.receipt(
          status: LunoPlayPurchaseStatus.pending,
          token: 'round3-new-pending',
        ),
      ]);
      result.complete([]);
      await restoring;
      expect(
        billing.productStatuses[fixture.goldId],
        LunoBillingStatus.pending,
      );
      await expectLater(
        billing.purchase(fixture.goldId),
        throwsA(isA<LunoBillingFailure>()),
      );
      expect(backend.verifications, 0);
    },
  );

  test(
    'an empty ownership query cannot release a still-open native payment launch',
    () async {
      await billing.start();
      final native = Completer<bool>();
      play.launchOverride = () => native.future;
      final launching = billing.purchase(fixture.goldId);
      await fixture.flush();
      await billing.restore();
      expect(
        billing.productStatuses[fixture.goldId],
        LunoBillingStatus.purchasing,
      );
      await expectLater(
        billing.purchase(fixture.monthId),
        throwsA(isA<LunoBillingFailure>()),
      );
      expect(play.launches, 1);
      native.complete(false);
      expect(await launching, false);
    },
  );
}
