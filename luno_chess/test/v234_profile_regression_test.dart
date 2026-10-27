import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/profile_update_result.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

class _ProfileSession {
  _ProfileSession(String uid, {bool holdResponse = false}) {
    store =
        GameStore.createForTesting()
          ..loaded = true
          ..accountUid = uid;
    store.data.bio = '$uid biography';
    auth.currentUser = TestUser(uid);
    online = LunoOnlineService.forTesting(
      auth: auth,
      bootstrap: () async {},
      appCheck: () async => 'check',
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/updateProfile'));
        final submitted = jsonDecode(request.body) as Map<String, dynamic>;
        submissions.add(submitted);
        if (holdResponse) return response.future;
        return confirmed(submitted);
      }),
    );
  }

  final auth = TestAuth();
  final submissions = <Map<String, dynamic>>[];
  final response = Completer<http.Response>();
  late final GameStore store;
  late final LunoOnlineService online;

  static http.Response confirmed(Map<String, dynamic> submitted) =>
      http.Response(
        jsonEncode({
          'ok': true,
          'state': {'profile': submitted},
        }),
        200,
      );

  void dispose() {
    online.dispose();
    store.dispose();
  }
}

Future<void> _mountEditor(
  WidgetTester tester,
  ValueNotifier<({LunoOnlineService online, GameStore store})> binding,
) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: LunoTheme.dark,
      locale: const Locale('en'),
      localizationsDelegates: const [LunoLocalizations.delegate],
      home: const Scaffold(body: Text('Profile home')),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder:
            (_) => ValueListenableBuilder(
              valueListenable: binding,
              builder:
                  (_, value, _) => EditProfileScreen(
                    key: const ValueKey('profile-editor'),
                    online: value.online,
                    playerStore: value.store,
                  ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Old account draft');
}

Finder _saveButton() => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'Save',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final language = LunoSettings.instance.language;
    LunoSettings.instance.language = LunoSettings.languageEnglish;
    addTearDown(() => LunoSettings.instance.language = language);
  });

  test(
    'profile confirmation preserves optional snapshot ordering metadata',
    () {
      const submitted = {
        'country': 'JP',
        'avatarEmoji': 'av_knight',
        'bio': 'Confirmed biography',
      };
      for (final metadata in <Map<String, dynamic>>[
        {},
        {'stateRevision': 7},
        {'stateObservedAt': 1791900000000},
        {'stateRevision': 7, 'stateObservedAt': 1791900000000},
      ]) {
        final state = <String, dynamic>{'profile': submitted, ...metadata};
        final confirmed = validateProfileUpdateResult({
          'ok': true,
          'state': state,
        }, submitted);
        expect(confirmed, state);
        expect(identical(confirmed, state), isFalse);
      }
    },
  );

  for (final replacement in ['online', 'store', 'both']) {
    testWidgets('profile save rejects replaced $replacement binding', (
      tester,
    ) async {
      final original = _ProfileSession('first');
      final next = _ProfileSession('second');
      final binding = ValueNotifier((
        online: original.online,
        store: original.store,
      ));
      addTearDown(() {
        binding.dispose();
        original.dispose();
        next.dispose();
      });
      await original.online.start();
      await next.online.start();
      await _mountEditor(tester, binding);
      binding.value = (
        online: replacement == 'store' ? original.online : next.online,
        store: replacement == 'online' ? original.store : next.store,
      );
      await tester.pump();
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      expect(original.submissions, isEmpty);
      expect(next.submissions, isEmpty);
      expect(original.store.data.bio, 'first biography');
      expect(next.store.data.bio, 'second biography');
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(
        find.text('Your account changed. Reopen the profile editor.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late profile save cannot apply to a replacement binding', (
    tester,
  ) async {
    final original = _ProfileSession('first', holdResponse: true);
    final next = _ProfileSession('second');
    final binding = ValueNotifier((
      online: original.online,
      store: original.store,
    ));
    addTearDown(() {
      binding.dispose();
      original.dispose();
      next.dispose();
    });
    await original.online.start();
    await next.online.start();
    await _mountEditor(tester, binding);
    await tester.tap(_saveButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(original.submissions, hasLength(1));
    binding.value = (online: next.online, store: next.store);
    await tester.pump();
    original.response.complete(
      _ProfileSession.confirmed(original.submissions.single),
    );
    await tester.pumpAndSettle();

    expect(next.submissions, isEmpty);
    expect(next.store.data.bio, 'second biography');
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('Profile updated.'), findsNothing);
    expect(tester.widget<IconButton>(_saveButton()).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
