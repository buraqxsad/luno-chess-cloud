import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:luno_chess/services/battle_v1_rank.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'v214_active_deck_test.dart' show setup, reply;
import 'v214_rank_projection_test.dart' show rank;
import 'online_request_session_test.dart' show TestUser;

Map<String, dynamic> profile(String uid, int trophies) => {
  'uid': uid,
  'username': '${uid}_name',
  'trophies': 9000,
  'battleV1Rank': rank(uid, trophies),
  'bio': 'Current biography',
  'email': 'private',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('production profile read uses safe V1 API, not direct RTDB', () async {
    final (store, online, _) = await setup((request) async {
      expect(request.url.path.endsWith('/getPublicPlayerProfile'), isTrue);
      final body = jsonDecode(request.body) as Map;
      expect(body['targetUid'], 'target');
      expect(body['protocolVersion'], BattleV1Rank.protocolVersion);
      return reply({'ok': true, 'profile': profile('target', 612)});
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    final value = (await online.publicPlayerProfile('target'))!;
    expect(value['trophies'], 612);
    expect(value['bio'], 'Current biography');
    expect(value.containsKey('email'), isFalse);
  });
  test(
    'production friends roster uses server rank and deterministic sorting',
    () async {
      final (store, online, _) = await setup((request) async {
        expect(request.url.path.endsWith('/getFriends'), isTrue);
        expect(
          (jsonDecode(request.body) as Map)['protocolVersion'],
          BattleV1Rank.protocolVersion,
        );
        return reply({
          'ok': true,
          'protocolVersion': BattleV1Rank.protocolVersion,
          'results': [profile('target_a', 42), profile('target_b', 612)],
        });
      });
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      final rows = await online.friends();
      expect(rows.map((row) => row['uid']), ['target_b', 'target_a']);
      expect(rows.map((row) => row['trophies']), [612, 42]);
      expect(rows.any((row) => row.containsKey('email')), isFalse);
    },
  );
  for (final scenario in [
    'duplicate',
    'foreign-rank',
    'legacy-only',
    'wrong-protocol',
    'self',
    'non-list',
  ]) {
    test('production roster fails closed on $scenario', () async {
      final value = profile('target', 612);
      if (scenario == 'foreign-rank') {
        value['battleV1Rank'] = rank('other', 612);
      }
      if (scenario == 'legacy-only') value.remove('battleV1Rank');
      if (scenario == 'self') value['uid'] = 'first';
      final (store, online, _) = await setup(
        (_) async => reply({
          'ok': true,
          'protocolVersion':
              scenario == 'wrong-protocol'
                  ? 'OLD'
                  : BattleV1Rank.protocolVersion,
          'results':
              scenario == 'non-list'
                  ? {}
                  : [value, if (scenario == 'duplicate') value],
        }),
      );
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      await expectLater(online.friends(), throwsFormatException);
    });
  }
  test(
    'missing/deleted/blocked target is distinct from a connection error',
    () async {
      final (store, online, _) = await setup(
        (_) async =>
            http.Response(jsonEncode({'error': 'target-not-found'}), 404),
      );
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      expect(await online.publicPlayerProfile('target'), isNull);
    },
  );
  test('friends beyond the first hundred remain visible and sorted', () async {
    var calls = 0;
    final (store, online, _) = await setup((request) async {
      final body = jsonDecode(request.body) as Map;
      calls++;
      if (calls == 1) {
        expect(body.containsKey('pageToken'), isFalse);
        return reply({
          'ok': true,
          'protocolVersion': BattleV1Rank.protocolVersion,
          'results': [
            for (var i = 0; i < 100; i++)
              profile('friend_${i.toString().padLeft(3, '0')}', i),
          ],
          'nextPageToken': 'friend_099',
        });
      }
      expect(body['pageToken'], 'friend_099');
      return reply({
        'ok': true,
        'protocolVersion': BattleV1Rank.protocolVersion,
        'results': [profile('friend_100', 612)],
        'nextPageToken': null,
      });
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    final rows = await online.friends();
    expect(rows, hasLength(101));
    expect(rows.first['uid'], 'friend_100');
    expect(calls, 2);
  });
  for (final duplicate in [false, true]) {
    test(
      'friend pages reject ${duplicate ? 'duplicate players' : 'cursor loops'}',
      () async {
        var calls = 0;
        final (store, online, _) = await setup((_) async {
          calls++;
          return reply({
            'ok': true,
            'protocolVersion': BattleV1Rank.protocolVersion,
            'results': [profile(duplicate ? 'target' : 'target_$calls', 42)],
            'nextPageToken': 'repeated',
          });
        });
        addTearDown(store.dispose);
        addTearDown(online.dispose);
        await expectLater(online.friends(), throwsFormatException);
        expect(calls, 2);
      },
    );
  }
  test(
    'filtered empty friend page still advances to later visible friends',
    () async {
      var calls = 0;
      final (store, online, _) = await setup(
        (_) async => reply({
          'ok': true,
          'protocolVersion': BattleV1Rank.protocolVersion,
          'results': ++calls == 1 ? [] : [profile('target', 42)],
          'nextPageToken': calls == 1 ? 'filtered' : null,
        }),
      );
      addTearDown(store.dispose);
      addTearDown(online.dispose);
      expect((await online.friends()).single['uid'], 'target');
      expect(calls, 2);
    },
  );
  test('opaque server cursor preserves maximum-length owner and key', () async {
    final token = base64Url
        .encode(
          utf8.encode(jsonEncode({'v': 1, 'uid': 'u' * 128, 'key': 'k' * 128})),
        )
        .replaceAll('=', '');
    expect(token.length, greaterThan(256));
    var calls = 0;
    final (store, online, _) = await setup((request) async {
      if (++calls == 1) {
        return reply({
          'ok': true,
          'protocolVersion': BattleV1Rank.protocolVersion,
          'results': [],
          'nextPageToken': token,
        });
      }
      expect((jsonDecode(request.body) as Map)['pageToken'], token);
      return reply({
        'ok': true,
        'protocolVersion': BattleV1Rank.protocolVersion,
        'results': [],
        'nextPageToken': null,
      });
    });
    addTearDown(store.dispose);
    addTearDown(online.dispose);
    expect(await online.friends(), isEmpty);
    expect(calls, 2);
  });
  for (final route in ['profile', 'friends']) {
    test(
      'late production $route response cannot cross account switch',
      () async {
        final entered = Completer<void>();
        final pending = Completer<http.Response>();
        final (store, online, auth) = await setup((_) {
          entered.complete();
          return pending.future;
        });
        addTearDown(store.dispose);
        addTearDown(online.dispose);
        final operation =
            route == 'profile'
                ? online.publicPlayerProfile('target')
                : online.friends();
        await entered.future;
        auth.currentUser = TestUser('second');
        pending.complete(
          reply({
            'ok': true,
            'profile': profile('target', 612),
            'protocolVersion': BattleV1Rank.protocolVersion,
            'results': [profile('target', 612)],
          }),
        );
        await expectLater(
          operation,
          throwsA(
            isA<LunoApiException>().having(
              (error) => error.code,
              'code',
              'session-changed',
            ),
          ),
        );
      },
    );
  }
}
