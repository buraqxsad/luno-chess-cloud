import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_online_service.dart';

void main() {
  for (final code in ['account-deleted', 'account-deletion-in-progress']) {
    test('$code survives startup and does not automatically retry', () async {
      var attempts = 0;
      final failure = LunoApiException(
        code,
        code == 'account-deleted' ? 403 : 409,
      );
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {
          attempts++;
          throw failure;
        },
      );
      addTearDown(service.dispose);
      await service.start();
      expect(service.ready, isFalse);
      expect(service.loading, isFalse);
      expect(service.accountFailure, same(failure));
      expect(service.lastError, failure.accountAccessMessage);
      await service.recoverAfterReconnectForTesting();
      await service.recoverAfterReconnectForTesting();
      await expectLater(
        service.api('/getPlayerState', {}),
        throwsA(same(failure)),
      );
      expect(attempts, 1);
      expect(service.ready, isFalse);
      expect(service.lastError, failure.accountAccessMessage);
    });
  }
  test(
    'failed reconnect bootstrap cannot mark service ready or clear error',
    () async {
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {
          throw const LunoApiException('network-unavailable', 0);
        },
      );
      addTearDown(service.dispose);
      await service.recoverAfterReconnectForTesting();
      expect(service.ready, isFalse);
      expect(service.lastError, isNotNull);
    },
  );
  test(
    'explicit retry can replace old failure after successful bootstrap',
    () async {
      var attempts = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {
          if (++attempts == 1) {
            throw const LunoApiException('account-deletion-in-progress', 409);
          }
        },
      );
      addTearDown(service.dispose);
      await service.start();
      expect(service.accountFailure, isNotNull);
      await service.retry();
      expect(attempts, 2);
      expect(service.ready, isTrue);
      expect(service.lastError, isNull);
      expect(service.accountFailure, isNull);
    },
  );
}
