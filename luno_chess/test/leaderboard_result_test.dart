import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/leaderboard_result.dart';

void main() {
  for (final entry
      in {
        'trophies': 'trophies',
        'collection': 'collectionScore',
        'season': 'seasonScore',
      }.entries) {
    Map<String, dynamic> response(Object? rows) => {
      'ok': true,
      'mode': entry.key,
      'results': rows,
    };
    test(
      '${entry.key} distinguishes empty results from malformed responses',
      () {
        expect(parseLeaderboardResult(response([]), entry.key), isEmpty);
        for (final value in [null, {}, 'bad']) {
          expect(
            () => parseLeaderboardResult(response(value), entry.key),
            throwsFormatException,
          );
        }
        expect(
          () =>
              parseLeaderboardResult({...response([]), 'ok': false}, entry.key),
          throwsFormatException,
        );
        expect(
          () => parseLeaderboardResult({
            ...response([]),
            'mode': 'wrong',
          }, entry.key),
          throwsFormatException,
        );
      },
    );
    test('${entry.key} sorts and deduplicates stable identities', () {
      final rows = parseLeaderboardResult(
        response([
          {'uid': 'b', 'username': 'bbb', entry.value: 10},
          {'uid': ' a ', 'username': 'aaa', entry.value: 10},
          {'uid': 'c', 'username': 'ccc', entry.value: 20},
          {'uid': 'a', 'username': 'aaa', entry.value: 10},
        ]),
        entry.key,
      );
      expect(rows.map((row) => row['uid']), ['c', 'a', 'b']);
    });
    test('${entry.key} rejects invalid score and identity values', () {
      for (final score in [null, '10', -1, 1.5, double.nan, double.infinity]) {
        expect(
          () => parseLeaderboardResult(
            response([
              {'uid': 'a', entry.value: score},
            ]),
            entry.key,
          ),
          throwsFormatException,
        );
      }
      for (final uid in [null, '', ' ', 123]) {
        expect(
          () => parseLeaderboardResult(
            response([
              {'uid': uid, entry.value: 10},
            ]),
            entry.key,
          ),
          throwsFormatException,
        );
      }
    });
  }
}
