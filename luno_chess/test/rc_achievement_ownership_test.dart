import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth;

Map<String, dynamic> achievementState({int gold = 700, bool claimed = false}) =>
    {
      'gold': gold,
      'gems': 20,
      'rewards': {
        'achievements': [
          {
            'id': 'first_win',
            'title': 'İlk Zafer',
            'description': 'İlk maçını kazan.',
            'target': 1,
            'progress': 1,
            'statKey': 'wins',
            'claimed': claimed,
            'reward': {'gold': 100},
          },
        ],
      },
    };

http.Response payload(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Finder iconAction(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

void main() {
  setupPracticeTestAssets();
  test('achievements opt into account-scoped navigation', () {
    expect(const AchievementsScreen(), isA<LunoAccountScopedPage>());
  });
  for (final scenario in [
    'store-switch',
    'disposed',
    'malformed',
    'duplicate',
    'timeout',
  ]) {
    testWidgets('achievement load owns its result: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.createForTesting();
      await store.bindAccount('first');
      final pending = Completer<http.Response>();
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        appCheck: () async => 'test-only',
        databaseRead: (_) async => {},
        client: MockClient((request) {
          requests++;
          if (scenario == 'duplicate' && requests == 1) {
            return Future.value(
              payload({'ok': true, 'state': achievementState()}),
            );
          }
          return pending.future;
        }),
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await online.start();
      await tester.pumpWidget(
        shell(AchievementsScreen(online: online, playerStore: store)),
      );
      await tester.pump();
      expect(requests, 1);
      if (scenario == 'store-switch') {
        await store.bindAccount('second');
      } else if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      } else if (scenario == 'duplicate') {
        final refresh =
            tester.widget<IconButton>(iconAction('Yenile')).onPressed!;
        refresh();
        refresh();
        await tester.pump();
        expect(requests, 2);
      } else if (scenario == 'timeout') {
        await tester.pump(const Duration(seconds: 13));
        expect(find.text('Başarımlar sunucudan yüklenemedi.'), findsOneWidget);
      }
      pending.complete(
        payload({
          'ok': true,
          'state':
              scenario == 'malformed'
                  ? {'gold': 919}
                  : achievementState(gold: 919),
        }),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (scenario != 'duplicate') expect(store.data.gold, isNot(919));
      if (scenario == 'malformed' || scenario == 'timeout') {
        expect(find.text('Başarımlar sunucudan yüklenemedi.'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final scenario in ['success', 'store-switch', 'disposed', 'refresh']) {
    testWidgets('achievement claim is confirmed and refreshed: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStore.createForTesting();
      await store.bindAccount('first');
      final pending = Completer<http.Response>();
      var loads = 0;
      var claims = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        appCheck: () async => 'test-only',
        databaseRead: (_) async => {},
        client: MockClient((request) {
          if (request.url.path.endsWith('getPlayerState')) {
            loads++;
            if (loads == 1) {
              return Future.value(
                payload({'ok': true, 'state': achievementState()}),
              );
            }
            return pending.future;
          }
          claims++;
          return pending.future;
        }),
      );
      addTearDown(() {
        online.dispose();
        store.dispose();
      });
      await online.start();
      await tester.pumpWidget(
        shell(AchievementsScreen(online: online, playerStore: store)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final claim =
          tester.widget<IconButton>(iconAction('Ödülü al')).onPressed!;
      if (scenario == 'refresh') {
        tester.widget<IconButton>(iconAction('Yenile')).onPressed!();
        await tester.pump();
      }
      claim();
      claim();
      await tester.pump();
      expect(claims, scenario == 'refresh' ? 0 : 1);
      if (scenario == 'store-switch') {
        await store.bindAccount('second');
      } else if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      }
      pending.complete(
        payload({
          'ok': true,
          'granted': true,
          'reward': {'gold': 100},
          'state': achievementState(gold: 919, claimed: true),
        }),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (scenario == 'success') {
        expect(store.data.gold, 919);
        expect(find.byTooltip('Ödülü al'), findsNothing);
        final dynamic state = tester.state(find.byType(AchievementsScreen));
        expect(state.serverAchievements.single['claimed'], true);
      } else if (scenario != 'refresh') {
        expect(store.data.gold, isNot(919));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
