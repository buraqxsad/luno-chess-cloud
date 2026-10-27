import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:luno_chess/services/luno_online_service.dart';

void main() {
  group('online failure classification', () {
    for (final failure in const [
      LunoApiException('profile-not-found', 404),
      LunoApiException('account-deleted', 403),
      LunoApiException('account-deletion-in-progress', 409),
      LunoApiException('insufficient-gold', 400),
      LunoApiException('already-claimed', 409),
      LunoApiException('app-check-required', 403),
      LunoApiException('auth-required', 401),
      LunoApiException('invalid-server-response', 200),
    ]) {
      test('${failure.code} does not retry or disable online access', () {
        expect(LunoOnlineService.isRetryableFailure(failure), isFalse);
      });
    }
    for (final failure in [
      const LunoApiException('network-unavailable', 0),
      const LunoApiException('timeout', 408),
      const LunoApiException('rate-limit', 429),
      const LunoApiException('invalid-server-response', 503),
      const LunoApiException('auth/id-token-expired', 401),
      const LunoApiException('invalid-token', 401),
      TimeoutException('request'),
      http.ClientException('Connection closed'),
    ]) {
      test('$failure permits bounded recovery', () {
        expect(LunoOnlineService.isRetryableFailure(failure), isTrue);
      });
    }
    test('programming and malformed data errors are not network failures', () {
      expect(
        LunoOnlineService.isRetryableFailure(StateError('bad state')),
        isFalse,
      );
      expect(
        LunoOnlineService.isRetryableFailure(const FormatException()),
        isFalse,
      );
    });
  });
}
