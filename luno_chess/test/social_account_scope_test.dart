import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/navigation/luno_route.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  testWidgets(
    'covered social route discards old state and rebuilds only on return',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final service = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        authChanges: events.stream,
        databaseRead: (_) async => {},
        friendRequestStream: const Stream.empty(),
        matchInviteStream: const Stream.empty(),
      );
      final navigator = GlobalKey<NavigatorState>();
      await service.start();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: LunoAccountScope(
            service: service,
            page: FriendsScreen(online: service),
          ),
        ),
      );
      await tester.pump();
      final old = tester.state(find.byType(FriendsScreen));
      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      );
      unawaited(navigator.currentState!.push(coveringRoute));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      auth.currentUser = TestUser('second');
      events.add(auth.currentUser);
      await tester.pump();
      await tester.pump();
      expect(old.mounted, isFalse);
      expect(find.byType(FriendsScreen, skipOffstage: false), findsNothing);
      navigator.currentState!.pop();
      // Network-backed screens may keep a loading animation running in a
      // widget test; advance the route transition without waiting for idle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FriendsScreen), findsOneWidget);
      expect(identical(old, tester.state(find.byType(FriendsScreen))), isFalse);
      final same = tester.state(find.byType(FriendsScreen));
      events.add(auth.currentUser);
      await service.retry();
      await tester.pump();
      expect(identical(same, tester.state(find.byType(FriendsScreen))), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      await events.close();
      expect(tester.takeException(), isNull);
    },
  );

  for (final page in <Widget>[
    const FriendsScreen(),
    const InboxScreen(),
    const DirectMessageScreen(targetUid: 'other', targetName: 'Other'),
  ]) {
    testWidgets(
      '${page.runtimeType} discards old state and draft on account change',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final auth = TestAuth();
        final events = StreamController<User?>.broadcast(sync: true);
        final service = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          authChanges: events.stream,
          databaseRead: (_) async => {},
          friendRequestStream: const Stream.empty(),
          matchInviteStream: const Stream.empty(),
        );
        await service.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: LunoAccountScope(
              service: service,
              page:
                  page is FriendsScreen
                      ? FriendsScreen(online: service)
                      : page is InboxScreen
                      ? InboxScreen(online: service)
                      : page is DirectMessageScreen
                      ? DirectMessageScreen(
                        targetUid: page.targetUid,
                        targetName: page.targetName,
                        online: service,
                      )
                      : page,
            ),
          ),
        );
        await tester.pump();
        final dynamic old = tester.state(find.byType(page.runtimeType));
        if (page is FriendsScreen) {
          old.controller.text = 'private search';
          old.friendRows = <Map<String, dynamic>>[
            {'uid': 'old', 'name': 'Old friend'},
          ];
        }
        if (page is DirectMessageScreen) old.input.text = 'private draft';
        auth.currentUser = TestUser('second');
        events.add(auth.currentUser);
        await tester.pump();
        await tester.pump();
        final dynamic fresh = tester.state(find.byType(page.runtimeType));
        expect(identical(old, fresh), isFalse);
        expect(old.mounted, isFalse);
        if (page is FriendsScreen) {
          expect(fresh.controller.text, isEmpty);
          expect(fresh.friendRows, isEmpty);
        }
        if (page is DirectMessageScreen) expect(fresh.input.text, isEmpty);
        auth.currentUser = null;
        events.add(null);
        await tester.pump();
        expect(find.byType(page.runtimeType), findsNothing);
        expect(find.textContaining('Oturumun kapandı'), findsOneWidget);
        expect(fresh.mounted, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
        await events.close();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('production routes opt in only account-owned social pages', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    for (final page in <Widget>[
      const FriendsScreen(),
      const InboxScreen(),
      const DirectMessageScreen(targetUid: 'other', targetName: 'Other'),
      const SizedBox(),
    ]) {
      final route = lunoRoute(page) as PageRouteBuilder;
      final built = route.pageBuilder(
        context,
        kAlwaysCompleteAnimation,
        kAlwaysDismissedAnimation,
      );
      expect(built is LunoAccountScope, page is LunoAccountScopedPage);
      route.dispose();
    }
  });
}
