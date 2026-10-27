import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final kind in ['mission', 'tier', 'end']) {
    for (final scenario in [
      'success',
      'before',
      'during',
      'covered',
      'malformed',
    ]) {
      testWidgets('$kind reward preserves $scenario account boundary', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        final auth = TestAuth();
        final response = Completer<http.Response>();
        var claims = 0;
        Map<String, dynamic> snapshot() => {
          'season': {
            'status': kind == 'end' ? 'ended' : 'active',
            'seasonNumber': 1,
            'path': [
              {
                'id': 'tier1',
                'title': 'First reward',
                'state': claims > 0 ? 'claimed' : 'claimable',
                'canClaim': claims == 0,
                'minTrophies': 0,
                'reward': {'gold': 100},
              },
            ],
            'endReward': {
              'tier': 'Bronz',
              'reward': {'gold': 200},
            },
          },
          'rewards': {
            'missions': {
              'daily': [
                {
                  'id': 'd1',
                  'title': 'First mission',
                  'target': 1,
                  'progress': 1,
                  'claimed': claims > 0,
                  'reward': {'gold': 100},
                },
              ],
              'weekly': [],
              'special': [],
            },
            'periods': {},
          },
        };
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/getPlayerState')) {
              return http.Response(
                jsonEncode({'ok': true, 'state': snapshot()}),
                200,
              );
            }
            claims++;
            return response.future;
          }),
          appCheck: () async => 'check',
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
            home:
                kind == 'mission'
                    ? MissionsScreen(online: online, playerStore: store)
                    : SeasonScreen(online: online, playerStore: store),
          ),
        );
        await tester.pumpAndSettle();
        final VoidCallback callback;
        if (kind == 'end') {
          callback =
              tester
                  .widget<LunoButton>(
                    find.widgetWithText(LunoButton, 'SEZON SONU ÖDÜLÜNÜ AL'),
                  )
                  .onPressed!;
        } else {
          callback =
              tester
                  .widget<IconButton>(
                    find
                        .byWidgetPredicate(
                          (w) => w is IconButton && w.tooltip == 'Ödülü al',
                        )
                        .first,
                  )
                  .onPressed!;
        }
        if (scenario == 'before') auth.currentUser = TestUser('second');
        callback();
        callback();
        await tester.pump(const Duration(milliseconds: 200));
        if (scenario == 'before') {
          expect(claims, 0);
          expect(store.data.gold, isNot(777));
          expect(find.byType(SnackBar), findsNothing);
          return;
        }
        expect(claims, 1);
        if (scenario == 'during') auth.currentUser = TestUser('second');
        if (scenario == 'covered') {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other screen')),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
        }
        response.complete(
          http.Response(
            jsonEncode({
              'ok': true,
              'granted': scenario == 'malformed' ? 'true' : true,
              'reward': {'gold': 100},
              'state': {...snapshot(), 'gold': 777},
            }),
            200,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          store.data.gold,
          scenario == 'during' || scenario == 'malformed' ? isNot(777) : 777,
        );
        if (scenario == 'during' || scenario == 'covered') {
          expect(find.byType(SnackBar), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final mission in [false, true]) {
    testWidgets(
      'period refresh resumes after a pending ${mission ? 'mission' : 'season'} claim',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        final auth = TestAuth();
        var reads = 0;
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          client: MockClient((_) async {
            reads++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'state': {
                  'season': {
                    'status': 'active',
                    'path': [],
                    'serverTime': 1,
                    'seasonEndAt': 1,
                  },
                  'rewards': {
                    'missions': {'daily': [], 'weekly': [], 'special': []},
                    'periods': {'serverTime': 86399900},
                  },
                },
              }),
              200,
            );
          }),
          appCheck: () async => 'check',
        );
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await online.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home:
                mission
                    ? MissionsScreen(online: online, playerStore: store)
                    : SeasonScreen(online: online, playerStore: store),
          ),
        );
        await tester.pumpAndSettle();
        expect(reads, 1);
        final dynamic state = tester.state(
          find.byType(mission ? MissionsScreen : SeasonScreen),
        );
        state.setState(() => state.claiming = true);
        await tester.pump(Duration(milliseconds: mission ? 1200 : 30100));
        expect(reads, 1);
        state.setState(() => state.claiming = false);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(reads, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'late ${mission ? 'mission' : 'season'} load rejects changed account',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        final auth = TestAuth();
        final response = Completer<http.Response>();
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          client: MockClient((_) => response.future),
          appCheck: () async => 'check',
        );
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await online.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home:
                mission
                    ? MissionsScreen(online: online, playerStore: store)
                    : SeasonScreen(online: online, playerStore: store),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        auth.currentUser = TestUser('second');
        response.complete(
          http.Response(
            jsonEncode({
              'ok': true,
              'state': {
                'gold': 777,
                'season': {'path': []},
                'rewards': {
                  'missions': {'daily': [], 'weekly': [], 'special': []},
                },
              },
            }),
            200,
          ),
        );
        await tester.pumpAndSettle();
        expect(store.data.gold, isNot(777));
        expect(
          find.text(
            mission
                ? 'Hesabın değişti. Görev ekranını yeniden aç.'
                : 'Hesabın değişti. Sezon ekranını yeniden aç.',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Ödülü al',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
