import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  setupPracticeTestAssets();
  for (final scenario in [
    'success',
    'double-submit',
    'missing-state',
    'wrong-username',
    'store-switch',
    'disposed',
    'covered',
  ]) {
    testWidgets('initial username is confirmed and owned: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      LunoSettings.instance.language = LunoSettings.languageEnglish;
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      final original = store.data.username;
      final response = Completer<http.Response>();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        appCheck: () async => 'test-only',
        client: MockClient((request) async {
          requests++;
          return response.future;
        }),
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await online.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          locale: const Locale('en'),
          supportedLocales: LunoLocalizations.supportedLocales,
          localizationsDelegates: const [
            LunoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: UsernameSetupScreen(store: store, online: online),
        ),
      );
      await tester.enterText(find.byType(TextField), 'LunoFriend');
      final submit =
          tester.widget<TextField>(find.byType(TextField)).onSubmitted!;
      submit('LunoFriend');
      if (scenario == 'double-submit') submit('LunoFriend');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, 1);
      if (scenario == 'store-switch') {
        await store.bindAccount('second');
      }
      if (scenario == 'disposed') await tester.pumpWidget(const SizedBox());
      if (scenario == 'covered') {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered')),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
      }
      response.complete(
        http.Response(
          jsonEncode({
            'ok': true,
            if (scenario != 'missing-state')
              'state': {
                'profile': {
                  'username':
                      scenario == 'wrong-username' ? 'wrongname' : 'lunofriend',
                },
              },
          }),
          200,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final accepted = scenario == 'success' || scenario == 'double-submit';
      expect(store.hasChosenUsername, accepted);
      expect(
        store.data.username,
        accepted
            ? 'lunofriend'
            : scenario == 'store-switch'
            ? isNot('lunofriend')
            : original,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
