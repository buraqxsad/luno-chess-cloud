import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final action in ['add', 'accept', 'reject', 'remove', 'invite']) {
    for (final scenario in ['success', 'account', 'before', 'stale']) {
      testWidgets('friend $action owns current account and row: $scenario', (
        tester,
      ) async {
        final auth = TestAuth();
        final pending = Completer<http.Response>();
        final requests = <Map<String, dynamic>>[];
        final requestStream =
            StreamController<List<Map<String, dynamic>>>.broadcast(sync: true);
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          appCheck: () async => 'check',
          friendRequestStream: requestStream.stream,
          matchInviteStream: Stream.value(<Map<String, dynamic>>[]),
          databaseRead:
              (path) async =>
                  path.startsWith('publicProfiles/')
                      ? {'username': 'target_player', 'trophies': 20}
                      : path.startsWith('friends/')
                      ? {'target': true}
                      : {
                        'target': {'fromUsername': 'target_player'},
                      },
          client: MockClient((request) {
            requests.add({
              'path': request.url.path,
              ...Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            });
            return pending.future;
          }),
        );
        addTearDown(() async {
          online.dispose();
          await requestStream.close();
        });
        await online.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: FriendsScreen(online: online),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(FriendsScreen));
        if (action == 'add') {
          state.setState(() {
            state.searchActive = true;
            state.results = <Map<String, dynamic>>[
              {'uid': 'target', 'username': 'target_player'},
            ];
          });
        } else if (action == 'accept' || action == 'reject') {
          state.setState(() => state.tab = 1);
        }
        await tester.pumpAndSettle();
        VoidCallback callback;
        if (action == 'add') {
          callback =
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'EKLE'),
                  )
                  .onPressed!;
        } else {
          final tooltip = switch (action) {
            'accept' => 'Kabul et',
            'reject' => 'Reddet',
            'remove' => 'Arkadaşlıktan çıkar',
            _ => 'Maça davet et',
          };
          callback =
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (w) => w is IconButton && w.tooltip == tooltip,
                    ),
                  )
                  .onPressed!;
        }
        if (scenario == 'before') auth.currentUser = TestUser('second');
        if (scenario == 'stale') {
          state.setState(() {
            if (action == 'add') {
              state.results = <Map<String, dynamic>>[];
            } else if (action == 'accept' || action == 'reject') {
              state.requestRows = <Map<String, dynamic>>[];
            } else {
              state.friendRows = <Map<String, dynamic>>[];
            }
          });
        }
        callback();
        callback();
        await tester.pump(const Duration(milliseconds: 300));
        if (scenario == 'before' || scenario == 'stale') {
          expect(requests, isEmpty);
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          if (action == 'remove') {
            expect(find.byType(AlertDialog), findsOneWidget);
            await tester.tap(find.text('ÇIKAR'));
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(requests, hasLength(1));
          expect(
            requests.first[action == 'accept' || action == 'reject'
                ? 'fromUid'
                : 'targetUid'],
            'target',
          );
          if (scenario == 'account') auth.currentUser = TestUser('second');
          pending.complete(
            http.Response(
              jsonEncode(switch (action) {
                'add' => {'ok': true, 'status': 'sent'},
                'accept' => {'ok': true, 'accepted': true},
                'reject' => {'ok': true, 'accepted': false},
                'remove' => {'ok': true, 'removed': true},
                _ => {
                  'ok': true,
                  'sent': true,
                  'status': 'pending',
                  'expiresAt': 121000,
                },
              }),
              200,
            ),
          );
          await tester.pumpAndSettle();
          expect(requests, hasLength(1));
          if (scenario == 'account') {
            expect(find.byType(SnackBar), findsNothing);
            if (action == 'add') {
              expect(state.results.first['relationship'], isNull);
            }
          } else {
            if (action == 'add') {
              expect(state.results.first['relationship'], 'outgoing');
            }
            if (action == 'invite') {
              expect(
                find.text('Dostluk maçı daveti gönderildi.'),
                findsOneWidget,
              );
              expect(
                find.text('Dostluk maçı daveti gönderilemedi.'),
                findsNothing,
              );
            }
            expect(
              action == 'invite' ? state.inviteBusy : state.friendBusy,
              isEmpty,
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'new live requests beat delayed initial snapshot and handle stream error',
    (tester) async {
      final initial = Completer<Object?>();
      final stream = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        friendRequestStream: stream.stream,
        matchInviteStream: Stream.value(<Map<String, dynamic>>[]),
        databaseRead:
            (path) =>
                path.startsWith('friendRequests/')
                    ? initial.future
                    : Future.value({}),
      );
      addTearDown(() async {
        online.dispose();
        await stream.close();
      });
      await online.start();
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: FriendsScreen(online: online)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      stream.add([
        {'fromUid': 'new', 'fromUsername': 'new_player'},
      ]);
      await tester.pump();
      initial.complete({
        'old': {'fromUsername': 'old_player'},
      });
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(FriendsScreen));
      expect(state.requestRows.single['fromUid'], 'new');
      stream.addError(StateError('fixture stream error'));
      await tester.pumpAndSettle();
      expect(
        find.text('Arkadaşlık istekleri şu an yenilenemedi.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final accept in [false, true]) {
    for (final scenario in ['before', 'account', if (!accept) 'success']) {
      testWidgets('incoming match invite accept=$accept guards $scenario', (
        tester,
      ) async {
        final auth = TestAuth();
        final pending = Completer<http.Response>();
        var requests = 0;
        Map<dynamic, dynamic>? sentBody;
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          appCheck: () async => 'check',
          friendRequestStream: Stream.value(<Map<String, dynamic>>[]),
          matchInviteStream: Stream.value(<Map<String, dynamic>>[
            {'fromUid': 'target', 'fromUsername': 'target_player'},
          ]),
          databaseRead: (_) async => {},
          client: MockClient((request) {
            requests++;
            sentBody = jsonDecode(request.body) as Map;
            return pending.future;
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: FriendsScreen(online: online),
          ),
        );
        await tester.pumpAndSettle();
        final tooltip = accept ? 'Kabul et' : 'Reddet';
        final callback =
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == tooltip,
                  ),
                )
                .onPressed!;
        if (scenario == 'before') auth.currentUser = TestUser('second');
        callback();
        callback();
        await tester.pump(const Duration(milliseconds: 200));
        if (scenario == 'before') {
          expect(requests, 0);
        } else {
          expect(requests, 1);
          expect(sentBody?['fromUid'], 'target');
          expect(sentBody?['accept'], accept);
          if (scenario == 'account') auth.currentUser = TestUser('second');
          pending.complete(
            http.Response(
              jsonEncode({
                'ok': true,
                'accepted': accept,
                if (accept) 'matchId': 'match_1',
                if (accept) 'view': {'matchId': 'match_1'},
              }),
              200,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(OnlineMatchScreen), findsNothing);
          final notices =
              tester
                  .widgetList<Text>(
                    find.descendant(
                      of: find.byType(SnackBar),
                      matching: find.byType(Text),
                    ),
                  )
                  .map((text) => text.data)
                  .toList();
          if (scenario == 'account') {
            expect(find.byType(SnackBar), findsNothing, reason: '$notices');
          } else {
            expect(
              find.text('Davet reddedildi.'),
              findsOneWidget,
              reason: '$notices',
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'friend removal confirmation closes before dispatch on account change',
    (tester) async {
      final auth = TestAuth();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        friendRequestStream: Stream.value(<Map<String, dynamic>>[]),
        matchInviteStream: Stream.value(<Map<String, dynamic>>[]),
        databaseRead:
            (path) async =>
                path.startsWith('publicProfiles/')
                    ? {'username': 'target_player'}
                    : path.startsWith('friends/')
                    ? {'target': true}
                    : {},
        client: MockClient((_) async {
          requests++;
          return http.Response('{"ok":true,"removed":true}', 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: FriendsScreen(online: online)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Arkadaşlıktan çıkar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      auth.currentUser = TestUser('second');
      online.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
