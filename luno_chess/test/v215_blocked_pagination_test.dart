import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/blocked_players_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v215_privacy_legal_ui_test.dart' show fonts, capture;

String cursor(
  String after, {
  String uid = 'first',
  String scope = 'blocked-users',
}) => base64Url
    .encode(
      utf8.encode(
        jsonEncode({'v': 1, 'scope': scope, 'uid': uid, 'after': after}),
      ),
    )
    .replaceAll('=', '');
Map<String, Object> row(int index) => {
  'uid': 'target_${index.toString().padLeft(3, '0')}',
  'name': 'Player $index',
  'username': 'player_$index',
};
http.Response reply(List<Map<String, Object>> rows, {String? next}) =>
    http.Response(
      jsonEncode({'ok': true, 'results': rows, 'nextPageToken': next}),
      200,
    );

Widget app(LunoOnlineService online, {GlobalKey<NavigatorState>? navigator}) =>
    RepaintBoundary(
      key: const Key('capture'),
      child: MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: LunoTheme.dark,
        supportedLocales: LunoLocalizations.supportedLocales,
        localizationsDelegates: const [
          LunoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
        home: BlockedPlayersScreen(online: online),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  LunoOnlineService service(
    Future<http.Response> Function(http.Request) request, {
    TestAuth? auth,
  }) {
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth ?? TestAuth(),
      appCheck: () async => 'check',
      client: MockClient(request),
    );
    addTearDown(online.dispose);
    return online;
  }

  test('typed pages validate owner-bound canonical cursors and row limits', () {
    final token = cursor('target_025');
    expect(BlockedPlayersPage.cursorKey(token, 'first'), 'target_025');
    final page = BlockedPlayersPage.fromResponse({
      'ok': true,
      'results': [row(1)],
      'nextPageToken': token,
    }, ownerUid: 'first');
    expect(page.players.single.uid, 'target_001');
    expect(page.nextPageToken, token);
    for (final malformed in [
      cursor('target_025', uid: 'second'),
      cursor('target_025', scope: 'friends'),
      cursor('../private'),
      '$token=',
      'a' * 513,
      base64Url.encode(utf8.encode('not-json')).replaceAll('=', ''),
    ]) {
      expect(
        () => BlockedPlayersPage.cursorKey(malformed, 'first'),
        throwsFormatException,
      );
    }
    expect(
      () => BlockedPlayersPage.fromResponse({
        'ok': true,
        'results': [for (var i = 1; i <= 26; i++) row(i)],
      }, ownerUid: 'first'),
      throwsFormatException,
    );
  });

  test(
    'typed fallback remains removable without publishing target identity',
    () {
      final page = BlockedPlayersPage.fromResponse({
        'ok': true,
        'results': [
          {
            'uid': 'target_deleted',
            'name': 'Silinmiş oyuncu',
            'username': '',
            'unavailable': true,
          },
        ],
        'nextPageToken': null,
      }, ownerUid: 'first');
      expect(page.unavailableUids, {'target_deleted'});
      expect(page.players.single.uid, 'target_deleted');
    },
  );

  test(
    'client preserves server numeric-key ordering rather than inventing lexicographic order',
    () {
      final page = BlockedPlayersPage.fromResponse({
        'ok': true,
        'results': [
          {'uid': '200000', 'username': 'numeric_first'},
          {'uid': '1000000', 'username': 'numeric_second'},
        ],
        'nextPageToken': null,
      }, ownerUid: 'first');
      expect(page.players.map((player) => player.uid), ['200000', '1000000']);
    },
  );

  test(
    'compatibility list follows all five pages to the 101st block',
    () async {
      var requests = 0;
      final online = service((request) async {
        expect(request.url.path.endsWith('/listBlockedUsers'), isTrue);
        final body = jsonDecode(request.body) as Map;
        expect(body.keys.toSet(), requests == 0 ? <String>{} : {'pageToken'});
        final start = requests++ * 25 + 1;
        final end = (start + 24).clamp(1, 101);
        return reply(
          [for (var i = start; i <= end; i++) row(i)],
          next:
              end == 101
                  ? null
                  : cursor('target_${end.toString().padLeft(3, '0')}'),
        );
      });
      await online.start();
      final players = await online.blockedPlayers();
      expect(requests, 5);
      expect(players, hasLength(101));
      expect(players.last.uid, 'target_101');
      expect(players.map((player) => player.uid).toSet(), hasLength(101));
    },
  );

  test('filtered empty page is not mistaken for end of list', () async {
    var requests = 0;
    final online = service(
      (_) async =>
          ++requests == 1
              ? reply([], next: cursor('target_025'))
              : reply([row(26)]),
    );
    await online.start();
    expect((await online.blockedPlayers()).single.uid, 'target_026');
    expect(requests, 2);
  });

  test('foreign request cursor is rejected before HTTP dispatch', () async {
    var requests = 0;
    final online = service((_) async {
      requests++;
      return reply([]);
    });
    await online.start();
    await expectLater(
      online.blockedPlayersPage(pageToken: cursor('target_025', uid: 'second')),
      throwsFormatException,
    );
    expect(requests, 0);
  });

  for (final malformed in ['duplicate', 'repeated', 'foreign']) {
    test(
      'client rejects $malformed continuation without returning a partial list',
      () async {
        var requests = 0;
        final first = cursor('target_001');
        final online = service((_) async {
          if (++requests == 1) return reply([row(1)], next: first);
          return malformed == 'duplicate'
              ? reply([row(1)])
              : reply(
                [],
                next:
                    malformed == 'repeated'
                        ? first
                        : cursor('target_025', uid: 'second'),
              );
        });
        await online.start();
        await expectLater(online.blockedPlayers(), throwsFormatException);
        expect(requests, 2);
      },
    );
  }

  test(
    'response from a departed account is never returned as its new owner page',
    () async {
      final auth = TestAuth(),
          pending = Completer<http.Response>(),
          entered = Completer<void>();
      final online = service((_) {
        entered.complete();
        return pending.future;
      }, auth: auth);
      await online.start();
      final loading = online.blockedPlayersPage();
      await entered.future;
      auth.currentUser = TestUser('second');
      final assertion = expectLater(
        loading,
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'session-changed',
          ),
        ),
      );
      pending.complete(reply([row(1)]));
      await assertion;
    },
  );

  for (final width in [320.0, 768.0]) {
    testWidgets(
      'paged block list retains rows during failure and retry at $width',
      (tester) async {
        await fonts(tester);
        tester.view.physicalSize = Size(width, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0;
        final pending = Completer<http.Response>();
        final online = service((_) async {
          requests++;
          if (requests == 1) return reply([row(1)], next: cursor('target_001'));
          if (requests == 2) return pending.future;
          return reply([row(2)]);
        });
        await online.start();
        await tester.pumpWidget(app(online));
        await tester.pumpAndSettle();
        expect(find.text('player_1'), findsOneWidget);
        final loadMore = find.byKey(const Key('blocked-list-load-more'));
        await tester.ensureVisible(loadMore);
        final callback = tester.widget<FilledButton>(loadMore).onPressed!;
        callback();
        callback();
        await tester.pump();
        expect(requests, 2);
        expect(find.text('player_1'), findsOneWidget);
        pending.complete(
          http.Response('{"ok":true,"results":"malformed"}', 200),
        );
        await tester.pumpAndSettle();
        expect(find.text('player_1'), findsOneWidget);
        expect(find.text('More players could not be loaded.'), findsOneWidget);
        await capture(
          tester,
          'blocked-pagination-retry-en-${width.toInt()}-150',
        );
        await tester.tap(loadMore);
        await tester.pumpAndSettle();
        expect(find.text('player_1'), findsOneWidget);
        expect(find.text('player_2'), findsOneWidget);
        expect(loadMore, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'filtered page exposes continuation instead of false empty completion',
    (tester) async {
      var requests = 0;
      final online = service(
        (_) async =>
            ++requests == 1
                ? reply([], next: cursor('target_025'))
                : reply([row(26)]),
      );
      await online.start();
      await tester.pumpWidget(app(online));
      await tester.pumpAndSettle();
      expect(find.text('There are more blocked entries.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('blocked-list-load-more')));
      await tester.pumpAndSettle();
      expect(find.text('player_26'), findsOneWidget);
      expect(requests, 2);
    },
  );

  for (final stale in ['covered', 'account', 'disposed']) {
    testWidgets('retained load-more callback cannot fetch when $stale', (
      tester,
    ) async {
      var requests = 0;
      final auth = TestAuth();
      final online = service((_) async {
        requests++;
        return reply([row(1)], next: cursor('target_001'));
      }, auth: auth);
      await online.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(online, navigator: navigator));
      await tester.pumpAndSettle();
      final callback =
          tester
              .widget<FilledButton>(
                find.byKey(const Key('blocked-list-load-more')),
              )
              .onPressed!;
      if (stale == 'covered') {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          ),
        );
      } else if (stale == 'account') {
        auth.currentUser = TestUser('second');
        online.notifyListeners();
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(requests, 1);
      if (stale == 'covered') expect(find.text('Cover'), findsOneWidget);
      if (stale == 'account') expect(find.text('player_1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
