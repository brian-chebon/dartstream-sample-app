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

  // ---- IntelliToggle (Aortem feature-flag SaaS, via OpenFeature) -----------
  //
  // The IntelliToggle OpenFeature provider authenticates with OAuth2
  // client-credentials. These are injected at build time, never committed:
  //   flutter run -d chrome --web-port=3000 \
  //     --dart-define=FIREBASE_API_KEY=YOUR_KEY \
  //     --dart-define=INTELLITOGGLE_CLIENT_ID=... \
  //     --dart-define=INTELLITOGGLE_CLIENT_SECRET=... \
  //     --dart-define=INTELLITOGGLE_TENANT_ID=...
  // The secret is confidential — supplying it to a web bundle is only safe for
  // a demo/sandbox tenant; production keeps client-credentials server-side.
  static const intelliToggleClientId =
      String.fromEnvironment('INTELLITOGGLE_CLIENT_ID');
  static const intelliToggleClientSecret =
      String.fromEnvironment('INTELLITOGGLE_CLIENT_SECRET');
  static const intelliToggleTenantId =
      String.fromEnvironment('INTELLITOGGLE_TENANT_ID');

  /// Optional API host override; defaults to IntelliToggle production.
  static const intelliToggleApiUrl = String.fromEnvironment(
    'INTELLITOGGLE_API_URL',
    defaultValue: 'https://api.intellitoggle.com',
  );

  /// Whether all three IntelliToggle client-credentials were injected; the
  /// IntelliToggle screen surfaces this and explains how to supply them.
  static bool get hasIntelliToggle =>
      intelliToggleClientId.isNotEmpty &&
      intelliToggleClientSecret.isNotEmpty &&
      intelliToggleTenantId.isNotEmpty;
}
