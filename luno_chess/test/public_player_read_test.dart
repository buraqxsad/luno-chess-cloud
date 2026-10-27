import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/public_player_profile.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  test('public read normalizes safe fields without retaining private data', () {
    final row =
        parsePublicPlayerProfile('target', {
          'username': ' Current_Name ',
          'name': 'stale_name',
          'country': ' gb ',
          'bio': ' Biography ',
          'wins': 7,
          'gamesPlayed': 2,
          'trophies': 42,
          'isPremium': true,
          'email': 'private',
          'gold': 999,
          'purchaseTokens': ['secret'],
        })!;
    expect(row['username'], 'current_name');
    expect(row['bio'], 'Biography');
    expect(row['country'], 'GB');
    expect(row['gamesPlayed'], 7);
    expect(row['premium'], true);
    expect(row['isPremium'], true);
    expect(row.keys, isNot(contains('email')));
    expect(row.keys, isNot(contains('gold')));
    expect(row.keys, isNot(contains('purchaseTokens')));
  });
  test('missing profile is distinct from malformed profile', () {
    expect(parsePublicPlayerProfile('target', null), isNull);
    for (final value in [
      42,
      {},
      {'username': 12},
      {1: 'bad'},
      {'username': '!!'},
    ]) {
      expect(
        () => parsePublicPlayerProfile('target', value),
        throwsFormatException,
      );
    }
  });
  test('malformed display fields do not crash or stringify objects', () {
    final row =
        parsePublicPlayerProfile('target', {
          'name': 'legacy_name',
          'wins': double.nan,
          'gamesPlayed': double.infinity,
          'trophies': -4,
          'country': {},
          'bio': {},
          'avatarEmoji': 12,
          'isPremium': 'true',
        })!;
    expect(row['wins'], 0);
    expect(row['gamesPlayed'], 0);
    expect(row['trophies'], 0);
    expect(row['country'], 'TR');
    expect(row['bio'], '');
    expect(row['avatarEmoji'], 'av_pawn');
    expect(row['premium'], false);
  });
  for (final uid in [
    '',
    'bad/path',
    'bad.key',
    'bad#key',
    ' spaced ',
    'x' * 129,
  ]) {
    test('invalid UID cannot select a database path: $uid', () {
      expect(() => parsePublicPlayerProfile(uid, null), throwsFormatException);
    });
  }
  test(
    'friends read skips removed, self, malformed edges and missing profiles',
    () async {
      final paths = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        databaseRead: (path) async {
          paths.add(path);
          if (path == 'friends/first') {
            return {
              'first': true,
              'target': {'addedAt': 1},
              'missing': true,
              'removed': false,
              'bad/path': true,
              'string_edge': 'true',
            };
          }
          if (path == 'publicProfiles/missing') return null;
          return {
            'username': 'target_player',
            'wins': 2,
            'gamesPlayed': 1,
            'isPremium': true,
          };
        },
      );
      addTearDown(online.dispose);
      await online.start();
      final rows = await online.friends();
      expect(rows, hasLength(1));
      expect(rows.single['uid'], 'target');
      expect(rows.single['gamesPlayed'], 2);
      expect(paths.toSet(), {
        'friends/first',
        'publicProfiles/target',
        'publicProfiles/missing',
      });
    },
  );
  for (final change in ['account', 'signout', 'retry']) {
    test('public read ignores old session after $change', () async {
      final auth = TestAuth();
      final pending = Completer<Object?>();
      final entered = Completer<void>();
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        databaseRead: (path) async {
          if (path == 'friends/first') return {'target': true};
          entered.complete();
          return pending.future;
        },
      );
      addTearDown(online.dispose);
      await online.start();
      final operation = online.friends();
      await entered.future;
      if (change == 'account') auth.currentUser = TestUser('second');
      if (change == 'signout') auth.currentUser = null;
      if (change == 'retry') await online.retry();
      final assertion = expectLater(
        operation,
        throwsA(
          isA<LunoApiException>().having(
            (e) => e.code,
            'code',
            'session-changed',
          ),
        ),
      );
      pending.complete({'username': 'old_player'});
      await assertion;
    });
  }
  test(
    'malformed public record rejects the list rather than inventing a player',
    () async {
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        databaseRead:
            (path) async =>
                path.startsWith('friends/')
                    ? {'target': true}
                    : {'username': 42},
      );
      addTearDown(online.dispose);
      await online.start();
      await expectLater(online.friends(), throwsFormatException);
    },
  );
}
