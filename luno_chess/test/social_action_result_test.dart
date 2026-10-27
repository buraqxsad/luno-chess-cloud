import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/social_action_result.dart';

void main() {
  test('friend accept and decline must match requested action', () {
    for (final accept in [true, false]) {
      expect(
        () => validateFriendResponse({
          'ok': true,
          'accepted': accept,
        }, accept: accept),
        returnsNormally,
      );
      for (final result in <Map<String, dynamic>>[
        {},
        {'ok': true},
        {'ok': true, 'accepted': !accept},
        {'ok': false, 'accepted': accept},
      ]) {
        expect(
          () => validateFriendResponse(result, accept: accept),
          throwsFormatException,
        );
      }
    }
  });
  test('removal needs explicit confirmation', () {
    expect(
      () => validateFriendRemoval({'ok': true, 'removed': true}),
      returnsNormally,
    );
    for (final result in <Map<String, dynamic>>[
      {},
      {'ok': true},
      {'ok': true, 'removed': false},
    ]) {
      expect(() => validateFriendRemoval(result), throwsFormatException);
    }
  });
  test('accepted invitations need a consistent match payload', () {
    expect(
      () => validateMatchInviteResponse({'accepted': false}, accept: false),
      returnsNormally,
    );
    expect(
      () => validateMatchInviteResponse({
        'accepted': true,
        'matchId': 'm1',
        'view': {'matchId': 'm1'},
      }, accept: true),
      returnsNormally,
    );
    for (final result in <Map<String, dynamic>>[
      {},
      {'accepted': false},
      {'accepted': true},
      {'accepted': true, 'matchId': 'm1', 'view': {}},
      {
        'accepted': true,
        'matchId': 'm1',
        'view': {'matchId': 'm2'},
      },
    ]) {
      expect(
        () => validateMatchInviteResponse(result, accept: true),
        throwsFormatException,
      );
    }
  });
  test('friend requests accept only confirmed known outcomes', () {
    for (final status in ['sent', 'pending', 'accepted', 'friends']) {
      expect(friendRequestStatus({'ok': true, 'status': status}), status);
    }
    for (final result in <Map<String, dynamic>>[
      {},
      {'ok': true},
      {'ok': false, 'status': 'sent'},
      {'ok': true, 'status': 'unknown'},
    ]) {
      expect(() => friendRequestStatus(result), throwsFormatException);
    }
  });
  test('new and already pending invitations match backend contract', () {
    expect(matchInviteStatus({'sent': true, 'inviteId': 'fi_a'}), 'sent');
    expect(
      matchInviteStatus({
        'sent': false,
        'status': 'pending',
        'inviteId': 'fi_a',
      }),
      'pending',
    );
  });
  test(
    'missing and contradictory invitation outcomes cannot report success',
    () {
      for (final result in <Map<String, dynamic>>[
        {},
        {'sent': true},
        {'sent': true, 'inviteId': ''},
        {'sent': false, 'inviteId': 'fi_a'},
        {'sent': true, 'status': 'pending', 'inviteId': 'fi_a'},
        {'ok': false, 'sent': true, 'inviteId': 'fi_a'},
        {'sent': 'true', 'inviteId': 'fi_a'},
      ]) {
        expect(() => matchInviteStatus(result), throwsFormatException);
      }
    },
  );
}
