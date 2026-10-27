import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/account_operation_guard.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final boundary in [
    'none',
    'same-binding',
    'retry',
    'store-switch',
    'store-return',
    'auth-switch',
    'auth-signout',
    'auth-return',
    'dispose',
  ]) {
    test(
      'optimistic operation remains attached to $boundary account',
      () async {
        final store = GameStore.createForTesting();
        await store.bindAccount('first');
        final auth = TestAuth();
        final changes = StreamController<User?>.broadcast(sync: true);
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          authChanges: changes.stream,
        );
        var disposed = false;
        addTearDown(() async {
          if (!disposed) service.dispose();
          await changes.close();
          await store.flush();
          store.dispose();
        });
        await service.start();
        final guard = AccountOperationGuard(store, service);
        if (boundary == 'same-binding') await store.bindAccount('first');
        if (boundary == 'retry') await service.retry();
        if (boundary == 'store-switch' || boundary == 'store-return') {
          await store.bindAccount('second');
          if (boundary == 'store-return') await store.bindAccount('first');
        }
        if (boundary == 'auth-switch') auth.currentUser = TestUser('second');
        if (boundary == 'auth-signout' || boundary == 'auth-return') {
          auth.currentUser = null;
          changes.add(null);
          if (boundary == 'auth-return') {
            auth.currentUser = TestUser('first');
            changes.add(auth.currentUser);
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (boundary == 'dispose') {
          service.dispose();
          disposed = true;
        }
        final valid = ['none', 'same-binding', 'retry'].contains(boundary);
        expect(guard.isCurrent, valid);
        if (valid) {
          expect(guard.check, returnsNormally);
        } else {
          expect(guard.check, throwsA(isA<LunoApiException>()));
        }
      },
    );
  }
}
