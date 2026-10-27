import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecoveryUser extends Fake implements User {
  RecoveryUser(this.uid, {this.reloadAction, this.tokenAction});

  @override
  final String uid;
  Future<void> Function()? reloadAction;
  Future<String?> Function(bool)? tokenAction;
  int reloads = 0;
  final refreshes = <bool>[];

  @override
  bool get isAnonymous => true;

  @override
  Future<void> reload() async {
    reloads++;
    await reloadAction?.call();
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    refreshes.add(forceRefresh);
    return tokenAction == null
        ? 'token-$uid'
        : await tokenAction!(forceRefresh);
  }
}

class RecoveryCredential extends Fake implements UserCredential {
  RecoveryCredential(this.user);

  @override
  final User user;
}

class RecoveryAuth extends Fake implements FirebaseAuth {
  RecoveryAuth(this.currentUser);

  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast(sync: true);
  int signOuts = 0;
  int anonymousSignIns = 0;
  Object? signInFailure;
  bool delayEvents = false;
  final pendingEvents = <User?>[];

  void changeUser(User? next) {
    currentUser = next;
    if (delayEvents) {
      pendingEvents.add(next);
    } else {
      changes.add(next);
    }
  }

  void flushEvents() {
    for (final next in pendingEvents) {
      changes.add(next);
    }
    pendingEvents.clear();
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    changeUser(null);
  }

  @override
  Future<UserCredential> signInAnonymously() async {
    anonymousSignIns++;
    if (signInFailure != null) throw signInFailure!;
    final fresh = RecoveryUser('fresh-$anonymousSignIns');
    changeUser(fresh);
    return RecoveryCredential(fresh);
  }
}

class PausedErasureStore extends Fake implements GameStore {
  final entered = Completer<void>();
  final finish = Completer<void>();
  final erasedUids = <String>[];

  @override
  String? accountUid;

  @override
  int serverStateEpoch = 0;

  @override
  void invalidateServerStates() => serverStateEpoch++;

  @override
  Future<void> bindAccount(String? uid, {bool restoreExisting = false}) async =>
      accountUid = uid;

  @override
  Future<void> eraseLocalAccount(String uid) {
    erasedUids.add(uid);
    entered.complete();
    return finish.future;
  }
}

Matcher apiError(String code) => throwsA(
  isA<LunoApiException>().having((error) => error.code, 'code', code),
);

LunoOnlineService makeService(
  RecoveryAuth auth, {
  bool validateAuth = false,
  GameStore? store,
  Future<void> Function()? bootstrap,
  http.Client? client,
  Future<String?> Function()? appCheck,
}) {
  final service = LunoOnlineService.forTesting(
    auth: auth,
    authChanges: auth.changes.stream,
    validateAuth: validateAuth,
    playerStore: store,
    bootstrap: bootstrap ?? () async {},
    client: client,
    appCheck: appCheck ?? () async => 'test-app-check',
  );
  addTearDown(service.dispose);
  addTearDown(auth.changes.close);
  return service;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final code in [
    'user-not-found',
    'user-token-expired',
    'invalid-user-token',
  ]) {
    test(
      'startup recovers $code once without copying the old account',
      () async {
        final cached = RecoveryUser(
          'deleted-tester',
          reloadAction: () async => throw FirebaseAuthException(code: code),
        );
        final auth = RecoveryAuth(cached);
        final store = GameStore.createForTesting();
        await store.bindAccount(cached.uid);
        store.data.gold = 9876;
        await store.completeTutorial();
        final service = makeService(auth, validateAuth: true, store: store);

        await Future.wait([service.start(), service.start()]);

        expect(service.ready, isTrue);
        expect(service.lastError, isNull);
        expect(service.authTransitioning, isFalse);
        expect(service.user?.uid, 'fresh-1');
        expect(auth.signOuts, 1);
        expect(auth.anonymousSignIns, 1);
        expect(cached.reloads, 1);
        expect(store.accountUid, 'fresh-1');
        expect(store.data.gold, PlayerData.initial().gold);
        expect(store.hasCompletedTutorial, isFalse);
        await service.start();
        expect(auth.anonymousSignIns, 1);
        if (code == 'user-not-found') {
          await expectLater(
            store.bindAccount(cached.uid),
            throwsA(isA<LocalAccountErasedException>()),
          );
        } else {
          await store.bindAccount(cached.uid);
          expect(store.data.gold, 9876);
          expect(store.hasCompletedTutorial, isTrue);
        }
      },
    );
  }

  test('startup accepts a healthy cached UID without replacing it', () async {
    final cached = RecoveryUser('linked-account');
    final auth = RecoveryAuth(cached);
    final service = makeService(auth, validateAuth: true);

    await service.start();

    expect(service.ready, isTrue);
    expect(service.user, same(cached));
    expect(cached.reloads, 1);
    expect(auth.signOuts, 0);
    expect(auth.anonymousSignIns, 0);
    expect(service.accountRevision, 0);
  });

  for (final failure in <Object>[
    FirebaseAuthException(code: 'network-request-failed'),
    FirebaseAuthException(code: 'user-disabled'),
    FirebaseAuthException(code: 'invalid-credential'),
    FirebaseException(plugin: 'firebase_app_check', code: 'invalid-user-token'),
    StateError('user-not-found network App Check'),
  ]) {
    test('startup preserves cached data for $failure', () async {
      final cached = RecoveryUser(
        'existing',
        reloadAction: () async => throw failure,
      );
      final auth = RecoveryAuth(cached);
      final store = GameStore.createForTesting();
      await store.bindAccount(cached.uid);
      store.data.gold = 3456;
      final service = makeService(auth, validateAuth: true, store: store);

      await service.start();
      await service.retry();

      expect(service.ready, isFalse);
      expect(service.lastError, isNotNull);
      expect(service.user, same(cached));
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 0);
      expect(store.accountUid, cached.uid);
      expect(store.data.gold, 3456);
      await store.bindAccount(cached.uid);
    });
  }

  test(
    'SDK auto-sign-out still recovers a confirmed deleted cached user',
    () async {
      final cached = RecoveryUser('deleted');
      final auth = RecoveryAuth(cached);
      cached.reloadAction = () async {
        auth.changeUser(null);
        throw FirebaseAuthException(code: 'user-not-found');
      };
      final service = makeService(auth, validateAuth: true);

      await service.start();

      expect(service.ready, isTrue);
      expect(service.user?.uid, 'fresh-1');
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 1);
    },
  );

  test(
    'delayed recovery auth events cannot strand a running bootstrap',
    () async {
      final cached = RecoveryUser(
        'deleted',
        reloadAction:
            () async => throw FirebaseAuthException(code: 'user-not-found'),
      );
      final auth = RecoveryAuth(cached)..delayEvents = true;
      final entered = Completer<void>();
      final finish = Completer<void>();
      var bootstraps = 0;
      final service = makeService(
        auth,
        validateAuth: true,
        bootstrap: () async {
          if (++bootstraps == 1) {
            entered.complete();
            await finish.future;
          }
        },
      );
      final pending = service.start();
      await entered.future;
      auth.flushEvents();
      finish.complete();

      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(service.ready, isTrue);
      expect(service.lastError, isNull);
      expect(service.authTransitioning, isFalse);
      expect(service.user?.uid, 'fresh-1');
      expect(auth.signOuts, 1);
      expect(auth.anonymousSignIns, 1);
      expect(bootstraps, 2);
    },
  );

  test(
    'late invalid-user failure cannot sign out a switched account',
    () async {
      final reload = Completer<void>();
      final cached = RecoveryUser('old', reloadAction: () => reload.future);
      final auth = RecoveryAuth(cached);
      final service = makeService(auth, validateAuth: true);
      final pending = service.start();
      final switched = RecoveryUser('new-linked');
      auth.changeUser(switched);
      reload.completeError(FirebaseAuthException(code: 'user-not-found'));

      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(service.user, same(switched));
      expect(service.ready, isTrue);
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 0);
    },
  );

  test(
    'parallel token failures share recovery and never replay old mutations',
    () async {
      final cached = RecoveryUser(
        'old',
        tokenAction:
            (_) async =>
                throw FirebaseAuthException(code: 'user-token-expired'),
      );
      final auth = RecoveryAuth(cached);
      var bootstraps = 0;
      var requests = 0;
      final service = makeService(
        auth,
        bootstrap: () async => bootstraps++,
        client: MockClient((_) async {
          requests++;
          return http.Response('{"ok":true}', 200);
        }),
      );
      await service.start();

      await Future.wait([
        expectLater(
          service.api('/oldMutationA', {}),
          apiError('session-changed'),
        ),
        expectLater(
          service.api('/oldMutationB', {}),
          apiError('session-changed'),
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(auth.signOuts, 1);
      expect(auth.anonymousSignIns, 1);
      expect(requests, 0);
      expect(bootstraps, 2);
      expect(service.ready, isTrue);
      expect(service.user?.uid, 'fresh-1');
      await service.api('/newRequest', {});
      expect(requests, 1);
    },
  );

  test(
    'account switch during cleanup resumes only the switched account',
    () async {
      final cached = RecoveryUser(
        'old',
        reloadAction:
            () async => throw FirebaseAuthException(code: 'user-not-found'),
      );
      final auth = RecoveryAuth(cached);
      final store = PausedErasureStore();
      final service = makeService(auth, validateAuth: true, store: store);
      final pending = service.start();
      await store.entered.future;
      final switched = RecoveryUser('new-linked');
      auth.changeUser(switched);
      store.finish.complete();

      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(service.user, same(switched));
      expect(service.ready, isTrue);
      expect(store.accountUid, switched.uid);
      expect(store.erasedUids, ['old']);
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 0);
    },
  );

  test(
    'forced refresh after HTTP rejection recovers only a typed auth failure',
    () async {
      final cached = RecoveryUser(
        'deleted',
        tokenAction: (forceRefresh) async {
          if (forceRefresh) {
            throw FirebaseAuthException(code: 'user-not-found');
          }
          return 'cached-token';
        },
      );
      final auth = RecoveryAuth(cached);
      var requests = 0;
      final service = makeService(
        auth,
        client: MockClient((_) async {
          requests++;
          return http.Response('{"ok":false,"error":"invalid-token"}', 401);
        }),
      );
      await service.start();

      await expectLater(
        service.api('/oldMutation', {}),
        apiError('session-changed'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cached.refreshes, [false, true]);
      expect(requests, 1);
      expect(auth.signOuts, 1);
      expect(auth.anonymousSignIns, 1);
      expect(service.ready, isTrue);
    },
  );

  for (final response in [
    http.Response('{"ok":false,"error":"invalid-token"}', 401),
    http.Response('{"ok":false,"error":"app-check-required"}', 401),
    http.Response('{"ok":false,"error":"invalid-app-check"}', 403),
  ]) {
    test('HTTP ${response.body} cannot erase or replace an identity', () async {
      final cached = RecoveryUser('existing');
      final auth = RecoveryAuth(cached);
      final service = makeService(
        auth,
        client: MockClient((_) async => response),
      );
      await service.start();

      await expectLater(
        service.api('/getPlayerState', {}),
        throwsA(isA<LunoApiException>()),
      );

      expect(service.user, same(cached));
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 0);
      expect(cached.reloads, 0);
      if (response.body.contains('invalid-token')) {
        expect(cached.refreshes, [false, true, true]);
      }
    });
  }

  test('App Check token exception cannot trigger auth recovery', () async {
    final cached = RecoveryUser('existing');
    final auth = RecoveryAuth(cached);
    final failure = FirebaseException(
      plugin: 'firebase_app_check',
      code: 'invalid-user-token',
    );
    final service = makeService(auth, appCheck: () async => throw failure);
    await service.start();

    await expectLater(
      service.api('/getPlayerState', {}),
      throwsA(same(failure)),
    );

    expect(service.user, same(cached));
    expect(auth.signOuts, 0);
    expect(auth.anonymousSignIns, 0);
  });

  test(
    'invalid auth during Google link is not replaced with a guest',
    () async {
      final cached = RecoveryUser(
        'linking',
        tokenAction:
            (_) async =>
                throw FirebaseAuthException(code: 'invalid-user-token'),
      );
      final auth = RecoveryAuth(cached);
      final service = makeService(auth);
      await service.start();

      await expectLater(
        service.linkGoogle(),
        throwsA(isA<FirebaseAuthException>()),
      );

      expect(service.user, same(cached));
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 0);
    },
  );

  test(
    'invalid auth during account deletion does not create a guest',
    () async {
      final cached = RecoveryUser(
        'deleting',
        tokenAction:
            (_) async =>
                throw FirebaseAuthException(code: 'invalid-user-token'),
      );
      final auth = RecoveryAuth(cached);
      final service = makeService(auth);
      await service.start();

      await expectLater(
        service.deleteAccount(confirmed: true),
        throwsA(isA<FirebaseAuthException>()),
      );

      expect(service.user, same(cached));
      expect(auth.signOuts, 0);
      expect(auth.anonymousSignIns, 0);
    },
  );

  test(
    'anonymous sign-in failure is retryable without erasing another account',
    () async {
      final cached = RecoveryUser(
        'deleted',
        reloadAction:
            () async => throw FirebaseAuthException(code: 'user-not-found'),
      );
      final auth = RecoveryAuth(cached)
        ..signInFailure = FirebaseAuthException(code: 'network-request-failed');
      final service = makeService(auth, validateAuth: true);

      await service.start();
      expect(service.ready, isFalse);
      expect(service.lastError, isNotNull);
      expect(service.authTransitioning, isFalse);
      auth.signInFailure = null;
      await service.retry();

      expect(service.ready, isTrue);
      expect(service.user?.uid, 'fresh-2');
      expect(auth.signOuts, 1);
    },
  );
}
