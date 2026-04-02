import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

/// Default `submit_form` handler.
///
/// This is intentionally non-networking for now:
/// - emits a PII-safe diagnostic metric
/// - returns success
class DiagnosticsSubmitFormHandler extends SubmitFormHandler {
  const DiagnosticsSubmitFormHandler({
    required this.diagnostics,
    required this.diagnosticsContext,
  });

  final RuntimeDiagnostics diagnostics;
  final Map<String, Object?> diagnosticsContext;

  @override
  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  ) async {
    // Never log raw values. Only log counts/keys.
    final keys = request.values.keys.toList(growable: false);

    diagnostics.emit(
      DiagnosticEvent(
        eventName: 'runtime.form.submit',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint: 'runtime.form.submit:${request.formId}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'formId': request.formId,
          'fieldCount': keys.length,
          'fieldKeys': keys.take(20).toList(growable: false),
        },
      ),
    );

    return const SubmitFormResponse(ok: true);
  }
}
