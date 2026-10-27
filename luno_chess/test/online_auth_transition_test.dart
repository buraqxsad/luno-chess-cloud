import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  test(
    'auth identity changes reset readiness and bootstrap the new account',
    () async {
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      var bootstraps = 0;
      final service = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: events.stream,
        bootstrap: () async {
          bootstraps++;
        },
      );
      addTearDown(service.dispose);
      addTearDown(events.close);
      await service.start();
      events.add(auth.currentUser);
      expect(service.accountRevision, 0);
      expect(bootstraps, 1);
      auth.currentUser = TestUser('second');
      events.add(auth.currentUser);
      expect(service.ready, isFalse);
      expect(service.authTransitioning, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(service.accountRevision, 1);
      expect(service.ready, isTrue);
      expect(service.authTransitioning, isFalse);
      expect(bootstraps, 2);
      auth.currentUser = null;
      events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(service.ready, isFalse);
      expect(service.authTransitioning, isFalse);
      expect(bootstraps, 2);
    },
  );

  test(
    'same UID after sign-out still invalidates an outstanding read',
    () async {
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final entered = Completer<void>();
      final response = Completer<Object?>();
      final service = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: events.stream,
        bootstrap: () async {},
        databaseRead: (_) {
          entered.complete();
          return response.future;
        },
      );
      addTearDown(service.dispose);
      addTearDown(events.close);
      await service.start();
      final pending = service.friendRequests();
      await entered.future;
      auth.currentUser = null;
      events.add(null);
      auth.currentUser = TestUser('first');
      events.add(auth.currentUser);
      final assertion = expectLater(
        pending,
        throwsA(
          isA<LunoApiException>().having(
            (error) => error.code,
            'code',
            'session-changed',
          ),
        ),
      );
      response.complete({});
      await assertion;
      await Future<void>.delayed(Duration.zero);
      expect(service.accountRevision, 2);
    },
  );

  test(
    'account switch waits for old bootstrap without accepting its completion',
    () async {
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final old = Completer<void>();
      final fresh = Completer<void>();
      var bootstraps = 0;
      final service = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: events.stream,
        bootstrap: () => ++bootstraps == 1 ? old.future : fresh.future,
      );
      addTearDown(service.dispose);
      addTearDown(events.close);
      final initial = service.start();
      auth.currentUser = TestUser('second');
      events.add(auth.currentUser);
      old.complete();
      await initial;
      await Future<void>.delayed(Duration.zero);
      expect(service.ready, isFalse);
      expect(service.authTransitioning, isTrue);
      expect(bootstraps, 2);
      fresh.complete();
      await Future<void>.delayed(Duration.zero);
      expect(service.ready, isTrue);
      expect(service.authTransitioning, isFalse);
    },
  );

  test(
    'initial anonymous sign-in does not invalidate its own bootstrap',
    () async {
      final auth = TestAuth()..currentUser = null;
      final events = StreamController<User?>.broadcast(sync: true);
      final complete = Completer<void>();
      var bootstraps = 0;
      final service = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: events.stream,
        bootstrap: () {
          bootstraps++;
          return complete.future;
        },
      );
      addTearDown(service.dispose);
      addTearDown(events.close);
      final pending = service.start();
      auth.currentUser = TestUser('guest');
      events.add(auth.currentUser);
      complete.complete();
      await pending;
      expect(service.ready, isTrue);
      expect(bootstraps, 1);
    },
  );

  test(
    'dispose during auth restart cancels listeners and late notifications',
    () async {
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final pendingBootstrap = Completer<void>();
      var bootstraps = 0;
      final service = LunoOnlineService.forTesting(
        auth: auth,
        authChanges: events.stream,
        bootstrap: () async {
          if (++bootstraps > 1) await pendingBootstrap.future;
        },
      );
      addTearDown(events.close);
      await service.start();
      auth.currentUser = TestUser('second');
      events.add(auth.currentUser);
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      expect(events.hasListener, isFalse);
      expect(service.isOnline, isFalse);
      pendingBootstrap.complete();
      await Future<void>.delayed(Duration.zero);
      await expectLater(service.start(), throwsStateError);
    },
  );
}
