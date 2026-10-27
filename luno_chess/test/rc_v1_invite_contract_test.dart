import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'helpers/battle_v1_response.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPracticeTestAssets();

  Future<LunoOnlineService> service(
    Map<String, dynamic> response, {
    required String path,
    bool? accept,
  }) async {
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth()..currentUser = TestUser('self'),
      appCheck: () async => 'check',
      client: MockClient((request) async {
        expect(request.url.path.endsWith(path), true);
        final body = jsonDecode(request.body) as Map;
        expect((body['client'] as Map)['protocolVersion'], battleV1Protocol);
        expect(body[accept == null ? 'targetUid' : 'fromUid'], 'other');
        if (accept != null) expect(body['accept'], accept);
        return http.Response(jsonEncode(response), 200);
      }),
    );
    addTearDown(online.dispose);
    await online.start();
    return online;
  }

  // Exact successful send shape from the current in-memory V1 backend.
  const sent = {
    'ok': true,
    'sent': true,
    'status': 'pending',
    'expiresAt': 121000,
  };
  test(
    'V1 send accepts the current backend shape without a legacy inviteId',
    () async {
      final online = await service(sent, path: '/sendBattleV1Invite');
      expect(await online.sendBattleV1Invite('other'), 'sent');
    },
  );
  for (final change
      in <String, Map<String, dynamic>>{
        'missing confirmation': {'ok': null},
        'not sent': {'sent': false},
        'string confirmation': {'sent': 'true'},
        'wrong status': {'status': 'accepted'},
        'missing expiry': {'expiresAt': null},
        'string expiry': {'expiresAt': '121000'},
        'invalid expiry': {'expiresAt': 0},
      }.entries) {
    test('V1 send rejects ${change.key}', () async {
      final online = await service({
        ...sent,
        ...change.value,
      }, path: '/sendBattleV1Invite');
      await expectLater(
        online.sendBattleV1Invite('other'),
        change.key == 'missing confirmation'
            ? throwsA(
              isA<BattleV1Rejection>().having(
                (error) => error.code,
                'code',
                'invalid-server-response',
              ),
            )
            : throwsFormatException,
      );
    });
  }

  test(
    'V1 acceptance confirms a paired snapshot owned by the caller',
    () async {
      final response = {
        ...v1Response(),
        'accepted': true,
        'durationMinutes': 5,
      };
      final online = await service(
        response,
        path: '/respondBattleV1Invite',
        accept: true,
      );
      final accepted = await online.respondBattleV1Invite(
        'other',
        accept: true,
      );
      final snapshot = BattleV1Snapshot.fromResponse(accepted, 'self');
      expect(snapshot.matchId, v1MatchId);
      expect(snapshot.player.ownHand, hasLength(3));
    },
  );

  for (final scenario in [
    'missing confirmation',
    'opposite confirmation',
    'string confirmation',
    'missing view',
    'legacy view',
    'wrong match',
    'wrong account',
    'unpaired version',
    'wrong status',
    'secret field',
  ]) {
    test('V1 acceptance rejects $scenario before navigation', () async {
      final response = {...v1Response(), 'accepted': true};
      final view = response['view'] as Map;
      final public = view['public'] as Map;
      final private = view['private'] as Map;
      switch (scenario) {
        case 'missing confirmation':
          response.remove('accepted');
        case 'opposite confirmation':
          response['accepted'] = false;
        case 'string confirmation':
          response['accepted'] = 'true';
        case 'missing view':
          response.remove('view');
        case 'legacy view':
          response['view'] = {'matchId': v1MatchId};
        case 'wrong match':
          response['matchId'] = 'bv1_${'a' * 32}';
        case 'wrong account':
          (public['participants'] as Map).remove('self');
        case 'unpaired version':
          private['stateVersion'] = 1;
        case 'wrong status':
          response['status'] = 'idle';
        case 'secret field':
          private['opponentHand'] = ['freeze'];
      }
      final online = await service(
        response,
        path: '/respondBattleV1Invite',
        accept: true,
      );
      await expectLater(
        online.respondBattleV1Invite('other', accept: true),
        throwsFormatException,
      );
    });
  }

  test('V1 decline requires explicit negative acknowledgement', () async {
    final online = await service(
      {'ok': true, 'accepted': false},
      path: '/respondBattleV1Invite',
      accept: false,
    );
    expect(
      await online.respondBattleV1Invite('other', accept: false),
      containsPair('accepted', false),
    );
  });
  for (final accepted in [null, true, 'false']) {
    test('V1 decline rejects contradictory confirmation $accepted', () async {
      final online = await service(
        {'ok': true, 'accepted': accepted},
        path: '/respondBattleV1Invite',
        accept: false,
      );
      await expectLater(
        online.respondBattleV1Invite('other', accept: false),
        throwsFormatException,
      );
    });
  }

  test('V1 accepted response cannot cross an account replacement', () async {
    final auth = TestAuth()..currentUser = TestUser('self');
    final entered = Completer<void>();
    final pending = Completer<http.Response>();
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth,
      appCheck: () async => 'check',
      client: MockClient((_) {
        entered.complete();
        return pending.future;
      }),
    );
    addTearDown(online.dispose);
    await online.start();
    final result = online.respondBattleV1Invite('other', accept: true);
    final assertion = expectLater(
      result,
      throwsA(
        isA<BattleV1Rejection>().having(
          (error) => error.code,
          'code',
          'session-changed',
        ),
      ),
    );
    await entered.future;
    auth.currentUser = TestUser('other');
    pending.complete(
      http.Response(jsonEncode({...v1Response(), 'accepted': true}), 200),
    );
    await assertion;
  });

  for (final scenario in [
    'confirmed',
    'missing view',
    'opposite confirmation',
  ]) {
    testWidgets('incoming V1 invite navigation requires $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final response = {...v1Response(), 'accepted': true};
      if (scenario == 'missing view') response.remove('view');
      if (scenario == 'opposite confirmation') response['accepted'] = false;
      var requests = 0;
      final paths = <String>[];
      final bodies = <Map>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth()..currentUser = TestUser('self'),
        appCheck: () async => 'check',
        databaseRead: (_) async => {},
        friendRequestStream: Stream.value(<Map<String, dynamic>>[]),
        matchInviteStream: Stream.value(<Map<String, dynamic>>[
          {'fromUid': 'other', 'fromUsername': 'Other'},
        ]),
        client: MockClient((request) async {
          paths.add(request.url.path);
          bodies.add(jsonDecode(request.body) as Map);
          requests++;
          return http.Response(jsonEncode(response), 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: FriendsScreen(online: online)),
      );
      await tester.pumpAndSettle();
      final accept =
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Kabul et',
                ),
              )
              .onPressed!;
      accept();
      accept();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(requests, 1, reason: '$paths');
      expect(paths.single.endsWith('/respondBattleV1Invite'), true);
      expect(bodies.single['accept'], true);
      if (scenario == 'confirmed') {
        // Route-entry proof, not live Firebase or native match-bootstrap proof.
        final battle = tester.widget<BattleV1Screen>(
          find.byType(BattleV1Screen),
        );
        expect(battle.matchId, v1MatchId);
        expect(battle.initialView, response['view']);
      } else {
        expect(find.byType(BattleV1Screen, skipOffstage: false), findsNothing);
        expect(find.text('Maç daveti güncellenemedi.'), findsOneWidget);
        expect(find.text('Davet kabul edildi.'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
