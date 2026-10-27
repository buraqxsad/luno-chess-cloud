import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  late TestAuth auth;
  late LunoOnlineService service;
  late List<StreamController<List<Map<String, dynamic>>>> controllers;
  var disposed = false;

  setUp(() async {
    disposed = false;
    auth = TestAuth();
    service = LunoOnlineService.forTesting(bootstrap: () async {}, auth: auth);
    controllers = List.generate(
      4,
      (_) => StreamController.broadcast(sync: true),
    );
    await service.start();
    service.bindActivityStreamsForTesting([
      for (final controller in controllers) controller.stream,
    ]);
  });

  tearDown(() async {
    if (!disposed) service.dispose();
    for (final controller in controllers) {
      await controller.close();
    }
  });

  void emit() {
    for (final controller in controllers) {
      controller.add([
        {'read': false, 'unread': true},
      ]);
    }
  }

  void expectCounts(int count) {
    expect(service.unreadNotificationCount, count);
    expect(service.unreadDirectMessageCount, count);
    expect(service.pendingFriendRequestCount, count);
    expect(service.pendingMatchInviteCount, count);
    expect(service.socialActivityBadgeCount, count);
  }

  test('current activity updates all four badges', () {
    emit();
    expectCounts(1);
    controllers.first.addError(
      const LunoApiException('network-unavailable', 0),
    );
    expect(service.lastError, isNotNull);
  });

  for (final change in ['account', 'signout']) {
    test('$change hides cached activity and ignores old data/errors', () {
      emit();
      expectCounts(1);
      auth.currentUser = change == 'account' ? TestUser('second') : null;
      expectCounts(0);
      var notifications = 0;
      service.addListener(() => notifications++);
      emit();
      for (final controller in controllers) {
        controller.addError(const LunoApiException('network-unavailable', 0));
      }
      expectCounts(0);
      expect(service.lastError, isNull);
      expect(notifications, 0);
    });
  }

  test('rebootstrap clears badges and cancels every previous stream', () async {
    emit();
    await service.retry();
    expectCounts(0);
    expect(controllers.every((controller) => !controller.hasListener), isTrue);
    emit();
    expectCounts(0);
  });

  for (final code in ['account-deleted', 'account-deletion-in-progress']) {
    test('$code hides badges and prevents later activity updates', () {
      emit();
      controllers.first.addError(LunoApiException(code, 403));
      expect(service.accountFailure?.code, code);
      expectCounts(0);
      var notifications = 0;
      service.addListener(() => notifications++);
      emit();
      controllers.last.addError(
        const LunoApiException('network-unavailable', 0),
      );
      expectCounts(0);
      expect(service.accountFailure?.code, code);
      expect(notifications, 0);
    });
  }

  test('rebinding to new account replaces old listeners and badges', () async {
    emit();
    auth.currentUser = TestUser('second');
    final fresh = List.generate(
      4,
      (_) => StreamController<List<Map<String, dynamic>>>.broadcast(sync: true),
    );
    service.bindActivityStreamsForTesting([
      for (final controller in fresh) controller.stream,
    ]);
    expectCounts(0);
    expect(controllers.every((controller) => !controller.hasListener), isTrue);
    emit();
    expectCounts(0);
    for (final controller in fresh) {
      controller.add([
        {'read': false, 'unread': true},
      ]);
    }
    expectCounts(1);
    service.dispose();
    disposed = true;
    for (final controller in fresh) {
      await controller.close();
    }
  });

  test('dispose detaches every activity listener', () {
    emit();
    service.dispose();
    disposed = true;
    expect(controllers.every((controller) => !controller.hasListener), isTrue);
    emit();
    expectCounts(0);
  });

  test(
    'signed out public streams never use the cached Firebase user',
    () async {
      auth.currentUser = null;
      for (final stream in [
        service.notificationsStream(),
        service.directMessageInboxStream(),
        service.directMessagesStream('other'),
        service.friendRequestsStream(),
        service.matchInvitesStream(),
      ]) {
        expect(await stream.first, isEmpty);
      }
    },
  );
}
