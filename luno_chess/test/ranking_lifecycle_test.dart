import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

http.Response result(String mode, String name) => http.Response(
  jsonEncode({
    'ok': true,
    'mode': mode,
    'results': [
      {
        'uid': name,
        'username': name,
        'trophies': 100,
        'collectionScore': 200,
        'seasonScore': 300,
        'wins': 7,
        'gamesPlayed': 2,
        'bio': 'Selected player biography',
        'country': 'GB',
      },
    ],
  }),
  200,
);

void main() {
  for (final scenario in [
    'mode',
    'account',
    'loaded-account',
    'covered-account',
    'offline',
    'error',
    'profile',
    'invalid-profile',
    'stale-profile',
    'account-profile',
    'disposed',
  ]) {
    testWidgets('ranking lifecycle guards $scenario', (tester) async {
      final auth = TestAuth();
      final pending = <Completer<http.Response>>[];
      final modes = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        databaseRead: (path) async {
          expect(path, 'publicProfiles/SelectedPlayer');
          return {
            'username': 'selectedplayer',
            'bio': 'Selected player biography',
            'country': 'GB',
            'wins': scenario == 'invalid-profile' ? double.nan : 7,
            'gamesPlayed': scenario == 'invalid-profile' ? double.infinity : 2,
          };
        },
        client: MockClient((request) {
          modes.add((jsonDecode(request.body) as Map)['mode'] as String);
          final response = Completer<http.Response>();
          pending.add(response);
          return response.future;
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: RankingScreen(online: online),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(pending, hasLength(1));
      expect(find.text('KOLEKSİYON'), findsNothing);
      expect(find.text('KOLEKSİYON SIRALAMASI'), findsNothing);
      if (scenario == 'mode') {
        await tester.tap(find.text('SEZON'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(modes, ['trophies', 'season']);
        pending[1].complete(result('season', 'NewSeason'));
        await tester.pumpAndSettle();
        pending[0].complete(result('trophies', 'OldTrophies'));
        await tester.pumpAndSettle();
        expect(find.text('newseason'), findsWidgets);
        expect(find.text('oldtrophies'), findsNothing);
      } else if (scenario == 'account') {
        auth.currentUser = TestUser('second');
        online.notifyListeners();
        await tester.pump(const Duration(milliseconds: 200));
        expect(pending, hasLength(2));
        pending[1].complete(result('trophies', 'NewAccount'));
        await tester.pumpAndSettle();
        pending[0].complete(result('trophies', 'OldAccount'));
        await tester.pumpAndSettle();
        expect(find.text('newaccount'), findsWidgets);
        expect(find.text('oldaccount'), findsNothing);
      } else if (scenario == 'loaded-account' ||
          scenario == 'covered-account') {
        pending[0].complete(result('trophies', 'OldAccount'));
        await tester.pumpAndSettle();
        expect(find.text('oldaccount'), findsWidgets);
        if (scenario == 'covered-account') {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other screen')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        auth.currentUser = TestUser('second');
        online.notifyListeners();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('oldaccount', skipOffstage: false), findsNothing);
        if (scenario == 'covered-account') {
          expect(pending, hasLength(1));
          expect(find.text('Other screen'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          await tester.tap(find.text('TEKRAR DENE'));
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(pending, hasLength(2));
        pending[1].complete(result('trophies', 'NewAccount'));
        await tester.pumpAndSettle();
        expect(find.text('newaccount'), findsWidgets);
      } else if (scenario == 'disposed') {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        pending[0].complete(result('trophies', 'Disposed'));
        await tester.pumpAndSettle();
      } else if (scenario == 'error') {
        pending[0].complete(http.Response('{"ok":false}', 200));
        await tester.pumpAndSettle();
        online.notifyListeners();
        await tester.pump(const Duration(milliseconds: 200));
        expect(pending, hasLength(1));
        await tester.tap(find.text('TEKRAR DENE'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(pending, hasLength(2));
        pending[1].complete(result('trophies', 'Retried'));
        await tester.pumpAndSettle();
        expect(find.text('retried'), findsWidgets);
      } else {
        pending[0].complete(result('trophies', 'SelectedPlayer'));
        await tester.pumpAndSettle();
        if (scenario == 'offline') {
          online.ready = false;
          online.notifyListeners();
          await tester.tap(find.text('SEZON'));
          await tester.pumpAndSettle();
          final dynamic state = tester.state(find.byType(RankingScreen));
          expect(state.rows, isEmpty);
          expect(find.text('selectedplayer'), findsNothing);
          online.ready = true;
          online.notifyListeners();
          await tester.pump(const Duration(milliseconds: 200));
          expect(modes, ['trophies', 'season']);
          pending[1].complete(result('season', 'ConnectedAgain'));
          await tester.pumpAndSettle();
          expect(find.text('connectedagain'), findsWidgets);
        } else if (scenario == 'stale-profile' ||
            scenario == 'account-profile') {
          final tile =
              find
                  .ancestor(
                    of: find.text('selectedplayer').first,
                    matching: find.byType(InkWell),
                  )
                  .first;
          final callback = tester.widget<InkWell>(tile).onTap!;
          if (scenario == 'account-profile') {
            auth.currentUser = TestUser('second');
          } else {
            final dynamic state = tester.state(find.byType(RankingScreen));
            state.setState(() => state.rows = <Map<String, dynamic>>[]);
          }
          callback();
          await tester.pumpAndSettle();
          expect(find.byType(PlayerDetailsScreen), findsNothing);
        } else {
          if (scenario == 'invalid-profile') {
            final dynamic state = tester.state(find.byType(RankingScreen));
            state.rows.first['wins'] = double.nan;
            state.rows.first['gamesPlayed'] = double.infinity;
          }
          await tester.tap(find.text('selectedplayer').first);
          await tester.pumpAndSettle();
          final profile = tester.widget<PlayerDetailsScreen>(
            find.byType(PlayerDetailsScreen),
          );
          expect(profile.name, 'selectedplayer');
          expect(find.textContaining('KOLEKSİYON PUANI'), findsNothing);
          expect(find.textContaining('COLLECTION SCORE'), findsNothing);
          expect(profile.bio, 'Selected player biography');
          expect(profile.country, 'GB');
          expect(profile.wins, scenario == 'invalid-profile' ? 0 : 7);
          expect(profile.games, scenario == 'invalid-profile' ? 0 : 7);
          expect(
            find.text(scenario == 'invalid-profile' ? '0%' : '100%'),
            findsOneWidget,
          );
        }
      }
      expect(modes, isNot(contains('collection')));
      expect(tester.takeException(), isNull);
    });
  }
}
