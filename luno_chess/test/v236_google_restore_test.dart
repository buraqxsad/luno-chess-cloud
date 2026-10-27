import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;

class _GoogleProvider extends Fake implements UserInfo {
  @override
  String get providerId => 'google.com';
}

class _RestoreUser extends TestUser {
  _RestoreUser(super.uid, {this.guest = false});
  final bool guest;
  @override
  bool get isAnonymous => guest;
  @override
  List<UserInfo> get providerData => guest ? [] : [_GoogleProvider()];
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User? user;
}

class _RestoreAuth extends TestAuth {
  int selections = 0;
  Future<UserCredential> Function()? choose;
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    if (credential.providerId != 'google.com') {
      throw StateError('Expected native Google credential');
    }
    selections++;
    return choose!();
  }
}

Map<String, dynamic> _state(String uid, {int gold = 777}) => {
  'uid': uid,
  'stateRevision': 1,
  'stateObservedAt': 100,
  'gold': gold,
  'gems': 23,
  'profile': {'username': 'returningluno', 'usernameGenerated': false},
  'stats': {'wins': 4, 'losses': 1, 'draws': 0},
};

void main() {
  setupPracticeTestAssets();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(LunoOnlineService, _RestoreAuth, GameStore)> fixture({
    Future<http.Response> Function(http.Request)? respond,
    bool startService = true,
  }) async {
    final auth =
        _RestoreAuth()..currentUser = _RestoreUser('guest', guest: true);
    final store = GameStore.createForTesting();
    await store.load();
    final online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
      playerStore: store,
      appCheck: () async => 'check',
      client: MockClient(
        respond ??
            (_) async => http.Response(
              jsonEncode({'ok': true, 'state': _state(auth.currentUser!.uid)}),
              200,
            ),
      ),
    );
    addTearDown(() {
      online.dispose();
      store.dispose();
    });
    if (startService) await online.start();
    store.data.gold = 9999;
    store.data.bio = 'private guest bio';
    await store.save();
    auth.choose = () async {
      auth.currentUser = _RestoreUser('existing');
      return _Credential(auth.currentUser);
    };
    return (online, auth, store);
  }

  test('Google account restore requires explicit confirmation', () async {
    final (online, auth, _) = await fixture();
    await expectLater(
      (online as dynamic).signInGoogle(confirmed: false),
      throwsA(
        isA<LunoApiException>().having(
          (e) => e.code,
          'code',
          'confirmation-required',
        ),
      ),
    );
    expect(auth.selections, 0);
  });

  test('restore loads server account without merging guest progress', () async {
    final (online, auth, store) = await fixture();
    expect(await (online as dynamic).signInGoogle(confirmed: true), 'existing');
    expect(auth.currentUser!.uid, 'existing');
    expect(store.accountUid, 'existing');
    expect(store.data.gold, 777);
    expect(store.data.gems, 23);
    expect(store.data.bio, isNot('private guest bio'));
    expect(store.hasChosenUsername, isTrue);
    expect(store.data.username, 'returningluno');
    expect(online.isOnline, isTrue);
    await store.bindAccount('guest');
    expect(store.data.gold, 9999, reason: 'guest archive remains separate');
  });

  test('cancel preserves guest and restores its connection', () async {
    final (online, auth, store) = await fixture();
    auth.choose =
        () async => throw FirebaseAuthException(code: 'web-context-canceled');
    await expectLater(
      (online as dynamic).signInGoogle(confirmed: true),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(auth.currentUser!.uid, 'guest');
    expect(store.accountUid, 'guest');
    expect(store.data.gold, 9999);
    expect(online.authTransitioning, isFalse);
    expect(online.isOnline, isTrue);
  });

  test(
    'restore before guest bootstrap quarantines unowned local progress',
    () async {
      final (online, _, store) = await fixture(startService: false);
      expect(store.accountUid, isNull);
      await (online as dynamic).signInGoogle(confirmed: true);
      expect(store.accountUid, 'existing');
      expect(store.data.gold, 777);
      expect(store.data.bio, isNot('private guest bio'));
      final prefs = await SharedPreferences.getInstance();
      final backup =
          jsonDecode(prefs.getString('luno_unowned_account_backup_v1')!) as Map;
      expect(backup['bio'], 'private guest bio');
      expect(prefs.getString('luno_unowned_account_backup_owner_v1'), isNull);
    },
  );

  test(
    'unconfirmed restored profile leaves chosen identity offline, never merges guest',
    () async {
      final (online, auth, store) = await fixture(
        respond:
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'state': {'uid': 'foreign', 'profile': {}},
              }),
              200,
            ),
      );
      await expectLater(
        (online as dynamic).signInGoogle(confirmed: true),
        throwsFormatException,
      );
      expect(auth.currentUser!.uid, 'existing');
      expect(store.accountUid, 'existing');
      expect(store.data.gold, isNot(9999));
      expect(online.isOnline, isFalse);
      expect(online.authTransitioning, isFalse);
    },
  );

  test('opening account selector invalidates an old HTTP response', () async {
    final oldResponse = Completer<http.Response>();
    final entered = Completer<void>();
    final (online, auth, store) = await fixture(
      respond: (request) async {
        if (request.url.path.endsWith('/old')) {
          entered.complete();
          return oldResponse.future;
        }
        return http.Response(
          jsonEncode({'ok': true, 'state': _state('existing')}),
          200,
        );
      },
    );
    final old = online.api('/old', {});
    await entered.future;
    final picker = Completer<UserCredential>();
    auth.choose = () => picker.future;
    final restore =
        (online as dynamic).signInGoogle(confirmed: true) as Future<String>;
    await Future<void>.delayed(Duration.zero);
    final rejected = expectLater(
      old,
      throwsA(
        isA<LunoApiException>().having(
          (e) => e.code,
          'code',
          'session-changed',
        ),
      ),
    );
    oldResponse.complete(
      http.Response(
        jsonEncode({'ok': true, 'state': _state('guest', gold: 90000)}),
        200,
      ),
    );
    await rejected;
    auth.currentUser = _RestoreUser('existing');
    picker.complete(_Credential(auth.currentUser));
    expect(await restore, 'existing');
    expect(store.data.gold, 777);
  });

  test(
    'another account selected during provider await cannot receive stale profile',
    () async {
      final (online, auth, store) = await fixture();
      final picker = Completer<UserCredential>();
      auth.choose = () => picker.future;
      final restore =
          (online as dynamic).signInGoogle(confirmed: true) as Future<String>;
      await Future<void>.delayed(Duration.zero);
      auth.currentUser = _RestoreUser('third');
      final rejected = expectLater(
        restore,
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'session-changed',
          ),
        ),
      );
      picker.complete(_Credential(_RestoreUser('existing')));
      await rejected;
      expect(store.accountUid, isNot('existing'));
      expect(auth.currentUser!.uid, 'third');
    },
  );

  test(
    'duplicate restore and link cannot race the native account picker',
    () async {
      final (online, auth, _) = await fixture();
      final picker = Completer<UserCredential>();
      auth.choose = () => picker.future;
      final restore =
          (online as dynamic).signInGoogle(confirmed: true) as Future<String>;
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        (online as dynamic).signInGoogle(confirmed: true),
        throwsA(isA<LunoApiException>()),
      );
      await expectLater(online.linkGoogle(), throwsA(isA<LunoApiException>()));
      await expectLater(
        online.deleteAccount(confirmed: true),
        throwsA(isA<LunoApiException>()),
      );
      auth.currentUser = _RestoreUser('existing');
      picker.complete(_Credential(auth.currentUser));
      await restore;
      expect(auth.selections, 1);
    },
  );

  for (final language in ['tr', 'en']) {
    testWidgets('settings exposes existing-account recovery $language', (
      tester,
    ) async {
      final (online, _, _) = await fixture();
      final settings = LunoSettings(deviceLocale: Locale(language));
      await settings.load();
      await tester.pumpWidget(
        shell(SettingsScreen(online: online, settings: settings)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('google-account-restore')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
