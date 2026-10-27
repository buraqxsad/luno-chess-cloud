import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  setupPracticeTestAssets();
  for (final ranked in [false, true]) {
    final name = ranked ? 'ranked queue' : 'friendly room';
    test('$name is account-scoped', () {
      expect(
        ranked ? const OnlineHubScreen() : const FriendlyOnlineScreen(),
        isA<LunoAccountScopedPage>(),
      );
    });
    for (final change in ['none', 'account', 'signout']) {
      testWidgets('$name exit cleanup respects $change ownership', (
        tester,
      ) async {
        final auth = TestAuth();
        final paths = <String>[];
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          appCheck: () async => 'check',
          client: MockClient((request) async {
            paths.add(request.url.path.split('/').last);
            return http.Response(
              jsonEncode({
                'ok': true,
                'status': 'queued',
                if (!ranked) 'roomCode': 'ABC123',
              }),
              200,
            );
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        await tester.pumpWidget(
          shell(
            ranked
                ? OnlineHubScreen(online: online)
                : FriendlyOnlineScreen(online: online),
          ),
        );
        final button = find.byWidgetPredicate(
          (w) =>
              w is LunoButton &&
              w.label.startsWith(
                ranked ? 'EŞLEŞMEYİ BAŞLAT' : 'ODA KODU OLUŞTUR',
              ),
        );
        tester.widget<LunoButton>(button).onPressed!();
        await tester.pump();
        await tester.pump();
        expect(
          paths,
          contains(ranked ? 'enqueueBattleV1' : 'createBattleV1Room'),
        );
        if (change == 'account') auth.currentUser = TestUser('second');
        if (change == 'signout') auth.currentUser = null;
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pump();
        expect(
          paths.where((p) => p.startsWith('cancelBattleV1')).length,
          change == 'none' ? 1 : 0,
          reason:
              'an old route must never cancel the next account queue or room',
        );
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$name does not dispatch after bootstrap changes owner', (
      tester,
    ) async {
      final auth = TestAuth();
      final pending = Completer<void>();
      final paths = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () => pending.future,
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            '{"ok":true,"status":"queued","roomCode":"ABC123"}',
            200,
          );
        }),
      );
      addTearDown(online.dispose);
      if (ranked) online.ready = true;
      await tester.pumpWidget(
        shell(
          ranked
              ? OnlineHubScreen(online: online)
              : FriendlyOnlineScreen(online: online),
        ),
      );
      final button = find.byWidgetPredicate(
        (w) =>
            w is LunoButton &&
            w.label.startsWith(
              ranked ? 'EŞLEŞMEYİ BAŞLAT' : 'ODA KODU OLUŞTUR',
            ),
      );
      online.ready = false;
      tester.widget<LunoButton>(button).onPressed!();
      await tester.pump();
      auth.currentUser = TestUser('second');
      pending.complete();
      await tester.pump();
      await tester.pump();
      expect(paths, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  for (final switched in [false, true]) {
    testWidgets('late queued response cleanup keeps original owner $switched', (
      tester,
    ) async {
      final auth = TestAuth();
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
      );
      addTearDown(online.dispose);
      final pending = Completer<Map<String, dynamic>>();
      final paths = <String>[];
      await tester.pumpWidget(
        shell(
          OnlineHubScreen(
            online: online,
            onlineOverride: true,
            requestOverride: (path, body) async {
              paths.add(path);
              return path == '/enqueueRanked' ? pending.future : {'ok': true};
            },
          ),
        ),
      );
      tester
          .widget<LunoButton>(
            find.byWidgetPredicate(
              (w) => w is LunoButton && w.label == 'EŞLEŞMEYİ BAŞLAT',
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(paths, ['/enqueueRanked']);
      if (switched) auth.currentUser = TestUser('second');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final cleanupBeforeReply =
          paths.where((p) => p == '/cancelRankedQueue').length;
      pending.complete({'ok': true, 'status': 'queued'});
      await tester.pump();
      await tester.pump();
      expect(cleanupBeforeReply, switched ? 0 : 1);
      expect(
        paths.where((p) => p == '/cancelRankedQueue').length,
        switched ? 0 : 2,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
