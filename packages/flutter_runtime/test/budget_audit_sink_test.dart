import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BudgetAuditSink records schema budget exceeded', () {
    final audit = BudgetAuditSink(maxViolations: 10);

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.schema.budget_exceeded',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'fp1',
        payload: const <String, Object?>{
          'budgetName': 'max_nodes',
          'limit': 3,
          'actual': 10,
        },
      ),
    );

    final snap = audit.snapshot();
    expect(snap.violations, hasLength(1));
    expect(snap.violations.first.budgetKey, 'schema.max_nodes');
    expect(snap.countsByBudgetKey['schema.max_nodes'], 1);
    expect(snap.countsByEventName['runtime.schema.budget_exceeded'], 1);
  });

  test('BudgetAuditSink records query budget failures', () {
    final audit = BudgetAuditSink(maxViolations: 10);

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.query.failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'fp2',
        payload: const <String, Object?>{
          'errorType': 'response_too_large',
          'maxResponseBytes': 100,
          'actualBytes': 101,
        },
      ),
    );

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.query.paged.failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'fp3',
        payload: const <String, Object?>{
          'errorType': 'max_items',
          'maxItems': 1000,
        },
      ),
    );

    final snap = audit.snapshot();
    expect(snap.violations, hasLength(2));
    expect(snap.countsByBudgetKey['query.response_too_large'], 1);
    expect(snap.countsByBudgetKey['query.max_items'], 1);
  });

  test('BudgetAuditSink ignores non-budget events', () {
    final audit = BudgetAuditSink(maxViolations: 10);

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.query.success',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'fp4',
      ),
    );

    expect(audit.snapshot().violations, isEmpty);
  });

  test('BudgetAuditSink caps stored violations', () {
    final audit = BudgetAuditSink(maxViolations: 2);

    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.schema.budget_exceeded',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'a',
        payload: const <String, Object?>{'budgetName': 'max_json_bytes'},
      ),
    );
    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.schema.budget_exceeded',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'b',
        payload: const <String, Object?>{'budgetName': 'max_nodes'},
      ),
    );
    audit.handle(
      DiagnosticEvent(
        eventName: 'runtime.query.failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'c',
        payload: const <String, Object?>{'errorType': 'response_too_large'},
      ),
    );

    final snap = audit.snapshot();
    expect(snap.violations, hasLength(2));
    expect(snap.violations.first.fingerprint, 'b');
    expect(snap.violations.last.fingerprint, 'c');
  });
}
