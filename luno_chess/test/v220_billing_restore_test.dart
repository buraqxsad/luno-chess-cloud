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

  test(
    'explicit restore retries a recovered inactive subscription token',
    () async {
      var recovered = false;
      backend.verifyOverride = (_, _, _) async {
        if (!recovered) throw const LunoBillingFailure('purchase-not-active');
        return fixture.verified;
      };
      await billing.start();
      final receipt = fixture.receipt(id: fixture.monthId);
      play.emit([receipt]);
      await fixture.flush();
      expect(backend.verifications, 1);
      expect(billing.errorCode, 'purchase-not-active');
      recovered = true;
      play.emit([receipt]);
      await fixture.flush();
      expect(
        backend.verifications,
        1,
        reason: 'Stream duplicates cannot force retry',
      );
      play.owned = [receipt];
      await billing.restore();
      expect(backend.verifications, 2);
      expect(
        billing.productStatuses[fixture.monthId],
        LunoBillingStatus.verified,
      );
    },
  );

  for (final code in [
    'account-mismatch',
    'purchase-token-used',
    'purchase-revoked',
  ]) {
    test('explicit restore keeps $code token rejected', () async {
      backend.verifyOverride =
          (_, _, _) async => throw LunoBillingFailure(code);
      await billing.start();
      final receipt = fixture.receipt(id: fixture.monthId);
      play.emit([receipt]);
      await fixture.flush();
      play.owned = [receipt];
      await billing.restore();
      expect(backend.verifications, 1);
      expect(billing.productStatuses[fixture.monthId], LunoBillingStatus.error);
    });
  }

  test(
    'explicit restore does not duplicate an in-flight token verification',
    () async {
      final result = Completer<Map<String, dynamic>>();
      backend.verifyOverride = (_, _, _) => result.future;
      await billing.start();
      final receipt = fixture.receipt(id: fixture.monthId);
      play.emit([receipt]);
      await fixture.flush();
      play.owned = [receipt];
      final restore = billing.restore();
      await fixture.flush();
      expect(backend.verifications, 1);
      result.complete(fixture.verified);
      await restore;
      expect(backend.verifications, 1);
      expect(billing.queuedVerificationCount, 0);
    },
  );

  test(
    'accepted-token stream guard survives an unrelated inactive-token retry',
    () async {
      var recovered = false;
      backend.verifyOverride = (_, id, _) async {
        if (id == fixture.monthId && !recovered) {
          throw const LunoBillingFailure('purchase-not-active');
        }
        return fixture.verified;
      };
      await billing.start();
      final accepted = fixture.receipt();
      final inactive = fixture.receipt(
        id: fixture.monthId,
        token: 'synthetic-inactive',
      );
      play.emit([accepted, inactive]);
      await fixture.flush();
      expect(backend.verifications, 2);
      recovered = true;
      play.owned = [inactive];
      await billing.restore();
      expect(backend.verifications, 3);
      play.emit([accepted, inactive]);
      await fixture.flush();
      expect(backend.verifications, 3);
    },
  );
}
