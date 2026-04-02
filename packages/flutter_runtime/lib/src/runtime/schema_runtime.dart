import 'runtime_models.dart';
import 'schema_compatibility.dart';
import 'schema_loader.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';

class SchemaRuntime {
  const SchemaRuntime({
    required this.loader,
    required this.compatibilityChecker,
    this.diagnostics,
    this.diagnosticsContext = const <String, Object?>{},
  });

  final SchemaLoader loader;
  final SchemaCompatibilityChecker compatibilityChecker;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;

  Future<SchemaRuntimeLoadResult> load(RuntimeScreenRequest request) async {
    SchemaBundle bundle;
    try {
      bundle = await loader.loadScreen(request);
    } catch (error) {
      diagnostics?.emit(
        DiagnosticEvent(
          eventName: 'runtime.schema.load_failed',
          severity: DiagnosticSeverity.error,
          kind: DiagnosticKind.diagnostic,
          fingerprint:
              'runtime.schema.load_failed:${request.product}:${request.screenId}:${request.service ?? 'none'}',
          context: diagnosticsContext,
          payload: <String, Object?>{
            'product': request.product,
            'screenId': request.screenId,
            if (request.service != null) 'service': request.service,
            'errorType': error.runtimeType.toString(),
          },
        ),
      );
      rethrow;
    }

    final compatibility = compatibilityChecker.check(bundle.document);
    if (!compatibility.isSupported) {
      diagnostics?.emit(
        DiagnosticEvent(
          eventName: 'runtime.schema.compatibility_failed',
          severity: DiagnosticSeverity.error,
          kind: DiagnosticKind.diagnostic,
          fingerprint:
              'runtime.schema.compatibility_failed:${bundle.schemaId}:${bundle.schemaVersion}',
          context: diagnosticsContext,
          payload: <String, Object?>{
            'schemaId': bundle.schemaId,
            'schemaVersion': bundle.schemaVersion,
            if (compatibility.reason != null) 'reason': compatibility.reason,
          },
        ),
      );
      return SchemaRuntimeLoadResult.incompatible(
        bundle: bundle,
        incompatibilityReason:
            compatibility.reason ?? 'Unsupported schema bundle',
      );
    }

    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.schema.activated',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.schema.activated:${bundle.schemaId}:${bundle.schemaVersion}:${request.product}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'schemaId': bundle.schemaId,
          'schemaVersion': bundle.schemaVersion,
          'product': request.product,
          'screenId': request.screenId,
          if (request.service != null) 'service': request.service,
        },
      ),
    );

    return SchemaRuntimeLoadResult.supported(bundle: bundle);
  }
}

final class SchemaRuntimeLoadResult {
  const SchemaRuntimeLoadResult._({
    required this.isSupported,
    required this.bundle,
    required this.incompatibilityReason,
  });

  const SchemaRuntimeLoadResult.supported({required SchemaBundle bundle})
      : this._(isSupported: true, bundle: bundle, incompatibilityReason: null);

  const SchemaRuntimeLoadResult.incompatible({
    required SchemaBundle bundle,
    required String incompatibilityReason,
  }) : this._(
          isSupported: false,
          bundle: bundle,
          incompatibilityReason: incompatibilityReason,
        );

  final bool isSupported;
  final SchemaBundle bundle;
  final String? incompatibilityReason;
}
