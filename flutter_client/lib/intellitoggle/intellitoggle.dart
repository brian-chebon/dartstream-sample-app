import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

import '../config.dart';

/// Thin app-level wrapper around the **IntelliToggle** OpenFeature provider.
///
/// IntelliToggle is Aortem's feature-flag SaaS. Unlike DartStream's own
/// `platform.featureFlags` (tenant-facing CRUD), here we evaluate flags through
/// the standard [OpenFeature] API: register the [IntelliToggleProvider] once and
/// read values via the active provider. The provider performs the OAuth2
/// **client-credentials** handshake (clientId + clientSecret + tenantId)
/// internally — the app never mints a token by hand.
///
/// Registration is global (OpenFeature keeps a single active provider), so this
/// is a process-wide singleton that registers lazily and is safe to call into
/// from any screen.
class IntelliToggle {
  IntelliToggle._();
  static final IntelliToggle instance = IntelliToggle._();

  bool _registered = false;

  /// Whether the OAuth client-credentials were injected at build time.
  bool get isConfigured => AppConfig.hasIntelliToggle;

  /// Whether the provider has been registered with OpenFeature.
  bool get isReady => _registered;

  /// The active OpenFeature provider — only valid once [register] has run.
  FeatureProvider get provider => OpenFeatureAPI().provider;

  /// Register the IntelliToggle provider with OpenFeature (idempotent).
  ///
  /// [targeting] becomes the global evaluation context, so every flag is scored
  /// against the signed-in identity (we pass the DartStream user/tenant through,
  /// connecting the two SaaS products).
  Future<void> register({Map<String, dynamic>? targeting}) async {
    if (!isConfigured) {
      throw StateError(
        'IntelliToggle client-credentials are missing — supply '
        'INTELLITOGGLE_CLIENT_ID / _CLIENT_SECRET / _TENANT_ID via --dart-define.',
      );
    }
    if (!_registered) {
      final provider = IntelliToggleProvider(
        clientId: AppConfig.intelliToggleClientId,
        clientSecret: AppConfig.intelliToggleClientSecret,
        tenantId: AppConfig.intelliToggleTenantId,
        options: IntelliToggleOptions.production(
          baseUri: Uri.parse(AppConfig.intelliToggleApiUrl),
        ),
      );
      await OpenFeatureAPI().setProvider(provider);
      _registered = true;
    }
    if (targeting != null) {
      OpenFeatureAPI().setGlobalContext(OpenFeatureEvaluationContext(targeting));
    }
  }

  // ---- typed evaluation helpers -------------------------------------------
  // Each returns the full FlagEvaluationResult so callers can surface the
  // value *and* the reason / variant / error (house style: never hide errors).

  Future<FlagEvaluationResult<bool>> getBoolean(
    String flagKey, {
    bool defaultValue = false,
    Map<String, dynamic>? context,
  }) =>
      provider.getBooleanFlag(flagKey, defaultValue, context: context);

  Future<FlagEvaluationResult<String>> getString(
    String flagKey, {
    String defaultValue = '',
    Map<String, dynamic>? context,
  }) =>
      provider.getStringFlag(flagKey, defaultValue, context: context);

  Future<FlagEvaluationResult<int>> getInteger(
    String flagKey, {
    int defaultValue = 0,
    Map<String, dynamic>? context,
  }) =>
      provider.getIntegerFlag(flagKey, defaultValue, context: context);

  Future<FlagEvaluationResult<double>> getDouble(
    String flagKey, {
    double defaultValue = 0,
    Map<String, dynamic>? context,
  }) =>
      provider.getDoubleFlag(flagKey, defaultValue, context: context);

  Future<FlagEvaluationResult<Map<String, dynamic>>> getObject(
    String flagKey, {
    Map<String, dynamic> defaultValue = const {},
    Map<String, dynamic>? context,
  }) =>
      provider.getObjectFlag(flagKey, defaultValue, context: context);
}
