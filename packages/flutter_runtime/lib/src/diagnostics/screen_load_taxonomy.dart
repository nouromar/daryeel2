// Shared taxonomy for screen-load observability.
//
// Goal: standardize payloads so dashboards/alerts can rely on stable keys.
//
// Keep these stable: event names and wire values are a compatibility surface.

abstract final class ScreenLoadEventNames {
  /// Emitted once per screen load attempt, when the app has selected the final
  /// schema/theme (or decided to fall back).
  static const String summary = 'runtime.screen_load.summary';
}

/// Standard payload keys for `runtime.screen_load.summary`.
///
/// Prefer these keys over ad-hoc names. Additive changes are allowed.
abstract final class ScreenLoadSummaryKeys {
  static const String screenLoadId = 'screenLoadId';

  static const String finalSchemaSource = 'finalSchemaSource';
  static const String finalSchemaReasonCode = 'finalSchemaReasonCode';
  static const String schemaDocId = 'schemaDocId';
  static const String schemaBundleId = 'schemaBundleId';
  static const String schemaBundleVersion = 'schemaBundleVersion';
  static const String schemaFormatVersion = 'schemaFormatVersion';

  static const String parseErrorCount = 'parseErrorCount';
  static const String refErrorCount = 'refErrorCount';

  static const String usedRemoteTheme = 'usedRemoteTheme';
  static const String finalThemeSource = 'finalThemeSource';
  static const String themeDocId = 'themeDocId';

  static const String attemptCount = 'attemptCount';
  static const String fallbackCount = 'fallbackCount';
  static const String totalLoadMs = 'totalLoadMs';
}

enum ScreenLoadOutcome {
  /// Schema parsed and ref resolution completed without errors.
  success,

  /// The app showed UI, but with errors/degradation (e.g. ref errors).
  degraded,

  /// The app could not load any schema and would show a fatal error.
  /// (Not expected for production apps; prefer bundled fallback instead.)
  failed,
}

extension ScreenLoadOutcomeWire on ScreenLoadOutcome {
  String get wireValue {
    return switch (this) {
      ScreenLoadOutcome.success => 'success',
      ScreenLoadOutcome.degraded => 'degraded',
      ScreenLoadOutcome.failed => 'failed',
    };
  }
}
