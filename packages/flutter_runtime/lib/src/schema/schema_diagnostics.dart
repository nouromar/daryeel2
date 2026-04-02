import 'dart:convert';

import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';
import '../security/security_budgets.dart';

int _countNodes(SchemaNode node) {
  if (node is RefNode) return 1;
  if (node is ComponentNode) {
    var total = 1;
    for (final children in node.slots.values) {
      for (final child in children) {
        total += _countNodes(child);
      }
    }
    return total;
  }
  return 0;
}

SchemaParseResult<ScreenSchema> _budgetExceededResult({
  required String message,
}) {
  return SchemaParseResult(
    value: null,
    errors: <SchemaParseError>[SchemaParseError(path: r'$', message: message)],
  );
}

SchemaParseResult<ScreenSchema> parseScreenSchemaWithDiagnostics(
  Map<String, Object?> document, {
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  int maxErrors = 5,
  int maxJsonBytes = SecurityBudgets.maxSchemaJsonBytes,
  int maxNodes = SecurityBudgets.maxNodesPerDocument,
}) {
  // Hard budget: JSON bytes (fail closed).
  try {
    final bytes = utf8.encode(jsonEncode(document)).length;
    if (bytes > maxJsonBytes) {
      diagnostics?.emit(
        DiagnosticEvent(
          eventName: 'runtime.schema.budget_exceeded',
          severity: DiagnosticSeverity.error,
          kind: DiagnosticKind.diagnostic,
          fingerprint:
              'runtime.schema.budget_exceeded:budget=max_json_bytes:id=${document['id'] ?? 'unknown'}',
          context: diagnosticsContext,
          payload: <String, Object?>{
            'budgetName': 'max_json_bytes',
            'limit': maxJsonBytes,
            'actual': bytes,
          },
        ),
      );

      return _budgetExceededResult(
        message: 'Exceeded maxJsonBytes=$maxJsonBytes',
      );
    }
  } catch (_) {
    // If we cannot measure, continue to parsing; parsing errors will be emitted.
  }

  final parsed = parseScreenSchema(document);

  // Hard budget: node count (fail closed).
  final screen = parsed.value;
  if (screen != null && parsed.errors.isEmpty) {
    final nodeCount = _countNodes(screen.root);
    if (nodeCount > maxNodes) {
      diagnostics?.emit(
        DiagnosticEvent(
          eventName: 'runtime.schema.budget_exceeded',
          severity: DiagnosticSeverity.error,
          kind: DiagnosticKind.diagnostic,
          fingerprint:
              'runtime.schema.budget_exceeded:budget=max_nodes:screen=${screen.id}',
          context: diagnosticsContext,
          payload: <String, Object?>{
            'budgetName': 'max_nodes',
            'limit': maxNodes,
            'actual': nodeCount,
            'screenId': screen.id,
          },
        ),
      );

      return _budgetExceededResult(
        message: 'Exceeded maxNodes=$maxNodes',
      );
    }

    return parsed;
  }

  if (diagnostics != null) {
    final errors = parsed.errors
        .take(maxErrors)
        .map(
          (e) => <String, Object?>{
            'path': e.path,
            'message': e.message,
          },
        )
        .toList(growable: false);

    diagnostics.emit(
      DiagnosticEvent(
        eventName: 'runtime.schema.parse_failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.schema.parse_failed:id=${document['id'] ?? 'unknown'}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'errorCount': parsed.errors.length,
          'errors': errors,
        },
      ),
    );
  }

  return parsed;
}

Future<RefResolutionResult> resolveScreenRefsWithDiagnostics({
  required ScreenSchema schema,
  required FragmentDocumentLoader loader,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  int maxErrors = 5,
  int maxDepth = SecurityBudgets.maxRefDepth,
  int maxFragments = SecurityBudgets.maxFragmentsPerScreen,
}) async {
  final resolved = await resolveScreenRefs(
    schema: schema,
    loader: loader,
    maxDepth: maxDepth,
    maxFragments: maxFragments,
  );

  if (resolved.errors.isEmpty) {
    return resolved;
  }

  if (diagnostics != null) {
    final errors = resolved.errors
        .take(maxErrors)
        .map(
          (e) => <String, Object?>{
            'path': e.path,
            'ref': e.ref,
            'message': e.message,
          },
        )
        .toList(growable: false);

    diagnostics.emit(
      DiagnosticEvent(
        eventName: 'runtime.schema.ref_resolution_failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.schema.ref_resolution_failed:screen=${schema.id}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'errorCount': resolved.errors.length,
          'errors': errors,
        },
      ),
    );
  }

  return resolved;
}
