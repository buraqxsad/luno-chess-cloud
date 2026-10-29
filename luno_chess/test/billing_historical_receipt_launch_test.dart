import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_billing_service.dart';

import 'luno_billing_service_test.dart' as fixtures;

void main() {
  late fixtures.FakePlay play;
  late fixtures.FakeBackend backend;
  late LunoBillingService billing;

  setUp(() {
    play = fixtures.FakePlay();
    backend = fixtures.FakeBackend();
    billing = LunoBillingService(play: play, backend: backend);
  });
  tearDown(() async {
    billing.dispose();
    backend.dispose();
    await play.controller.close();
  });

  for (final status in [
    LunoPlayPurchaseStatus.pending,
    LunoPlayPurchaseStatus.canceled,
    LunoPlayPurchaseStatus.error,
  ]) {
    test(
      'current $status callback still resolves its own Play sheet',
      () async {
        await billing.start();
        expect(await billing.purchase(fixtures.goldId), isTrue);
        play.emit([fixtures.receipt(status: status, token: '')]);
        await fixtures.flush();
        expect(backend.verifications, 0);
        expect(await billing.purchase(fixtures.yearId), isTrue);
        expect(play.launches, 2);
      },
    );
  }

  for (final restore in [false, true]) {
    test(
      '${restore ? 'restore replay' : 'stream duplicate'} of a historical receipt cannot unlock a newer Play flow',
      () async {
        await billing.start();
        final oldReceipt = fixtures.receipt(token: 'already-fulfilled-gold');
        play.emit([oldReceipt]);
        await fixtures.flush();
        expect(backend.verifications, 1);
        expect(
          billing.productStatuses[fixtures.goldId],
          LunoBillingStatus.verified,
        );

        expect(await billing.purchase(fixtures.goldId), isTrue);
        expect(play.launches, 1);
        if (restore) {
          play.owned = [oldReceipt];
          await billing.restore();
          expect(
            backend.verifications,
            2,
            reason: 'Restore still revalidates ownership.',
          );
        } else {
          play.emit([oldReceipt]);
          await fixtures.flush();
          expect(
            backend.verifications,
            1,
            reason: 'A stream duplicate must remain idempotent.',
          );
        }

        // The first Play sheet still has no receipt for its own new token.
        // Its global launch lock must also prevent a different product sheet.
        await expectLater(
          billing.purchase(fixtures.yearId),
          throwsA(
            isA<LunoBillingFailure>().having(
              (e) => e.code,
              'code',
              'billing-busy',
            ),
          ),
        );
        expect(play.launches, 1);

        // A genuinely new receipt resolves that sheet and permits another flow.
        play.emit([fixtures.receipt(token: 'new-flow-gold')]);
        await fixtures.flush();
        expect(
          billing.productStatuses[fixtures.goldId],
          LunoBillingStatus.verified,
        );
        expect(await billing.purchase(fixtures.yearId), isTrue);
        expect(play.launches, 2);
      },
    );
  }
  test(
    'restore during native launch cannot unlock its later accepted flow',
    () async {
      await billing.start();
      final oldReceipt = fixtures.receipt(
        token: 'old-gold-before-native-return',
      );
      play.emit([oldReceipt]);
      await fixtures.flush();
      final nativeLaunch = Completer<bool>();
      play.launchOverride = () => nativeLaunch.future;
      final launch = billing.purchase(fixtures.goldId);
      await fixtures.flush();
      expect(play.launches, 1);

      play.owned = [oldReceipt];
      await billing.restore();
      expect(backend.verifications, 2);
      nativeLaunch.complete(true);
      expect(await launch, isTrue);
      await fixtures.flush();
      await expectLater(
        billing.purchase(fixtures.yearId),
        throwsA(
          isA<LunoBillingFailure>().having(
            (e) => e.code,
            'code',
            'billing-busy',
          ),
        ),
      );
      expect(play.launches, 1);

      play.emit([fixtures.receipt(token: 'fresh-gold-after-native-return')]);
      await fixtures.flush();
      play.launchOverride = null;
      expect(await billing.purchase(fixtures.yearId), isTrue);
      expect(play.launches, 2);
    },
  );
}
