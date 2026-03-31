import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';

class SchemaVisibilityContext {
  const SchemaVisibilityContext({
    this.enabledFeatureFlags = const <String>{},
    this.service,
    this.role,
    this.state = const <String, Object?>{},
  });

  final Set<String> enabledFeatureFlags;
  final String? service;
  final String? role;
  final Map<String, Object?> state;
}

/// Evaluates v1 `visibleWhen` rules.
///
/// Per `docs/schema_format_v1.md`, v1 keeps conditionals narrow.
/// Today the only concrete, documented key is:
/// - `featureFlag`: string (or list of strings)
///
/// Unknown keys default to "visible" to avoid accidental content loss.
bool evaluateVisibleWhen(
  Map<String, Object?>? visibleWhen,
  SchemaVisibilityContext context, {
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  String? nodeType,
}) {
  if (visibleWhen == null || visibleWhen.isEmpty) return true;

  final unknownKeys = visibleWhen.keys.where((k) => k != 'featureFlag').toList()
    ..sort();
  if (unknownKeys.isNotEmpty) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.visibility.unknown_rule_key',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.visibility.unknown_rule_key:${unknownKeys.join(',')}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          if (nodeType != null) 'nodeType': nodeType,
          'unknownKeys': unknownKeys,
        },
      ),
    );
  }

  final featureFlag = visibleWhen['featureFlag'];
  if (featureFlag is String) {
    if (featureFlag.isEmpty) return true;
    return context.enabledFeatureFlags.contains(featureFlag);
  }

  if (featureFlag is List) {
    final flags = featureFlag.whereType<String>().where((f) => f.isNotEmpty);
    if (flags.isEmpty) return true;
    return flags.any(context.enabledFeatureFlags.contains);
  }

  if (visibleWhen.containsKey('featureFlag') && featureFlag != null) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.visibility.evaluation_failed',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.visibility.evaluation_failed:featureFlag',
        context: diagnosticsContext,
        payload: <String, Object?>{
          if (nodeType != null) 'nodeType': nodeType,
          'featureFlagType': featureFlag.runtimeType.toString(),
        },
      ),
    );
  }

  return true;
}
