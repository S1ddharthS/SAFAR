import 'package:flutter/foundation.dart';

/// Compile-time configuration. Secrets are never placed in the client.
class Env {
  static const String _definedBaseUrl = String.fromEnvironment(
    'SAFAR_API_BASE_URL',
  );

  /// Dev defaults are explicit and local. A release build must supply the URL
  /// with `--dart-define=SAFAR_API_BASE_URL=https://...`.
  static String get apiBaseUrl {
    final raw = _definedBaseUrl.trim();
    if (raw.isNotEmpty) {
      return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    }
    if (kDebugMode) {
      // Port 8020 is the active SAFAR staging server.
      // Physical Android devices using `adb reverse tcp:8020 tcp:8020` (and ADB loopback)
      // connect to 127.0.0.1:8020.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        return 'http://127.0.0.1:8020';
      }
      return 'http://localhost:8020';
    }
    throw StateError(
      'SAFAR_API_BASE_URL was not provided. Release builds must be compiled '
      'with --dart-define=SAFAR_API_BASE_URL=https://your-api-host.',
    );
  }

  static const String _definedWebBaseUrl = String.fromEnvironment(
    'SAFAR_WEB_BASE_URL',
  );

  /// Origin of the web fallback that serves public companion pages such as
  /// `/companion/{token}`. Native app links are configured separately.
  static String? get webBaseUrl {
    final raw = _definedWebBaseUrl.trim();
    if (raw.isNotEmpty) {
      return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    }
    if (kDebugMode) return 'http://localhost:3000';
    return null;
  }

  static const String appName = 'SAFAR';
  static const String policyLabel = 'Private by default · group approved';
}
