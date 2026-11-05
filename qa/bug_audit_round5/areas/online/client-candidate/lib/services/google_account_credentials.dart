import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Selects a Google identity without changing the active Firebase account.
class GoogleAccountCredentials {
  static Future<void>? _initialization;

  static OAuthCredential fromIdToken(String? token) {
    if (token == null || token.trim().isEmpty) {
      throw FirebaseAuthException(code: 'google-id-token-missing');
    }
    return GoogleAuthProvider.credential(idToken: token);
  }

  static Future<OAuthCredential> select() async {
    final google = GoogleSignIn.instance;
    final pending = _initialization ??= google.initialize();
    try {
      await pending;
    } catch (_) {
      if (identical(_initialization, pending)) _initialization = null;
      rethrow;
    }
    try {
      final account = await google.authenticate();
      return fromIdToken(account.authentication.idToken);
    } on GoogleSignInException catch (error) {
      throw FirebaseAuthException(
        code: switch (error.code) {
          GoogleSignInExceptionCode.canceled => 'web-context-canceled',
          GoogleSignInExceptionCode.interrupted => 'web-context-canceled',
          GoogleSignInExceptionCode.clientConfigurationError =>
            'google-client-configuration',
          _ => 'google-sign-in-failed',
        },
      );
    }
  }
}
