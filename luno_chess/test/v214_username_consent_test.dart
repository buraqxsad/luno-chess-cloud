import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth;
import 'v214_ugc_safety_test.dart' show ugcReply;

void main() {
  setupPracticeTestAssets();
  for (final scenario in ['accept', 'decline', 'account']) {
    testWidgets('initial public username requires owned consent: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.createForTesting()..loaded = true..accountUid = 'first';
      final paths = <String>[];
      var accepted = false;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {}, auth: TestAuth(), appCheck: () async => 'test-only',
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/acceptLegalTerms')) {
            accepted = true;
            return http.Response(jsonEncode(ugcReply('first')), 200);
          }
          if (!accepted) {
            return http.Response(jsonEncode({'ok': false, 'error': 'legal-consent-required'}), 403);
          }
          return http.Response(jsonEncode({'ok': true, 'state': {
            'profile': {'username': 'lunofriend'},
          }}), 200);
        }),
      );
      addTearDown(() { online.dispose(); store.dispose(); });
      await online.start();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'), supportedLocales: LunoLocalizations.supportedLocales,
        localizationsDelegates: const [LunoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate],
        home: UsernameSetupScreen(store: store, online: online),
      ));
      await tester.enterText(find.byType(TextField), 'LunoFriend');
      final submit = tester.widget<TextField>(find.byType(TextField)).onSubmitted!;
      submit('LunoFriend');
      submit('LunoFriend');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(paths.length, 1);
      expect(store.hasChosenUsername, false);
      expect(find.byKey(const Key('ugc-consent-checkbox')), findsOneWidget);
      if (scenario == 'accept') {
        await tester.ensureVisible(find.byKey(const Key('ugc-consent-checkbox')));
        await tester.tap(find.byKey(const Key('ugc-consent-checkbox')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const Key('ugc-consent-accept')));
      } else if (scenario == 'decline') {
        await tester.tap(find.byKey(const Key('ugc-consent-decline')));
      } else {
        await store.bindAccount('other');
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paths.length, scenario == 'accept' ? 3 : 1);
      expect(store.hasChosenUsername, scenario == 'accept');
      if (scenario == 'accept') expect(store.data.username, 'lunofriend');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('offline chosen draft survives restart but cannot cross accounts', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.load();
    await store.bindAccount('first');
    await store.chooseUsername('LunoFriend');
    final economy = store.data.toJson();
    await store.requireUsernamePublication('first', store.accountBindingRevision, store.data.username);
    expect(store.hasChosenUsername, false);
    expect(store.pendingUsernameDraft, 'lunofriend');
    expect(store.data.toJson(), economy);
    final restored = GameStore.createForTesting();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.pendingUsernameDraft, 'lunofriend');
    final revision = restored.accountBindingRevision;
    await restored.bindAccount('other');
    await restored.requireUsernamePublication('first', revision, 'StaleName');
    expect(restored.pendingUsernameDraft, isEmpty);
    await restored.bindAccount('first');
    expect(restored.pendingUsernameDraft, 'lunofriend');
    await restored.chooseUsername('Published');
    expect(restored.pendingUsernameDraft, isEmpty);
  });
}
