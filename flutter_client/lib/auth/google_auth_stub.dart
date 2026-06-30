/// Non-web stub for [signInWithGoogleFirebaseIdToken].
///
/// Google sign-in in this sample is wired through Google Identity Services,
/// which is web-only. On any non-web target this throws rather than pulling
/// `dart:js_interop` into the VM compile (keeps `flutter test` green).
Future<String> signInWithGoogleFirebaseIdToken({
  required String clientId,
  required String firebaseApiKey,
}) {
  throw UnsupportedError(
    'Google sign-in is only available in the web build of this sample.',
  );
}
