import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final blocked in ['friends', 'requests']) {
    testWidgets(
      'social $blocked timeout permits retry without stale overwrite',
      (tester) async {
        final pending = Completer<Object?>();
        final stream = StreamController<List<Map<String, dynamic>>>.broadcast(
          sync: true,
        );
        var friendReads = 0, requestReads = 0;
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: TestAuth(),
          friendRequestStream: stream.stream,
          matchInviteStream:
              Stream.value(<Map<String, dynamic>>[]).asBroadcastStream(),
          databaseRead: (path) async {
            if (path.startsWith('friends/')) {
              friendReads++;
              if (blocked == 'friends' && friendReads == 1) {
                return pending.future;
              }
              return {'new_friend': true};
            }
            if (path.startsWith('friendRequests/')) {
              requestReads++;
              if (blocked == 'requests' && requestReads == 1) {
                return pending.future;
              }
              return <String, dynamic>{};
            }
            return {
              'username':
                  path.endsWith('old_friend') ? 'old_player' : 'new_player',
            };
          },
        );
        addTearDown(() async {
          online.dispose();
          await stream.close();
        });
        await online.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: FriendsScreen(online: online),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(
          FriendsScreen.socialLoadTimeout + const Duration(milliseconds: 50),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final dynamic state = tester.state(find.byType(FriendsScreen));
        expect(state.socialLoading, false);
        expect(state.friendRows, isEmpty);
        expect(find.text('Sosyal bilgiler yüklenemedi.'), findsOneWidget);
        expect(
          find.text('Henüz arkadaşın yok. Kullanıcı adıyla ara.'),
          findsNothing,
        );
        await tester.tap(find.text('TEKRAR DENE'));
        await tester.pumpAndSettle();
        expect(find.text('new_player'), findsOneWidget);
        pending.complete(
          blocked == 'friends'
              ? {'old_friend': true}
              : {
                'old_friend': {'fromUsername': 'old_player'},
              },
        );
        await tester.pumpAndSettle();
        expect(state.friendRows.single['username'], 'new_player');
        expect(state.requestRows, isEmpty);
        expect(find.text('old_player'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final departure in ['account', 'disposed', 'covered']) {
    testWidgets('social timeout does not notify after $departure', (
      tester,
    ) async {
      final auth = TestAuth();
      final pending = Completer<Object?>();
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        friendRequestStream: const Stream.empty(),
        matchInviteStream: const Stream.empty(),
        databaseRead: (_) => pending.future,
      );
      addTearDown(online.dispose);
      await online.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: FriendsScreen(online: online),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (departure == 'account') auth.currentUser = TestUser('second');
      if (departure == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      if (departure == 'covered') {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pump(
        FriendsScreen.socialLoadTimeout + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsNothing);
      pending.complete({});
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'live requests survive friends failure and repeated stream does not notify twice',
    (tester) async {
      final stream = StreamController<List<Map<String, dynamic>>>.broadcast(
        sync: true,
      );
      final pending = Completer<Object?>();
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        friendRequestStream: stream.stream,
        matchInviteStream: const Stream.empty(),
        databaseRead:
            (path) =>
                path.startsWith('friends/') ? pending.future : Future.value({}),
      );
      addTearDown(() async {
        online.dispose();
        await stream.close();
      });
      await online.start();
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: FriendsScreen(online: online)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      stream.add([]);
      await tester.pump();
      final requests = <Map<String, dynamic>>[
        {'fromUid': 'target', 'fromUsername': 'target_player'},
      ];
      stream.add(requests);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Yeni bir arkadaşlık isteğin var.'), findsOneWidget);
      stream.add(requests);
      await tester.pump();
      ScaffoldMessenger.of(
        tester.element(find.byType(FriendsScreen)),
      ).removeCurrentSnackBar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SnackBar), findsNothing);
      pending.completeError(StateError('friends unavailable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İSTEKLER'));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(FriendsScreen));
      expect(state.requestRows.single['fromUid'], 'target');
      expect(find.text('target_player'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
