import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_billing_service.dart';

import 'luno_billing_service_test.dart' as fixtures;

Map<String, dynamic> response(
  LunoBillingOwner owner, {
  required bool active,
  int? revision,
  int? observed,
}) => {
  'ok': true,
  'state': {
    'uid': owner.uid,
    'membership': {'active': active},
    if (revision != null) 'stateRevision': revision,
    if (observed != null) 'stateObservedAt': observed,
  },
};

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

  for (final boundary in ['older-revision', 'older-observation', 'legacy']) {
    for (final active in [true, false]) {
      test(
        'late $boundary restore cannot roll membership back from $active',
        () async {
          backend.stateOverride =
              (owner) async =>
                  response(owner, active: !active, revision: 0, observed: 50);
          await billing.start();
          final heldRestore = Completer<Map<String, dynamic>>();
          final restoreEntered = Completer<LunoBillingOwner>();
          var calls = 0;
          backend.stateOverride = (owner) async {
            if (++calls == 1) {
              restoreEntered.complete(owner);
              return heldRestore.future;
            }
            return response(owner, active: active, revision: 2, observed: 200);
          };
          final restoring = billing.restore();
          final owner = await restoreEntered.future;
          // A live purchase update can complete while restore's final read waits.
          // Current inactive access may instead reflect a refund/hold discovered
          // by an unrelated consumable's authoritative refresh.
          play.emit([
            fixtures.receipt(
              id: active ? fixtures.monthId : fixtures.goldId,
              token: 'round2-new-receipt-$boundary-$active',
            ),
          ]);
          await fixtures.flush();
          expect(billing.latestSnapshot!.state['stateRevision'], 2);
          expect(billing.latestSnapshot!.state['membership'], {
            'active': active,
          });
          heldRestore.complete(
            response(
              owner,
              active: !active,
              revision:
                  boundary == 'legacy'
                      ? null
                      : boundary == 'older-revision'
                      ? 1
                      : 2,
              observed: boundary == 'legacy' ? null : 100,
            ),
          );
          await restoring;
          expect(
            billing.latestSnapshot!.state['membership'],
            {'active': active},
            reason:
                'Completion order must not replace the newer server decision.',
          );
          expect(billing.latestSnapshot!.state['stateRevision'], 2);
          expect(billing.latestSnapshot!.state['stateObservedAt'], 200);
          if (active) {
            await expectLater(
              billing.purchase(fixtures.yearId),
              throwsA(
                isA<LunoBillingFailure>().having(
                  (failure) => failure.code,
                  'code',
                  'membership-already-owned',
                ),
              ),
            );
            expect(play.launches, 0);
          } else {
            expect(await billing.purchase(fixtures.yearId), isTrue);
            expect(play.launches, 1);
          }
        },
      );
    }
  }

  test('a stale inactive restore cannot launch a second membership', () async {
    backend.stateOverride =
        (owner) async =>
            response(owner, active: false, revision: 0, observed: 50);
    await billing.start();
    final held = Completer<Map<String, dynamic>>();
    final entered = Completer<LunoBillingOwner>();
    var calls = 0;
    backend.stateOverride = (owner) async {
      if (++calls == 1) {
        entered.complete(owner);
        return held.future;
      }
      return response(owner, active: true, revision: 2, observed: 200);
    };
    final restoring = billing.restore();
    final owner = await entered.future;
    play.emit([
      fixtures.receipt(
        id: fixtures.monthId,
        token: 'round2-membership-before-stale-inactive-restore',
      ),
    ]);
    await fixtures.flush();
    held.complete(response(owner, active: false, revision: 1, observed: 100));
    await restoring;
    await expectLater(
      billing.purchase(fixtures.yearId),
      throwsA(
        isA<LunoBillingFailure>().having(
          (failure) => failure.code,
          'code',
          'membership-already-owned',
        ),
      ),
    );
    expect(play.launches, 0);
  });

  test(
    'a newer restore response may apply after an earlier purchase refresh',
    () async {
      backend.stateOverride =
          (owner) async =>
              response(owner, active: false, revision: 0, observed: 50);
      await billing.start();
      final held = Completer<Map<String, dynamic>>();
      final entered = Completer<LunoBillingOwner>();
      var calls = 0;
      backend.stateOverride = (owner) async {
        if (++calls == 1) {
          entered.complete(owner);
          return held.future;
        }
        return response(owner, active: true, revision: 2, observed: 200);
      };
      final restoring = billing.restore();
      final owner = await entered.future;
      play.emit([
        fixtures.receipt(
          id: fixtures.monthId,
          token: 'round2-revoked-after-grant',
        ),
      ]);
      await fixtures.flush();
      expect(billing.latestSnapshot!.state['membership'], {'active': true});
      held.complete(response(owner, active: false, revision: 3, observed: 300));
      await restoring;
      expect(billing.latestSnapshot!.state['membership'], {'active': false});
      expect(await billing.purchase(fixtures.yearId), isTrue);
    },
  );

  test(
    'legacy-only backend remains usable until versioned authority is seen',
    () async {
      backend.stateOverride = (owner) async => response(owner, active: true);
      await billing.start();
      expect(billing.latestSnapshot!.state['membership'], {'active': true});
      backend.stateOverride = (owner) async => response(owner, active: false);
      await billing.restore();
      expect(billing.latestSnapshot!.state['membership'], {'active': false});
      expect(await billing.purchase(fixtures.yearId), isTrue);
    },
  );

  for (final malformed in [
    {'stateRevision': 3},
    {'stateRevision': 9007199254740992, 'stateObservedAt': 300},
  ]) {
    test(
      'invalid partial or unsafe version does not replace authority: $malformed',
      () async {
        backend.stateOverride =
            (owner) async =>
                response(owner, active: true, revision: 2, observed: 200);
        await billing.start();
        backend.stateOverride =
            (owner) async => {
              'ok': true,
              'state': {
                'uid': owner.uid,
                'membership': {'active': false},
                ...malformed,
              },
            };
        await expectLater(
          billing.restore(),
          throwsA(
            isA<LunoBillingFailure>().having(
              (failure) => failure.code,
              'code',
              'invalid-server-state',
            ),
          ),
        );
        expect(billing.latestSnapshot!.state['stateRevision'], 2);
        expect(billing.latestSnapshot!.state['membership'], {'active': true});
        backend.stateOverride =
            (owner) async =>
                response(owner, active: false, revision: 3, observed: 300);
        await billing.restore();
        expect(await billing.purchase(fixtures.yearId), isTrue);
      },
    );
  }

  test(
    'new owner may start at a lower revision without old ownership',
    () async {
      backend.stateOverride =
          (owner) async => response(
            owner,
            active: owner.uid == 'account-a',
            revision: owner.uid == 'account-a' ? 20 : 0,
            observed: owner.uid == 'account-a' ? 200 : 50,
          );
      await billing.start();
      expect(billing.latestSnapshot!.state['membership'], {'active': true});
      backend.switchAccount(const LunoBillingOwner('account-b', 2));
      await fixtures.flush();
      expect(billing.latestSnapshot!.owner.uid, 'account-b');
      expect(billing.latestSnapshot!.state['stateRevision'], 0);
      expect(billing.latestSnapshot!.state['membership'], {'active': false});
      expect(await billing.purchase(fixtures.yearId), isTrue);
      expect(play.launchedAccount, fixtures.accountHash('account-b'));
    },
  );
}
