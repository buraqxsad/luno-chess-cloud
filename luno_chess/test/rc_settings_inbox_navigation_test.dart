import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'google_link_flow_test.dart' show GoogleLinkUser;
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  setupPracticeTestAssets();
  for (final switched in [false, true]) {
    testWidgets('Google link bootstrap preserves action owner $switched', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      LunoSettings.instance.language = LunoSettings.languageTurkish;
      final first = GoogleLinkUser('first');
      final auth = TestAuth()..currentUser = first;
      final pending = Completer<void>();
      final paths = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () => pending.future,
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          final path = request.url.path.split('/').last;
          paths.add(path);
          return http.Response(
            jsonEncode(
              path == 'prepareGoogleLink'
                  ? {'ok': true, 'alreadyLinked': false, 'attemptId': 'a' * 32}
                  : {'ok': true, 'linked': true, 'uid': 'first', 'state': {}},
            ),
            200,
          );
        }),
      );
      addTearDown(online.dispose);
      await tester.pumpWidget(shell(SettingsScreen(online: online)));
      final button = find.ancestor(
        of: find.text('Google hesabını bağla'),
        matching: find.byType(ListTile),
      );
      tester.widget<ListTile>(button).onTap!();
      await tester.pump();
      if (switched) auth.currentUser = GoogleLinkUser('second');
      pending.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(paths.length, switched ? 0 : 2);
      expect(first.links, switched ? 0 : 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('settings replay is single route and old callbacks are inert', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    LunoSettings.instance.language = LunoSettings.languageTurkish;
    await tester.pumpWidget(shell(const SettingsScreen()));
    final button = find.ancestor(
      of: find.text('Rehberi yeniden izle'),
      matching: find.byType(ListTile),
    );
    final action = tester.widget<ListTile>(button).onTap!;
    action();
    action();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('REHBER  1/10', skipOffstage: false), findsOneWidget);
    action();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('REHBER  1/10', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    action();
    expect(tester.takeException(), isNull);
  });
  for (final scenario in ['repeat', 'account', 'disposed']) {
    testWidgets('inbox conversation callback respects $scenario state', (
      tester,
    ) async {
      final auth = TestAuth();
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        databaseRead: (_) async => {},
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(shell(InboxScreen(online: online)));
      await tester.pump();
      await tester.pump();
      final dynamic state = tester.state(find.byType(InboxScreen));
      state.setState(() {
        state.tab = 1;
        state.connecting = false;
        state.error = null;
        state.notificationStream = Stream<List<Map<String, dynamic>>>.value([]);
        state.inboxStream = Stream.value([
          {'targetUid': 'friend', 'username': 'luno_friend', 'last': 'Hello'},
        ]);
      });
      await tester.pump();
      await tester.pump();
      final action =
          tester
              .widget<ListTile>(
                find.ancestor(
                  of: find.text('luno_friend'),
                  matching: find.byType(ListTile),
                ),
              )
              .onTap!;
      if (scenario == 'account') auth.currentUser = TestUser('second');
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      action();
      if (scenario == 'repeat') action();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        find.byType(DirectMessageScreen, skipOffstage: false),
        scenario == 'repeat' ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
