import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/google_account_credentials.dart';

void main() {
  for (final token in <String?>[null, '', '   ']) {
    test('native Google exchange rejects missing ID token: $token', () {
      expect(
        () => GoogleAccountCredentials.fromIdToken(token),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'google-id-token-missing',
          ),
        ),
      );
    });
  }
  test('native Google ID token becomes a Firebase Google credential', () {
    final credential = GoogleAccountCredentials.fromIdToken(
      'selected-google-id-token',
    );
    expect(credential.providerId, 'google.com');
    expect(credential.signInMethod, 'google.com');
    expect(credential.idToken, 'selected-google-id-token');
    expect(credential.accessToken, isNull);
  });
}
