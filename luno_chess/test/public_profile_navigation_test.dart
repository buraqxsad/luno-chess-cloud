import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  test(
    'public profile mapping preserves premium, bio and normalized country',
    () {
      final profile = PlayerDetailsScreen.fromPlayer({
        'username': ' PLAYER ',
        'country': ' gb ',
        'bio': ' Biography ',
        'isPremium': true,
        'trophies': 20,
        'wins': 7,
        'gamesPlayed': 2,
      });
      expect(profile.name, 'player');
      expect(profile.country, 'GB');
      expect(profile.bio, 'Biography');
      expect(profile.premium, true);
      expect(profile.wins, 7);
      expect(profile, isA<LunoAccountScopedPage>());
    },
  );
  test('legacy premium flag is supported without truthy coercion', () {
    expect(PlayerDetailsScreen.fromPlayer({'premium': true}).premium, true);
    expect(
      PlayerDetailsScreen.fromPlayer({'isPremium': 'true'}).premium,
      false,
    );
  });
  test(
    'malformed numeric and text fields do not crash public profile mapping',
    () {
      final profile = PlayerDetailsScreen.fromPlayer({
        'trophies': double.infinity,
        'wins': -3,
        'gamesPlayed': double.nan,
        'country': 42,
        'bio': {'private': 'object'},
      });
      expect(profile.trophies, 0);
      expect(profile.wins, 0);
      expect(profile.games, 0);
      expect(profile.country, 'TR');
      expect(profile.bio, '');
    },
  );
  for (final source in ['search', 'friend', 'friend-rank']) {
    for (final scenario in [
      'success',
      'account',
      'stale',
      'invalid',
      'requests-tab',
    ]) {
      testWidgets('$source profile navigation guards $scenario', (
        tester,
      ) async {
        final auth = TestAuth();
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          databaseRead:
              (path) async =>
                  path == 'publicProfiles/target'
                      ? {
                        'username': 'target_player',
                        'country': 'GB',
                        'bio': 'Profile biography',
                        'isPremium': true,
                      }
                      : {},
          friendRequestStream: Stream.value(<Map<String, dynamic>>[]),
          matchInviteStream:
              Stream.value(<Map<String, dynamic>>[]).asBroadcastStream(),
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
        final dynamic state = tester.state(find.byType(FriendsScreen));
        final row = <String, dynamic>{
          'uid': scenario == 'invalid' ? 42 : 'target',
          'username': 'target_player',
          'country': 'GB',
          'bio': 'Profile biography',
          'isPremium': true,
          'relationship': 'friends',
          'trophies': 200,
        };
        state.setState(() {
          state.socialLoading = false;
          state.searchActive = source == 'search';
          state.results = source == 'search' ? [row] : <Map<String, dynamic>>[];
          state.friendRows =
              source == 'search' ? <Map<String, dynamic>>[] : [row];
          state.tab = source == 'friend-rank' ? 2 : 0;
        });
        await tester.pumpAndSettle();
        final name = find.text('target_player');
        final tile =
            find.ancestor(of: name, matching: find.byType(InkWell)).first;
        final callback = tester.widget<InkWell>(tile).onTap!;
        if (scenario == 'account') auth.currentUser = TestUser('second');
        if (scenario == 'requests-tab') state.setState(() => state.tab = 1);
        if (scenario == 'stale') {
          state.setState(() {
            state.results = <Map<String, dynamic>>[];
            state.friendRows = <Map<String, dynamic>>[];
          });
        }
        callback();
        await tester.pumpAndSettle();
        if (scenario == 'success') {
          expect(find.byType(PlayerDetailsScreen), findsOneWidget);
          expect(find.text('Profile biography'), findsOneWidget);
          expect(find.textContaining('LUNO PREMIUM'), findsOneWidget);
        } else {
          expect(find.byType(PlayerDetailsScreen), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final covered in [false, true]) {
    testWidgets('public profile signout clears covered=$covered', (
      tester,
    ) async {
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        authChanges: events.stream,
      );
      addTearDown(() async {
        online.dispose();
        await events.close();
      });
      await online.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: LunoAccountScope(
            service: online,
            page: PlayerDetailsScreen.fromPlayer({
              'username': 'target_player',
              'bio': 'Old biography',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (covered) {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      auth.currentUser = null;
      events.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Old biography', skipOffstage: false), findsNothing);
      expect(
        find.byType(PlayerDetailsScreen, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
