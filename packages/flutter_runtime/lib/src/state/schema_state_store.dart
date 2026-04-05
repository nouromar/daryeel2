import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';
import '../security/security_budgets.dart';

/// A simple, bounded screen-scoped state store for schema-driven UI.
///
/// This is intentionally conservative:
/// - keys are strings
/// - values are limited to primitives (String/num/bool/null)
/// - reactive reads are supported via stable per-key [ValueListenable]s
final class SchemaStateStore extends ChangeNotifier {
  SchemaStateStore({
    Map<String, Object?>? initial,
    this.maxKeys = SecurityBudgets.maxStateKeysPerScreen,
    this.maxStringLength = SecurityBudgets.maxStateStringLength,
    RuntimeDiagnostics? diagnostics,
    Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  }) {
    configureDiagnostics(
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
    );
    applyDefaults(initial);
  }

  RuntimeDiagnostics? _diagnostics;
  Map<String, Object?> _diagnosticsContext = const <String, Object?>{};

  RuntimeDiagnostics? get diagnostics => _diagnostics;
  Map<String, Object?> get diagnosticsContext => _diagnosticsContext;

  void configureDiagnostics({
    RuntimeDiagnostics? diagnostics,
    Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  }) {
    _diagnostics = diagnostics;
    _diagnosticsContext = diagnosticsContext;
  }

  final int maxKeys;
  final int maxStringLength;

  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, ValueNotifier<Object?>> _notifiers =
      <String, ValueNotifier<Object?>>{};

  Map<String, Object?> snapshotValues() {
    return Map<String, Object?>.unmodifiable(_values);
  }

  Object? getValue(String key) {
    if (key.isEmpty) return null;
    return _values[key];
  }

  /// Watches a single key for reactive bindings.
  ///
  /// Returns a stable [ValueListenable] per key.
  ValueListenable<Object?> watchValue(String key) {
    if (key.isEmpty) return ValueNotifier<Object?>(null);
    return _notifiers.putIfAbsent(
      key,
      () => ValueNotifier<Object?>(_values[key]),
    );
  }

  void setValue(String key, Object? value) {
    if (key.isEmpty) return;

    if (_values.length >= maxKeys && !_values.containsKey(key)) {
      _emitBudgetViolation(
        eventName: 'runtime.state.budget_rejected',
        severity: DiagnosticSeverity.warn,
        fingerprint: 'runtime.state.budget_rejected:budget=max_keys:key=$key',
        payload: <String, Object?>{
          'budgetName': 'max_keys',
          'limit': maxKeys,
          'stateKey': key,
        },
      );
      return;
    }

    final sanitized = _sanitizeValue(value, key: key);
    final current = _values[key];
    if (current == sanitized) return;

    _values[key] = sanitized;
    _notifiers[key]?.value = sanitized;
    notifyListeners();
  }

  void setValues(Map<String, Object?> patch) {
    if (patch.isEmpty) return;

    var changed = false;
    for (final entry in patch.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;

      if (_values.length >= maxKeys && !_values.containsKey(key)) {
        _emitBudgetViolation(
          eventName: 'runtime.state.budget_rejected',
          severity: DiagnosticSeverity.warn,
          fingerprint: 'runtime.state.budget_rejected:budget=max_keys:key=$key',
          payload: <String, Object?>{
            'budgetName': 'max_keys',
            'limit': maxKeys,
            'stateKey': key,
          },
        );
        continue;
      }

      final sanitized = _sanitizeValue(entry.value, key: key);
      final current = _values[key];
      if (current == sanitized) continue;

      _values[key] = sanitized;
      _notifiers[key]?.value = sanitized;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Applies defaults only for keys that are currently unset.
  void applyDefaults(Map<String, Object?>? defaults) {
    if (defaults == null || defaults.isEmpty) return;

    var changed = false;
    for (final entry in defaults.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;

      if (_values.containsKey(key)) continue;
      if (_values.length >= maxKeys) break;

      final sanitized = _sanitizeValue(entry.value, key: key);
      if (sanitized == null) continue;

      _values[key] = sanitized;
      _notifiers[key]?.value = sanitized;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  Object? _sanitizeValue(Object? value, {required String key}) {
    if (value == null) return null;

    if (value is String) {
      if (value.length <= maxStringLength) return value;
      _emitBudgetViolation(
        eventName: 'runtime.state.budget_clamped',
        severity: DiagnosticSeverity.warn,
        fingerprint:
            'runtime.state.budget_clamped:budget=max_string_length:key=$key',
        payload: <String, Object?>{
          'budgetName': 'max_string_length',
          'limit': maxStringLength,
          'actual': value.length,
          'stateKey': key,
        },
      );
      return value.substring(0, maxStringLength);
    }

    if (value is num || value is bool) return value;

    // Fail-closed: only allow primitives.
    _emitBudgetViolation(
      eventName: 'runtime.state.budget_clamped',
      severity: DiagnosticSeverity.warn,
      fingerprint: 'runtime.state.budget_clamped:budget=non_primitive:key=$key',
      payload: <String, Object?>{
        'budgetName': 'non_primitive',
        'stateKey': key,
        'valueType': value.runtimeType.toString(),
      },
    );
    return value.toString();
  }

  void _emitBudgetViolation({
    required String eventName,
    required DiagnosticSeverity severity,
    required String fingerprint,
    required Map<String, Object?> payload,
  }) {
    _diagnostics?.emit(
      DiagnosticEvent(
        eventName: eventName,
        severity: severity,
        kind: DiagnosticKind.diagnostic,
        fingerprint: fingerprint,
        context: _diagnosticsContext,
        payload: payload,
      ),
    );
  }

  @override
  void dispose() {
    for (final n in _notifiers.values) {
      n.dispose();
    }
    _notifiers.clear();
    super.dispose();
  }
}
