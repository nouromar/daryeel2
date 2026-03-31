import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _CollectingSink extends DiagnosticsSink {
  _CollectingSink();

  final List<DiagnosticEvent> events = <DiagnosticEvent>[];

  @override
  void handle(DiagnosticEvent event) {
    events.add(event);
  }
}

DiagnosticEvent _event({
  required String name,
  required DiagnosticSeverity severity,
  required String fingerprint,
}) {
  return DiagnosticEvent(
    eventName: name,
    severity: severity,
    kind: DiagnosticKind.diagnostic,
    fingerprint: fingerprint,
    context: const {
      'app': {'appId': 'customer-app'}
    },
  );
}

void main() {
  test('BudgetedRuntimeDiagnostics forwards first event', () {
    final sink = _CollectingSink();
    final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);

    diagnostics.emit(
      _event(
        name: 'runtime.schema.activated',
        severity: DiagnosticSeverity.info,
        fingerprint: 'runtime.schema.activated:screen=home',
      ),
    );

    expect(sink.events, hasLength(1));
    expect(sink.events.single.eventName, 'runtime.schema.activated');
  });

  test('BudgetedRuntimeDiagnostics dedupes by fingerprint within TTL', () {
    final sink = _CollectingSink();
    var now = DateTime.utc(2026, 03, 31, 12, 00, 00);

    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: sink,
      config: const DiagnosticsConfig(dedupeTtl: Duration(seconds: 60)),
      now: () => now,
    );

    final event = _event(
      name: 'runtime.action.dispatch_failed',
      severity: DiagnosticSeverity.error,
      fingerprint: 'runtime.action.dispatch_failed:navigate:route_missing:x',
    );

    diagnostics.emit(event);
    diagnostics.emit(event);

    expect(sink.events, hasLength(1));
    expect(diagnostics.stats.suppressedByFingerprint[event.fingerprint], 1);

    now = now.add(const Duration(seconds: 61));
    diagnostics.emit(event);

    expect(sink.events, hasLength(2));
  });

  test('BudgetedRuntimeDiagnostics enforces info budget', () {
    final sink = _CollectingSink();
    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: sink,
      config: const DiagnosticsConfig(maxInfoPerSession: 1),
    );

    diagnostics.emit(
      _event(
        name: 'app.lifecycle.session_started',
        severity: DiagnosticSeverity.info,
        fingerprint: 'app.lifecycle.session_started',
      ),
    );

    diagnostics.emit(
      _event(
        name: 'app.lifecycle.session_started',
        severity: DiagnosticSeverity.info,
        fingerprint: 'app.lifecycle.session_started_2',
      ),
    );

    expect(sink.events, hasLength(1));
    expect(diagnostics.stats.suppressedBySeverity[DiagnosticSeverity.info], 1);
  });

  test('BudgetedRuntimeDiagnostics suppresses debug when disabled', () {
    final sink = _CollectingSink();
    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: sink,
      config: const DiagnosticsConfig(enableDebug: false),
    );

    diagnostics.emit(
      _event(
        name: 'runtime.schema.fetch_started',
        severity: DiagnosticSeverity.debug,
        fingerprint: 'runtime.schema.fetch_started',
      ),
    );

    expect(sink.events, isEmpty);
    expect(diagnostics.stats.suppressedBySeverity[DiagnosticSeverity.debug], 1);
  });

  test('InMemoryDiagnosticsSink stores last N events', () {
    final sink = InMemoryDiagnosticsSink(maxEvents: 2);

    sink.handle(
      _event(
        name: 'e1',
        severity: DiagnosticSeverity.info,
        fingerprint: 'e1',
      ),
    );
    sink.handle(
      _event(
        name: 'e2',
        severity: DiagnosticSeverity.info,
        fingerprint: 'e2',
      ),
    );
    sink.handle(
      _event(
        name: 'e3',
        severity: DiagnosticSeverity.info,
        fingerprint: 'e3',
      ),
    );

    expect(sink.events, hasLength(2));
    expect(sink.events.first.eventName, 'e2');
    expect(sink.events.last.eventName, 'e3');
  });
}
