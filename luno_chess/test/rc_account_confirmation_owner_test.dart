import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth;

VoidCallback buttonAction(WidgetTester tester, String label) {
  final button =
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton || widget is LunoButton,
            ),
          )
          .first;
  final widget = tester.widget(button);
  return widget is LunoButton
      ? widget.onPressed!
      : (widget as ButtonStyleButton).onPressed!;
}

Future<void> advance(WidgetTester tester) async {
  // A pending confirmation intentionally leaves its owner's spinner active.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setupPracticeTestAssets();
  for (final screen in ['friends', 'consent', 'delete']) {
    for (final confirm in [false, true]) {
      testWidgets('$screen confirmation $confirm owns only its dialog', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        LunoSettings.instance.language = LunoSettings.languageTurkish;
        GameStore.instance
          ..loaded = true
          ..data = PlayerData.initial();
        final requests = <String>[];
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: TestAuth(),
          appCheck: () async => 'local-test',
          databaseRead: (path) async {
            if (path.startsWith('friends/')) return {'friend': true};
            if (path.startsWith('publicProfiles/')) {
              return {'username': 'luno_friend', 'trophies': 500};
            }
            return {};
          },
          friendRequestStream: Stream.value(const []),
          matchInviteStream: Stream.value(const []),
          directMessageStream: (_) => Stream.value(const []),
          client: MockClient((request) async {
            final path = request.url.path.split('/').last;
            requests.add(path);
            if (path == 'sendDirectMessage') {
              return http.Response(
                '{"ok":false,"error":"legal-consent-required"}',
                403,
              );
            }
            return http.Response(
              jsonEncode({'ok': true, 'conversationId': 'first_friend'}),
              200,
            );
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        final page = switch (screen) {
          'friends' => FriendsScreen(online: online),
          'consent' => DirectMessageScreen(
            targetUid: 'friend',
            targetName: 'luno_friend',
            online: online,
          ),
          _ => SettingsScreen(online: online),
        };
        await tester.pumpWidget(shell(page));
        await advance(tester);
        if (screen == 'friends') {
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Arkadaşlıktan çıkar',
                ),
              )
              .onPressed!();
        } else if (screen == 'consent') {
          await tester.enterText(find.byType(TextField), 'Merhaba');
          tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
            'Merhaba',
          );
        } else {
          tester
              .widget<ListTile>(
                find.ancestor(
                  of: find.text('Hesabımı sil'),
                  matching: find.byType(ListTile),
                ),
              )
              .onTap!();
        }
        await advance(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        if (screen == 'consent' && confirm) {
          await tester.ensureVisible(
            find.byKey(const Key('ugc-consent-checkbox')),
          );
          await tester.tap(find.byKey(const Key('ugc-consent-checkbox')));
          await advance(tester);
        }
        final cancelLabel =
            screen == 'delete'
                ? 'Vazgeç'
                : screen == 'consent'
                ? 'ŞİMDİ DEĞİL'
                : 'VAZGEÇ';
        final confirmLabel = switch (screen) {
          'friends' => 'ÇIKAR',
          'consent' => 'KABUL ET',
          _ => 'Kalıcı olarak sil',
        };
        final cancel = buttonAction(tester, cancelLabel);
        final action = confirm ? buttonAction(tester, confirmLabel) : cancel;
        final navigator = Navigator.of(
          tester.element(find.byType(AlertDialog)),
        );
        final before = requests.length;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('confirmation-cover')),
          ),
        );
        await advance(tester);
        action();
        await advance(tester);
        expect(find.text('confirmation-cover'), findsOneWidget);
        expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
        expect(requests.length, before);
        navigator.pop();
        await advance(tester);
        cancel();
        cancel();
        await advance(tester);
        expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
        expect(requests.length, before);
        expect(action, returnsNormally);
        await tester.pumpWidget(const SizedBox());
        expect(action, returnsNormally);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
