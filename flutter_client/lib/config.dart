import 'package:dartstream_client/dartstream_client.dart';

/// App configuration for the DartStream sample.
///
/// Hosts, transport, auth, and tenant/session handling all live in the
/// `dartstream_client` SDK — the app only supplies the public Firebase web API
/// key (injected at build time, never committed):
///   flutter run -d chrome --web-port=3000 --dart-define=FIREBASE_API_KEY=YOUR_KEY
///
/// Firebase project: dartstream-prod (Sample-App-Brian-Chebon web app).
class AppConfig {
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');

  /// Whether a key was actually injected; the login flow surfaces this.
  static bool get hasFirebaseApiKey => firebaseApiKey.isNotEmpty;

  /// The DartStream SaaS dev environment, wired with our Firebase web key.
  /// Swap `.dev()` for `.prod()` to point at production.
  static DartStreamConfig get dartStream =>
      DartStreamConfig.dev(firebaseApiKey: firebaseApiKey);
}
