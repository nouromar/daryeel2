import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_runtime/src/diagnostics/diagnostic_event.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestDiagnostics extends RuntimeDiagnostics {
  final events = <DiagnosticEvent>[];

  @override
  void emit(DiagnosticEvent event) {
    events.add(event);
  }

  @override
  DiagnosticsStats get stats => const DiagnosticsStats(
        emittedBySeverity: <DiagnosticSeverity, int>{},
        suppressedBySeverity: <DiagnosticSeverity, int>{},
        suppressedByFingerprint: <String, int>{},
      );
}

class _StaticSchemaLoader implements SchemaLoader {
  _StaticSchemaLoader(this.bundle);

  final SchemaBundle bundle;

  @override
  Future<SchemaBundle> loadScreen(RuntimeScreenRequest request) async {
    return bundle;
  }
}

class _RejectAllCompatibilityChecker implements SchemaCompatibilityChecker {
  const _RejectAllCompatibilityChecker({required this.reason});

  final String reason;

  @override
  CompatibilityResult check(Map<String, Object?> document) {
    return CompatibilityResult(isSupported: false, reason: reason);
  }
}

void main() {
  test('SchemaRuntime.load returns incompatible result (no throw)', () async {
    final diagnostics = _TestDiagnostics();

    const bundle = SchemaBundle(
      schemaId: 'customer_home',
      schemaVersion: '999.0',
      document: <String, Object?>{
        'schemaVersion': '999.0',
        'id': 'customer_home',
        'documentType': 'screen',
        'product': 'customer_app',
        'themeId': 'customer-default',
        'root': <String, Object?>{'type': 'Text'},
      },
    );

    final runtime = SchemaRuntime(
      loader: _StaticSchemaLoader(bundle),
      compatibilityChecker: const _RejectAllCompatibilityChecker(
        reason: 'Unsupported schema version: 999.0',
      ),
      diagnostics: diagnostics,
      diagnosticsContext: const <String, Object?>{'test': true},
    );

    final result = await runtime.load(
      const RuntimeScreenRequest(
        screenId: 'customer_home',
        product: 'customer_app',
      ),
    );

    expect(result.isSupported, isFalse);
    expect(result.bundle.schemaId, equals('customer_home'));
    expect(
      result.incompatibilityReason,
      contains('Unsupported schema version'),
    );

    final eventNames = diagnostics.events.map((e) => e.eventName).toList();
    expect(eventNames, contains('runtime.schema.compatibility_failed'));
    expect(eventNames, isNot(contains('runtime.schema.activated')));
  });
}
