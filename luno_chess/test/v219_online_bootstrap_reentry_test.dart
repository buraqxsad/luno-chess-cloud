import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_online_service.dart';

void main() {
  test('synchronous bootstrap failure does not retain a completed start future', () async {
    var attempts = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () {
        if (++attempts == 1) {
          throw const LunoApiException('network-unavailable', 0);
        }
        return Future<void>.value();
      },
    );
    addTearDown(service.dispose);
    await service.start().timeout(const Duration(seconds: 1));
    expect(service.ready, isFalse);
    await service.retry().timeout(const Duration(seconds: 1));
    expect(attempts, 2);
    expect(service.ready, isTrue);
    expect(service.loading, isFalse);
    expect(service.lastError, isNull);
  });

  test('asynchronous bootstrap failure clears its completed attempt before retry', () async {
    var attempts = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () async {
        attempts++;
        await Future<void>.delayed(Duration.zero);
        if (attempts == 1) {
          throw const LunoApiException('network-unavailable', 0);
        }
      },
    );
    addTearDown(service.dispose);
    await service.start().timeout(const Duration(seconds: 1));
    expect(service.ready, isFalse);
    expect(service.lastError, isNotNull);
    await service.retry().timeout(const Duration(seconds: 1));
    expect(attempts, 2);
    expect(service.ready, isTrue);
    expect(service.loading, isFalse);
    expect(service.lastError, isNull);
  });

  test('concurrent start and retry callers share one in-flight bootstrap', () async {
    final hold = Completer<void>();
    var attempts = 0;
    final service = LunoOnlineService.forTesting(
      bootstrap: () {
        attempts++;
        return hold.future;
      },
    );
    addTearDown(service.dispose);
    final first = service.start(), second = service.start();
    final retry = service.retry();
    expect(identical(first, second), isTrue);
    expect(attempts, 1);
    expect(service.loading, isTrue);
    hold.complete();
    await Future.wait([first, second, retry]).timeout(const Duration(seconds: 1));
    expect(attempts, 1);
    expect(service.ready, isTrue);
    expect(service.loading, isFalse);
    await service.start();
    expect(attempts, 1);
  });

  test('synchronous listener re-entry observes the preinstalled bootstrap gate', () async {
    final hold = Completer<void>();
    var attempts = 0, entered = false;
    Future<void>? reentered;
    final service = LunoOnlineService.forTesting(
      bootstrap: () {
        attempts++;
        return hold.future;
      },
    );
    addTearDown(service.dispose);
    service.addListener(() {
      if (!entered && service.loading) {
        entered = true;
        reentered = service.start();
      }
    });
    final first = service.start();
    expect(identical(first, reentered), isTrue);
    expect(attempts, 1);
    hold.complete();
    await first.timeout(const Duration(seconds: 1));
    expect(service.ready, isTrue);
  });

  for (final failure in [false, true]) {
    test('disposed bootstrap cannot restore readiness or notify: failure=$failure', () async {
      final hold = Completer<void>();
      var attempts = 0, notifications = 0;
      final service = LunoOnlineService.forTesting(
        bootstrap: () {
          attempts++;
          return hold.future;
        },
      );
      service.addListener(() => notifications++);
      final running = service.start();
      service.dispose();
      final before = notifications;
      if (failure) {
        hold.completeError(const LunoApiException('network-unavailable', 0));
      } else {
        hold.complete();
      }
      await running.timeout(const Duration(seconds: 1));
      expect(service.ready, isFalse);
      expect(service.loading, isFalse);
      expect(notifications, before);
      await expectLater(service.start(), throwsStateError);
      expect(attempts, 1);
    });
  }
}
