import 'diagnostic_event.dart';
import 'diagnostics_sink.dart';

class DiagnosticsConfig {
  const DiagnosticsConfig({
    this.enableDebug = false,
    this.dedupeTtl = const Duration(seconds: 60),
    this.maxInfoPerSession = 30,
    this.maxWarnPerSession = 50,
  });

  final bool enableDebug;
  final Duration dedupeTtl;

  /// Maximum number of emitted `info` events per session.
  final int maxInfoPerSession;

  /// Maximum number of emitted `warn` events per session.
  final int maxWarnPerSession;
}

class DiagnosticsStats {
  const DiagnosticsStats({
    required this.emittedBySeverity,
    required this.suppressedBySeverity,
    required this.suppressedByFingerprint,
  });

  final Map<DiagnosticSeverity, int> emittedBySeverity;
  final Map<DiagnosticSeverity, int> suppressedBySeverity;

  /// Count of suppressions per fingerprint (dedupe or budget).
  final Map<String, int> suppressedByFingerprint;
}

abstract class RuntimeDiagnostics {
  const RuntimeDiagnostics();

  void emit(DiagnosticEvent event);

  DiagnosticsStats get stats;
}

/// A `RuntimeDiagnostics` implementation that enforces:
/// - debug enablement
/// - per-severity budgets (info/warn)
/// - TTL-based de-duplication by fingerprint
class BudgetedRuntimeDiagnostics extends RuntimeDiagnostics {
  BudgetedRuntimeDiagnostics({
    required DiagnosticsSink sink,
    DiagnosticsConfig config = const DiagnosticsConfig(),
    DateTime Function()? now,
  })  : _sink = sink,
        _config = config,
        _now = now ?? (() => DateTime.now().toUtc());

  final DiagnosticsSink _sink;
  final DiagnosticsConfig _config;
  final DateTime Function() _now;

  final Map<String, DateTime> _lastEmittedByFingerprint = <String, DateTime>{};
  final Map<DiagnosticSeverity, int> _emittedBySeverity =
      <DiagnosticSeverity, int>{};
  final Map<DiagnosticSeverity, int> _suppressedBySeverity =
      <DiagnosticSeverity, int>{};
  final Map<String, int> _suppressedByFingerprint = <String, int>{};

  @override
  DiagnosticsStats get stats => DiagnosticsStats(
        emittedBySeverity: Map.unmodifiable(_emittedBySeverity),
        suppressedBySeverity: Map.unmodifiable(_suppressedBySeverity),
        suppressedByFingerprint: Map.unmodifiable(_suppressedByFingerprint),
      );

  @override
  void emit(DiagnosticEvent event) {
    if (event.fingerprint.isEmpty) {
      // No stable fingerprint => cannot dedupe safely, and tends to spam.
      // Treat as programmer error.
      throw ArgumentError.value(
          event.fingerprint, 'event.fingerprint', 'Must be non-empty');
    }

    if (event.severity == DiagnosticSeverity.debug && !_config.enableDebug) {
      _suppress(event);
      return;
    }

    if (_isDuplicate(event)) {
      _suppress(event);
      return;
    }

    if (!_withinBudget(event)) {
      _suppress(event);
      return;
    }

    _recordEmitted(event);
    _sink.handle(event);
  }

  bool _isDuplicate(DiagnosticEvent event) {
    final last = _lastEmittedByFingerprint[event.fingerprint];
    if (last == null) return false;
    return _now().difference(last) <= _config.dedupeTtl;
  }

  bool _withinBudget(DiagnosticEvent event) {
    // error/fatal are always allowed (still deduped).
    if (event.severity == DiagnosticSeverity.error ||
        event.severity == DiagnosticSeverity.fatal) {
      return true;
    }

    final emitted = _emittedBySeverity[event.severity] ?? 0;
    switch (event.severity) {
      case DiagnosticSeverity.debug:
        // Only gated by enableDebug; no per-session budget.
        return true;
      case DiagnosticSeverity.info:
        return emitted < _config.maxInfoPerSession;
      case DiagnosticSeverity.warn:
        return emitted < _config.maxWarnPerSession;
      case DiagnosticSeverity.error:
      case DiagnosticSeverity.fatal:
        return true;
    }
  }

  void _recordEmitted(DiagnosticEvent event) {
    _lastEmittedByFingerprint[event.fingerprint] = _now();
    _emittedBySeverity[event.severity] =
        (_emittedBySeverity[event.severity] ?? 0) + 1;
  }

  void _suppress(DiagnosticEvent event) {
    _suppressedBySeverity[event.severity] =
        (_suppressedBySeverity[event.severity] ?? 0) + 1;
    _suppressedByFingerprint[event.fingerprint] =
        (_suppressedByFingerprint[event.fingerprint] ?? 0) + 1;
  }
}
