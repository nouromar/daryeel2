import 'package:flutter/widgets.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';
import '../bindings/schema_expression_engine.dart';

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
  BuildContext? buildContext,
}) {
  if (visibleWhen == null || visibleWhen.isEmpty) return true;

  final unknownKeys = visibleWhen.keys
      .where((k) => k != 'featureFlag' && k != 'expr')
      .toList()
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
  var featureFlagVisible = true;
  if (featureFlag is String) {
    if (featureFlag.isEmpty) {
      featureFlagVisible = true;
    } else {
      featureFlagVisible = context.enabledFeatureFlags.contains(featureFlag);
    }
  } else if (featureFlag is List) {
    final flags = featureFlag.whereType<String>().where((f) => f.isNotEmpty);
    if (flags.isEmpty) {
      featureFlagVisible = true;
    } else {
      featureFlagVisible = flags.any(context.enabledFeatureFlags.contains);
    }
  } else if (visibleWhen.containsKey('featureFlag') && featureFlag != null) {
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

  var exprVisible = true;
  final exprRaw = visibleWhen['expr'];
  if (exprRaw is String) {
    final trimmed = exprRaw.trim();
    if (trimmed.isNotEmpty) {
      if (buildContext == null) {
        diagnostics?.emit(
          DiagnosticEvent(
            eventName: 'runtime.visibility.evaluation_failed',
            severity: DiagnosticSeverity.warn,
            kind: DiagnosticKind.diagnostic,
            fingerprint: 'runtime.visibility.evaluation_failed:expr_no_context',
            context: diagnosticsContext,
            payload: <String, Object?>{
              if (nodeType != null) 'nodeType': nodeType,
              'reason': 'missing_build_context',
            },
          ),
        );
      } else {
        String normalize(String raw) {
          final t = raw.trim();
          if (t.startsWith(r'${') && t.endsWith('}')) {
            final inner = t.substring(2, t.length - 1).trim();
            return inner;
          }
          return t;
        }

        try {
          final normalized = normalize(trimmed);
          if (normalized.isNotEmpty) {
            final result = evaluateSchemaExpression(normalized, buildContext);
            if (result is bool) {
              exprVisible = result;
            } else {
              diagnostics?.emit(
                DiagnosticEvent(
                  eventName: 'runtime.visibility.evaluation_failed',
                  severity: DiagnosticSeverity.warn,
                  kind: DiagnosticKind.diagnostic,
                  fingerprint: 'runtime.visibility.evaluation_failed:expr_type',
                  context: diagnosticsContext,
                  payload: <String, Object?>{
                    if (nodeType != null) 'nodeType': nodeType,
                    'exprResultType': result?.runtimeType.toString(),
                  },
                ),
              );
            }
          }
        } catch (_) {
          diagnostics?.emit(
            DiagnosticEvent(
              eventName: 'runtime.visibility.evaluation_failed',
              severity: DiagnosticSeverity.warn,
              kind: DiagnosticKind.diagnostic,
              fingerprint:
                  'runtime.visibility.evaluation_failed:expr_exception',
              context: diagnosticsContext,
              payload: <String, Object?>{
                if (nodeType != null) 'nodeType': nodeType,
              },
            ),
          );
        }
      }
    }
  } else if (visibleWhen.containsKey('expr') && exprRaw != null) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.visibility.evaluation_failed',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.visibility.evaluation_failed:expr',
        context: diagnosticsContext,
        payload: <String, Object?>{
          if (nodeType != null) 'nodeType': nodeType,
          'exprType': exprRaw.runtimeType.toString(),
        },
      ),
    );
  }

  return featureFlagVisible && exprVisible;
}
