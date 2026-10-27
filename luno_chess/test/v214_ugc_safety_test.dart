import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/ugc_consent.dart';
import 'package:luno_chess/services/ugc_text_safety.dart';
import 'package:luno_chess/services/profile_update_result.dart';
import 'package:luno_chess/services/public_player_profile.dart';
import 'package:luno_chess/services/direct_message_rows.dart';

Map<String, dynamic> ugcRecord(String uid) => {
  'uid': uid,
  'accepted': true,
  'acceptedAt': 1,
  'termsVersion': ugcTermsVersion,
  'privacyVersion': ugcPrivacyVersion,
  'communityVersion': ugcCommunityVersion,
};

Map<String, dynamic> ugcReply(String uid) => {
  'ok': true,
  'accepted': true,
  'legalConsent': ugcRecord(uid),
  'state': {'uid': uid, 'legalConsent': ugcRecord(uid)},
};

void main() {
  for (final value in [
    'a\u202Eb',
    'a\u2066b',
    'a\u200Bb',
    'a\u0085b',
    'a\u0000b',
    '<script>x</script>',
  ]) {
    test('unsafe UGC is refused and hidden: ${value.runes.toList()}', () {
      expect(
        normalizeUgcText(value, maxLength: bioMaxLength, allowEmpty: true),
        isNull,
      );
      expect(safePublicBio(value), isEmpty);
      expect(
        parsePublicPlayerProfile('other', {
          'username': 'luno_friend',
          'bio': value,
        })!['bio'],
        isEmpty,
      );
      expect(
        parseDirectMessageRows(
          {
            'message': {'from': 'other', 'text': value, 'ts': 1},
          },
          viewerUid: 'first',
          targetUid: 'other',
        ),
        isEmpty,
      );
    });
  }
  test('bio whitespace, boundaries and emoji joiners stay consistent', () {
    expect(
      normalizeUgcText('  Merhaba\t\n dünya  ', maxLength: bioMaxLength),
      'Merhaba dünya',
    );
    expect(
      normalizeUgcText('👩‍💻 şah ♟', maxLength: bioMaxLength),
      '👩‍💻 şah ♟',
    );
    expect(normalizeUgcText('x' * 160, maxLength: bioMaxLength), 'x' * 160);
    expect(normalizeUgcText('x' * 161, maxLength: bioMaxLength), isNull);
    expect(
      normalizeUgcText('x' * 500, maxLength: directMessageMaxLength),
      'x' * 500,
    );
    expect(
      normalizeUgcText('x' * 501, maxLength: directMessageMaxLength),
      isNull,
    );
    expect(
      normalizeUgcText(' ' * 4097, maxLength: bioMaxLength, allowEmpty: true),
      isNull,
    );
  });
  test(
    'normalized profile echo must still match the actual submitted biography',
    () {
      expect(
        validateProfileUpdateResult(
          {
            'ok': true,
            'state': {
              'profile': {'bio': 'Hello world'},
            },
          },
          {'bio': ' Hello\tworld '},
        ),
        isA<Map>(),
      );
      expect(
        () => validateProfileUpdateResult(
          {
            'ok': true,
            'state': {
              'profile': {'bio': 'Another biography'},
            },
          },
          {'bio': 'Hello world'},
        ),
        throwsFormatException,
      );
      expect(
        () => validateProfileUpdateResult(
          {
            'ok': true,
            'state': {
              'profile': {'bio': 'a\u202Eb'},
            },
          },
          {'bio': 'a\u202Eb'},
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'only confirmed current server versions for the exact account can persist',
    () {
      expect(
        validateUgcConsentResult(ugcReply('first'), 'first'),
        ugcRecord('first'),
      );
      for (final reply in [
        {'ok': true},
        {...ugcReply('first'), 'accepted': false},
        ugcReply('second'),
        {
          ...ugcReply('first'),
          'legalConsent': {...ugcRecord('first'), 'communityVersion': 'old'},
        },
        {
          ...ugcReply('first'),
          'legalConsent': {...ugcRecord('first'), 'acceptedAt': 0},
        },
        {
          ...ugcReply('first'),
          'state': {
            'uid': 'first',
            'legalConsent': {...ugcRecord('first'), 'acceptedAt': 2},
          },
        },
        {
          ...ugcReply('first'),
          'state': {'uid': 'second', 'legalConsent': ugcRecord('first')},
        },
      ]) {
        expect(
          () => validateUgcConsentResult(reply, 'first'),
          throwsFormatException,
        );
      }
    },
  );
  test('acknowledgement persistence is UID namespaced rather than global', () {
    expect(
      ugcConsentStorageKey('first'),
      isNot(ugcConsentStorageKey('second')),
    );
    expect(confirmedUgcConsent(ugcRecord('first'), 'second'), isNull);
  });
}
