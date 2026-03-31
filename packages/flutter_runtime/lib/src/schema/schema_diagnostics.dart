import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';

SchemaParseResult<ScreenSchema> parseScreenSchemaWithDiagnostics(
  Map<String, Object?> document, {
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  int maxErrors = 5,
}) {
  final parsed = parseScreenSchema(document);
  if (parsed.value != null && parsed.errors.isEmpty) {
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
  int maxDepth = 32,
}) async {
  final resolved = await resolveScreenRefs(
    schema: schema,
    loader: loader,
    maxDepth: maxDepth,
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
