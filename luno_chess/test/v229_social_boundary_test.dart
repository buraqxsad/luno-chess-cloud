import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/direct_message_read_key.dart';
import 'package:luno_chess/services/direct_message_rows.dart';
import 'package:luno_chess/services/social_action_result.dart';
import 'package:luno_chess/services/social_safety_result.dart';

List<Map<String, dynamic>> _messages(Object? value) =>
    parseDirectMessageRows(value, viewerUid: 'viewer', targetUid: 'target');

Map<String, dynamic> _message({
  Object? from = 'target',
  Object? text = 'hello',
  Object? ts = 1,
}) => {'from': from, 'text': text, 'ts': ts};

List<BlockedPlayer> _blocked(List<Object?> rows) =>
    parseBlockedPlayers({'ok': true, 'results': rows}, viewerUid: 'viewer');

void main() {
  test('DM checks raw text before trimming forbidden edge characters', () {
    for (final hidden in ['\u0085', '\uFEFF']) {
      for (final text in ['${hidden}hello', 'hello$hidden']) {
        expect(_messages({'m': _message(text: text)}), isEmpty);
      }
    }
  });

  test('DM raw size limit cannot be bypassed with trimmed padding', () {
    expect(
      _messages({'m': _message(text: '${' ' * 4091}hello')}).single['text'],
      'hello',
    );
    expect(_messages({'m': _message(text: '${' ' * 4092}hello')}), isEmpty);
    expect(_messages({'m': _message(text: 'hello${' ' * 4092}')}), isEmpty);
  });

  test('DM keeps bounded multiline display text without unsafe metadata', () {
    final row =
        _messages({
          'm': {
            ..._message(text: '  hello\nworld  '),
            'read': true,
            'unread': false,
            'messageId': 'forged',
            'private': {'uid': 'other'},
          },
        }).single;
    expect(row, {
      'messageId': 'm',
      'from': 'target',
      'text': 'hello\nworld',
      'ts': 1,
    });
    expect(_messages({'m': _message(text: 'x' * 500)}), hasLength(1));
    expect(_messages({'m': _message(text: 'x' * 501)}), isEmpty);
  });

  test('DM participant validation rejects self and path-shaped accounts', () {
    for (final viewer in ['', 'target', '../viewer', ' viewer']) {
      expect(
        () => parseDirectMessageRows(
          null,
          viewerUid: viewer,
          targetUid: 'target',
        ),
        throwsFormatException,
      );
    }
    final rows = _messages({
      'mine': _message(from: 'viewer'),
      'incoming': _message(),
      'previous_account': _message(from: 'previous'),
      'object_sender': _message(from: {'uid': 'target'}),
    });
    expect(rows.map((row) => row['messageId']), ['incoming', 'mine']);
  });

  test('DM snapshot keys own identity despite duplicate embedded IDs', () {
    final rows = _messages({
      'a': {..._message(), 'messageId': 'same'},
      'b': {..._message(), 'messageId': 'same'},
    });
    expect(rows.map((row) => row['messageId']), ['a', 'b']);
    expect(
      directMessageReadKey(rows),
      isNot(directMessageReadKey([rows.last])),
    );
    expect(
      () => _messages({1: _message(), '1': _message()}),
      throwsFormatException,
    );
  });

  test('DM malformed times normalize before identity encoding', () {
    for (final value in <Object?>[
      null,
      true,
      double.nan,
      double.infinity,
      -1,
      9007199254740992,
      'Infinity',
      {'timestamp': 1},
    ]) {
      final rows = _messages({'m': _message(ts: value)});
      expect(rows.single['ts'], 0);
      expect(
        directMessageReadKey(rows),
        directMessageReadKey(_messages({'m': _message(ts: 0)})),
      );
    }
    final rows = _messages({
      'z': _message(ts: '2'),
      'a': _message(ts: 2),
      'early': _message(ts: 1),
    });
    expect(rows.map((row) => row['messageId']), ['early', 'a', 'z']);
  });

  test('read key tracks replacements and multiplicity without text', () {
    final before = _messages({'a': _message(), 'last': _message(ts: 2)});
    final after = _messages({'b': _message(), 'last': _message(ts: 2)});
    expect(directMessageReadKey(before), isNot(directMessageReadKey(after)));
    expect(
      directMessageReadKey(before),
      directMessageReadKey([
        for (final row in before) {...row, 'text': 'different private text'},
      ]),
    );
    expect(
      directMessageReadKey([before.first]),
      isNot(directMessageReadKey([before.first, before.first])),
    );
    expect(directMessageReadKey([]), isEmpty);
  });

  for (final field in ['username', 'name']) {
    test('blocked $field rejects invisible and unsafe display identities', () {
      for (final name in [
        '\u200B',
        'player\u200E',
        'player\u200F',
        'player\u0085',
        '\uFEFFplayer',
        'player\u2060',
        'player\u202E',
        '<player>',
      ]) {
        expect(
          () => _blocked([
            {'uid': 'target', field: name},
          ]),
          throwsFormatException,
        );
      }
    });
  }

  test('blocked IDs reject duplicates and self, but allow duplicate names', () {
    for (final rows in <List<Object?>>[
      [
        {'uid': 'viewer', 'name': 'self'},
      ],
      [
        {'uid': 'target', 'name': 'first'},
        {'uid': 'target', 'name': 'second'},
      ],
      [
        {'uid': 'bad/path', 'name': 'player'},
      ],
      [
        {1: 'invalid key', 'uid': 'target', 'name': 'player'},
      ],
    ]) {
      expect(() => _blocked(rows), throwsFormatException);
    }
    final rows = _blocked([
      {'uid': 'first', 'name': 'same'},
      {'uid': 'second', 'name': 'same'},
    ]);
    expect(rows.map((row) => row.uid), ['first', 'second']);
    expect(() => rows.clear(), throwsUnsupportedError);
  });

  test('blocked names retain safe Unicode and deleted-player fallback', () {
    final rows = _blocked([
      {'uid': 'target', 'username': '  player_1  ', 'name': 'ignored'},
      {'uid': 'deleted', 'username': '', 'name': 'Silinmi\u015f oyuncu'},
      {'uid': 'unicode', 'name': 'Oyuncu \u015eah \u265f'},
    ]);
    expect(rows.map((row) => row.name), [
      'player_1',
      'Silinmi\u015f oyuncu',
      'Oyuncu \u015eah \u265f',
    ]);
  });

  test('friend mutations require booleans and the requested outcome', () {
    for (final accept in [true, false]) {
      validateFriendResponse({'ok': true, 'accepted': accept}, accept: accept);
      for (final accepted in <Object?>[null, '$accept', 1, !accept, {}]) {
        expect(
          () => validateFriendResponse({
            'ok': true,
            'accepted': accepted,
          }, accept: accept),
          throwsFormatException,
        );
      }
    }
    validateFriendRemoval({'ok': true, 'removed': true});
    for (final removed in <Object?>[null, 'true', 1, false, {}]) {
      expect(
        () => validateFriendRemoval({'ok': true, 'removed': removed}),
        throwsFormatException,
      );
    }
    for (final status in <Object?>[null, true, 'unknown', ' sent', {}]) {
      expect(
        () => friendRequestStatus({'ok': true, 'status': status}),
        throwsFormatException,
      );
    }
  });

  test('legacy match outcomes preserve their existing contract', () {
    expect(matchInviteStatus({'sent': true, 'inviteId': 'fi_a'}), 'sent');
    expect(
      matchInviteStatus({
        'ok': true,
        'sent': false,
        'status': 'pending',
        'inviteId': 'fi_a',
      }),
      'pending',
    );
    expect(
      () => matchInviteStatus({
        'ok': true,
        'sent': true,
        'status': 'pending',
        'inviteId': 'fi_a',
      }),
      throwsFormatException,
    );
    validateMatchInviteResponse({'accepted': false}, accept: false);
    expect(
      () => validateMatchInviteResponse({
        'ok': true,
        'accepted': true,
        'matchId': 'm1',
        'view': {'matchId': 'm2'},
      }, accept: true),
      throwsFormatException,
    );
  });

  test('safety confirmations bind target and reject forged report IDs', () {
    for (final blocked in [true, false]) {
      validateSocialBlockResult(
        {'ok': true, 'targetUid': 'target', 'blocked': blocked},
        targetUid: 'target',
        blocked: blocked,
      );
      expect(
        () => validateSocialBlockResult(
          {'ok': true, 'targetUid': 'other', 'blocked': blocked},
          targetUid: 'target',
          blocked: blocked,
        ),
        throwsFormatException,
      );
    }
    validateSocialReportResult({
      'ok': true,
      'reported': true,
      'reportId': 'rp_valid',
    });
    for (final id in <Object?>[null, {}, 'rp_bad/path', 'rp_${'x' * 129}']) {
      expect(
        () => validateSocialReportResult({
          'ok': true,
          'reported': true,
          'reportId': id,
        }),
        throwsFormatException,
      );
    }
  });
}
