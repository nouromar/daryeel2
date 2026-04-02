import 'package:flutter_runtime/flutter_runtime.dart';

/// Default `track_event` handler for the customer app.
///
/// This implementation records a best-effort, PII-safe metric event into the
/// existing diagnostics pipeline.
class DiagnosticsTrackEventHandler extends TrackEventHandler {
  const DiagnosticsTrackEventHandler({
    required this.diagnostics,
    required this.diagnosticsContext,
  });

  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;

  @override
  Future<void> trackEvent(
    String eventName, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.analytics.track_event',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint: 'runtime.analytics.track_event:$eventName',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'eventName': eventName,
          'propertyCount': properties.length,
          // Keys are typically low-risk and low-cardinality; avoid logging values.
          'propertyKeys': properties.keys.toList(growable: false),
        },
      ),
    );
  }
}
