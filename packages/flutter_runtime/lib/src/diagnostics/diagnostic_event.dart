import 'dart:collection';

/// Severity for diagnostic events.
enum DiagnosticSeverity {
  debug,
  info,
  warn,
  error,
  fatal,
}

/// The type of telemetry event.
enum DiagnosticKind {
  diagnostic,
  metric,
  trace,
}

/// A structured diagnostic/telemetry event.
///
/// NOTE: Keep payload/context PII-free by design. This library does not attempt
/// to redact arbitrary strings.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.eventName,
    required this.severity,
    required this.kind,
    required this.fingerprint,
    Map<String, Object?> context = const {},
    Map<String, Object?> payload = const {},
    DateTime? timestamp,
    this.eventSchemaVersion = 1,
  })  : timestamp = (timestamp ?? DateTime.now()).toUtc(),
        context = UnmodifiableMapView(context),
        payload = UnmodifiableMapView(payload);

  final int eventSchemaVersion;
  final String eventName;
  final DiagnosticSeverity severity;
  final DiagnosticKind kind;

  /// Stable identifier used for de-duplication.
  ///
  /// Must not contain PII.
  final String fingerprint;

  /// Standard runtime context (app/session/schema/theme/flags/etc).
  final Map<String, Object?> context;

  /// Event-specific fields.
  final Map<String, Object?> payload;

  final DateTime timestamp;
}
