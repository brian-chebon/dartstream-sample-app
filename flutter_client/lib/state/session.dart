import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/foundation.dart';

import '../auth/google_auth.dart';
import '../config.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

/// Holds the authenticated DartStream connection for the app.
///
/// This is exactly how a customer wires the SDK into Flutter: sign in once via
/// [DartStreamClient.signIn] / [DartStreamClient.signUp], keep the resulting
/// [DartStreamConnection], and call its typed clients
/// (`client.auth` / `.platform` / `.experience` / `.reactive` / `.persistence`)
/// from the UI — passing the [DartStreamSession] the SDK handed back. The app
/// adds no API layer of its own; the SDK owns transport, auth, and tenancy.
class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? errorMessage;
  DartStreamConnection? _connection;

  /// The live SDK connection (client + session), or null when signed out.
  DartStreamConnection? get connection => _connection;

  /// The authenticated SDK client — use its typed clients for every call.
  DartStreamClient? get client => _connection?.client;

  /// The SDK session (idToken + userId + tenantId) passed to client calls.
  DartStreamSession? get ds => _connection?.session;

  String? get email => ds?.email;
  String? get userId => ds?.userId;
  String? get tenantId => ds?.tenantId;
  bool get isSignedIn => status == SessionStatus.signedIn;

  Future<void> signUp(String email, String password) => _authenticate(
        () => DartStreamClient.signUp(
          config: AppConfig.dartStream,
          email: email,
          password: password,
        ),
      );

  Future<void> signIn(String email, String password) => _authenticate(
        () => DartStreamClient.signIn(
          config: AppConfig.dartStream,
          email: email,
          password: password,
        ),
      );

  /// Federated sign-in with Google (web only). Obtains a Firebase ID token via
  /// Google Identity Services + Identity Toolkit, then onboards a DartStream
  /// session through the SDK's provider path — the same [DartStreamConnection]
  /// the email/password flow produces. Email/password is untouched; additive.
  Future<void> signInWithGoogle() => _authenticate(() async {
        final firebaseIdToken = await signInWithGoogleFirebaseIdToken(
          clientId: AppConfig.googleOAuthClientId,
          firebaseApiKey: AppConfig.firebaseApiKey,
        );
        final client = DartStreamClient(config: AppConfig.dartStream);
        final session = await client.auth.onboardProviderIdToken(
          provider: DartStreamAuthProvider.google,
          firebaseIdToken: firebaseIdToken,
        );
        return DartStreamConnection(
          client: client.withSession(session),
          session: session,
        );
      });

  Future<void> _authenticate(
    Future<DartStreamConnection> Function() connect,
  ) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();
    try {
      _connection = await connect();
      status = SessionStatus.signedIn;
    } on DartStreamFirebaseAuthException catch (e) {
      status = SessionStatus.error;
      errorMessage = e.message;
    } on DartStreamApiException catch (e) {
      status = SessionStatus.error;
      errorMessage = 'HTTP ${e.statusCode}: ${e.body}';
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  void signOut() {
    _connection?.client.close();
    _connection = null;
    status = SessionStatus.signedOut;
    errorMessage = null;
    notifyListeners();
  }
}
