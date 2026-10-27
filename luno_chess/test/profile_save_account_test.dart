import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final scenario in [
    'success',
    'malformed',
    'before-save',
    'during-save',
    'signout',
    'disposed',
  ]) {
    testWidgets('profile editor preserves account ownership: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      store.data.bio = 'original';
      final auth = TestAuth();
      final response = Completer<http.Response>();
      var requests = 0;
      Map<String, dynamic>? submitted;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        client: MockClient((request) async {
          requests++;
          submitted = Map<String, dynamic>.from(jsonDecode(request.body));
          return response.future;
        }),
        appCheck: () async => 'check',
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await online.start();
      LunoSettings.instance.language = LunoSettings.languageEnglish;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          localizationsDelegates: const [LunoLocalizations.delegate],
          theme: LunoTheme.dark,
          home: const Scaffold(body: Text('Profile home')),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder:
                (_) => EditProfileScreen(online: online, playerStore: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EDIT PROFILE'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'new biography');
      if (scenario == 'before-save') auth.currentUser = TestUser('second');
      final save = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Save',
      );
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 300));
      if (scenario == 'before-save') {
        expect(requests, 0);
        expect(store.data.bio, 'original');
        expect(
          find.text('Your account changed. Reopen the profile editor.'),
          findsOneWidget,
        );
        return;
      }
      expect(requests, 1);
      expect(submitted!['bio'], 'new biography');
      if (scenario == 'during-save') auth.currentUser = TestUser('second');
      if (scenario == 'signout') auth.currentUser = null;
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      response.complete(
        http.Response(
          jsonEncode({
            'ok': true,
            'state': {
              'profile': {
                ...submitted!,
                'bio': scenario == 'malformed' ? 'wrong' : 'new biography',
              },
            },
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        store.data.bio,
        scenario == 'success' || scenario == 'disposed'
            ? 'new biography'
            : 'original',
      );
      if (scenario == 'success') {
        expect(find.byType(EditProfileScreen), findsNothing);
        expect(find.text('Profile home'), findsOneWidget);
      } else if (scenario == 'malformed') {
        expect(
          find.text(
            'Your profile could not be saved. Check your connection and try again.',
          ),
          findsOneWidget,
        );
        expect(find.byType(EditProfileScreen), findsOneWidget);
      } else {
        expect(find.byType(SnackBar), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
