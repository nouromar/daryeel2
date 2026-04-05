import 'dart:collection';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/diagnostics_sink.dart';
import 'security_budgets.dart';

/// A budget-violation record derived from a [DiagnosticEvent].
final class BudgetViolation {
  BudgetViolation({
    required this.timestamp,
    required this.eventName,
    required this.severity,
    required this.fingerprint,
    required this.budgetKey,
    required this.payload,
    required this.context,
  });

  final DateTime timestamp;
  final String eventName;
  final DiagnosticSeverity severity;
  final String fingerprint;

  /// Stable identifier for the violated budget.
  ///
  /// Examples:
  /// - `schema.max_json_bytes`
  /// - `schema.max_nodes`
  /// - `query.response_too_large`
  /// - `query.max_items`
  final String budgetKey;

  final Map<String, Object?> payload;
  final Map<String, Object?> context;
}

/// Collects and aggregates budget-related violations from diagnostics.
///
/// Intended usage:
///
/// ```dart
/// final audit = BudgetAuditSink();
/// final sink = MultiDiagnosticsSink([audit, RemoteDiagnosticsSink(...)])
/// final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);
///
/// // Later:
/// final report = audit.snapshot();
/// ```
final class BudgetAuditSink extends DiagnosticsSink {
  BudgetAuditSink(
      {int maxViolations = SecurityBudgets.maxInMemoryDiagnosticsEvents})
      : assert(maxViolations > 0),
        _maxViolations = maxViolations;

  final int _maxViolations;
  final List<BudgetViolation> _violations = <BudgetViolation>[];

  /// Count of violations by [BudgetViolation.budgetKey].
  final Map<String, int> _countsByBudgetKey = <String, int>{};

  /// Count of violations by event name.
  final Map<String, int> _countsByEventName = <String, int>{};

  @override
  void handle(DiagnosticEvent event) {
    final violation = _tryMapEvent(event);
    if (violation == null) return;

    _violations.add(violation);
    _countsByBudgetKey[violation.budgetKey] =
        (_countsByBudgetKey[violation.budgetKey] ?? 0) + 1;
    _countsByEventName[violation.eventName] =
        (_countsByEventName[violation.eventName] ?? 0) + 1;

    if (_violations.length > _maxViolations) {
      _violations.removeRange(0, _violations.length - _maxViolations);
    }
  }

  /// Returns a stable, immutable snapshot for auditing / inspector UI.
  BudgetAuditSnapshot snapshot() {
    return BudgetAuditSnapshot(
      violations: List<BudgetViolation>.unmodifiable(_violations),
      countsByBudgetKey: UnmodifiableMapView(_countsByBudgetKey),
      countsByEventName: UnmodifiableMapView(_countsByEventName),
    );
  }

  void clear() {
    _violations.clear();
    _countsByBudgetKey.clear();
    _countsByEventName.clear();
  }

  BudgetViolation? _tryMapEvent(DiagnosticEvent event) {
    // 1) Schema budgeting (explicit).
    if (event.eventName == 'runtime.schema.budget_exceeded') {
      final raw = event.payload['budgetName'];
      final budgetName =
          raw is String && raw.trim().isNotEmpty ? raw.trim() : 'unknown';
      return BudgetViolation(
        timestamp: event.timestamp,
        eventName: event.eventName,
        severity: event.severity,
        fingerprint: event.fingerprint,
        budgetKey: 'schema.$budgetName',
        payload: event.payload,
        context: event.context,
      );
    }

    // 2) Query store budgeting (encoded as a failure type).
    if (event.eventName == 'runtime.query.failed' ||
        event.eventName == 'runtime.query.paged.failed') {
      final raw = event.payload['errorType'];
      final errorType = raw is String ? raw.trim() : '';

      if (errorType == 'response_too_large') {
        return BudgetViolation(
          timestamp: event.timestamp,
          eventName: event.eventName,
          severity: event.severity,
          fingerprint: event.fingerprint,
          budgetKey: 'query.response_too_large',
          payload: event.payload,
          context: event.context,
        );
      }

      if (errorType == 'max_items') {
        return BudgetViolation(
          timestamp: event.timestamp,
          eventName: event.eventName,
          severity: event.severity,
          fingerprint: event.fingerprint,
          budgetKey: 'query.max_items',
          payload: event.payload,
          context: event.context,
        );
      }
    }

    // 3) Form/state store budgeting (explicit).
    if (event.eventName == 'runtime.form.budget_clamped' ||
        event.eventName == 'runtime.form.budget_rejected' ||
        event.eventName == 'runtime.state.budget_clamped' ||
        event.eventName == 'runtime.state.budget_rejected') {
      final raw = event.payload['budgetName'];
      final budgetName =
          raw is String && raw.trim().isNotEmpty ? raw.trim() : 'unknown';

      final prefix = event.eventName.startsWith('runtime.form.')
          ? 'form'
          : (event.eventName.startsWith('runtime.state.') ? 'state' : 'store');

      return BudgetViolation(
        timestamp: event.timestamp,
        eventName: event.eventName,
        severity: event.severity,
        fingerprint: event.fingerprint,
        budgetKey: '$prefix.$budgetName',
        payload: event.payload,
        context: event.context,
      );
    }

    return null;
  }
}

final class BudgetAuditSnapshot {
  const BudgetAuditSnapshot({
    required this.violations,
    required this.countsByBudgetKey,
    required this.countsByEventName,
  });

  final List<BudgetViolation> violations;
  final Map<String, int> countsByBudgetKey;
  final Map<String, int> countsByEventName;
}
