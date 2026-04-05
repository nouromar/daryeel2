import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SchemaFormStore clamps strings to maxStringLength', () {
    final store = SchemaFormStore(maxStringLength: 3);

    store.setFieldValue('f1', 'name', 'abcd');

    expect(store.getFieldValue('f1', 'name'), 'abc');
  });

  test('SchemaStateStore emits diagnostics on key reject', () {
    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: sink,
      config: const DiagnosticsConfig(enableDebug: true),
    );

    final store = SchemaStateStore(
      diagnostics: diagnostics,
      diagnosticsContext: const <String, Object?>{'test': true},
      maxKeys: 1,
    );

    store.setValue('a', '1');
    store.setValue('b', '2');

    expect(store.getValue('a'), '1');
    expect(store.getValue('b'), isNull);
    expect(
      sink.events.any(
        (e) =>
            e.eventName == 'runtime.state.budget_rejected' &&
            e.payload['budgetName'] == 'max_keys',
      ),
      isTrue,
    );
  });

  test('BudgetAuditSink captures store budget events', () {
    final audit = BudgetAuditSink(maxViolations: 10);

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.form.budget_clamped',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'f1',
        payload: const <String, Object?>{'budgetName': 'max_string_length'},
      ),
    );

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.state.budget_rejected',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 's1',
        payload: const <String, Object?>{'budgetName': 'max_keys'},
      ),
    );

    final snap = audit.snapshot();
    expect(snap.countsByBudgetKey['form.max_string_length'], 1);
    expect(snap.countsByBudgetKey['state.max_keys'], 1);
  });
}
