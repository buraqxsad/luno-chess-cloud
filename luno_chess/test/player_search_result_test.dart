import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/player_search_result.dart';

void main() {
  test(
    'backend response needs no explicit ok flag and preserves profile fields',
    () {
      final rows = parsePlayerSearchResult({
        'results': [
          {
            'uid': ' target ',
            'relationship': 'none',
            'bio': 'hello',
            'username': 'target',
          },
          {'uid': 'target', 'relationship': 'friends'},
          {'uid': 'self', 'relationship': 'none'},
        ],
      }, ownUid: 'self');
      expect(rows, hasLength(1));
      expect(rows.single['uid'], 'target');
      expect(rows.single['bio'], 'hello');
    },
  );
  test('empty search is a valid result', () {
    expect(parsePlayerSearchResult({'results': []}, ownUid: 'self'), isEmpty);
  });
  for (final value in [
    {'ok': false, 'results': []},
    <String, dynamic>{},
    {
      'results': [42],
    },
    {
      'results': [
        {'uid': '', 'relationship': 'none'},
      ],
    },
    {
      'results': [
        {'uid': 12, 'relationship': 'none'},
      ],
    },
    {
      'results': [
        {'uid': 'target', 'relationship': 'unknown'},
      ],
    },
    {
      'results': [
        {'uid': 'target'},
      ],
    },
    {
      'results': [
        {1: 'target'},
      ],
    },
  ]) {
    test('malformed search is rejected: $value', () {
      expect(
        () => parsePlayerSearchResult(value, ownUid: 'self'),
        throwsFormatException,
      );
    });
  }
  for (final relationship in ['none', 'friends', 'incoming', 'outgoing']) {
    test('backend relationship $relationship is accepted', () {
      expect(
        parsePlayerSearchResult({
          'results': [
            {'uid': 'target', 'relationship': relationship},
          ],
        }, ownUid: 'self').single['relationship'],
        relationship,
      );
    });
  }
}
