import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'rc_account_confirmation_owner_test.dart' show advance, buttonAction;

void main() {
  setupPracticeTestAssets();
  const copy = LunoLocalizations(Locale('tr'));
  for (final surface in ['inbox', 'guest']) {
    for (final scenario in ['covered', 'account']) {
      testWidgets('$surface information modal owns $scenario dismissal', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final settings = LunoSettings(deviceLocale: const Locale('tr'));
        await tester.runAsync(settings.load);
        GameStore.instance
          ..loaded = true
          ..data = PlayerData.initial();
        final auth = TestAuth();
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          databaseRead: (_) async => {},
        );
        final notifications =
            StreamController<List<Map<String, dynamic>>>.broadcast(sync: true);
        addTearDown(() async {
          online.dispose();
          await notifications.close();
        });
        await online.start();
        await tester.pumpWidget(
          shell(
            surface == 'inbox'
                ? InboxScreen(online: online)
                : SettingsScreen(online: online, settings: settings),
          ),
        );
        await advance(tester);
        late VoidCallback open;
        if (surface == 'inbox') {
          final dynamic state = tester.state(find.byType(InboxScreen));
          state.setState(() {
            state.notificationStream = notifications.stream;
            state.inboxStream = Stream.value(<Map<String, dynamic>>[]);
            state.error = null;
          });
          await tester.pump();
          notifications.add([
            {
              'notificationId': 'n1',
              'read': true,
              'type': 'general',
              'message': 'RC notification details',
            },
          ]);
          await advance(tester);
          open =
              tester
                  .widget<InkWell>(
                    find
                        .ancestor(
                          of: find.text('RC notification details'),
                          matching: find.byType(InkWell),
                        )
                        .first,
                  )
                  .onTap!;
        } else {
          open =
              tester
                  .widget<ListTile>(
                    find.ancestor(
                      of: find.text(copy.signOut),
                      matching: find.byType(ListTile),
                    ),
                  )
                  .onTap!;
        }
        open();
        open();
        await advance(tester);
        final modal =
            surface == 'inbox'
                ? find.byType(BottomSheet, skipOffstage: false)
                : find.byType(AlertDialog, skipOffstage: false);
        expect(modal, findsOneWidget);
        final close = buttonAction(tester, copy.ok);
        final navigator = Navigator.of(tester.element(modal));
        if (scenario == 'covered') {
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('information-cover')),
              ),
            ),
          );
          await advance(tester);
          close();
          await advance(tester);
          expect(find.text('information-cover'), findsOneWidget);
          expect(modal, findsOneWidget);
          navigator.pop();
          await advance(tester);
          close();
          close();
          await advance(tester);
          expect(modal, findsNothing);
          expect(
            find.byType(surface == 'inbox' ? InboxScreen : SettingsScreen),
            findsOneWidget,
          );
        } else {
          auth.currentUser = TestUser('second');
          online.notifyListeners();
          await advance(tester);
          expect(modal, findsNothing);
        }
        expect(close, returnsNormally);
        await tester.pumpWidget(const SizedBox());
        expect(close, returnsNormally);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
