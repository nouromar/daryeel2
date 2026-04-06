import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';
import '../data/schema_data_scope.dart';
import '../security/security_budgets.dart';

/// A simple, bounded screen-scoped state store for schema-driven UI.
///
/// Values are JSON-like (decoded `Map`/`List` + primitives) with strict budgets.
/// Reactive reads are supported via stable per-path [ValueListenable]s.
final class SchemaStateStore extends ChangeNotifier {
  SchemaStateStore({
    Map<String, Object?>? initial,
    this.maxKeys = SecurityBudgets.maxStateKeysPerScreen,
    this.maxStringLength = SecurityBudgets.maxStateStringLength,
    this.maxJsonDepth = SecurityBudgets.maxStateJsonDepth,
    this.maxJsonNodes = SecurityBudgets.maxStateJsonNodes,
    this.maxJsonEntriesPerMap = SecurityBudgets.maxStateJsonEntriesPerMap,
    this.maxJsonItemsPerList = SecurityBudgets.maxStateJsonItemsPerList,
    this.maxJsonKeyLength = SecurityBudgets.maxStateJsonKeyLength,
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

  final int maxJsonDepth;
  final int maxJsonNodes;
  final int maxJsonEntriesPerMap;
  final int maxJsonItemsPerList;
  final int maxJsonKeyLength;

  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, ValueNotifier<Object?>> _notifiers =
      <String, ValueNotifier<Object?>>{};

  Map<String, Object?> snapshotValues() {
    return Map<String, Object?>.unmodifiable(_values);
  }

  Object? getValue(String key) {
    if (key.isEmpty) return null;

    // Treat `key` as a dotted JSON path rooted at `$state`.
    final v = readJsonPath(_values, key);
    if (v != null) return v;

    // Back-compat: allow top-level direct keys.
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

    final rootKey = _rootKeyForPath(key);
    if (rootKey == null) return;

    if (_values.length >= maxKeys && !_values.containsKey(rootKey)) {
      _emitBudgetViolation(
        eventName: 'runtime.state.budget_rejected',
        severity: DiagnosticSeverity.warn,
        fingerprint:
            'runtime.state.budget_rejected:budget=max_keys:key=$rootKey',
        payload: <String, Object?>{
          'budgetName': 'max_keys',
          'limit': maxKeys,
          'stateKey': rootKey,
        },
      );
      return;
    }

    final sanitized = _sanitizeValue(value, key: key);
    if (!_setPath(key, sanitized)) return;

    _syncNotifiers();
    notifyListeners();
  }

  void setValues(Map<String, Object?> patch) {
    if (patch.isEmpty) return;

    var changed = false;
    for (final entry in patch.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;

      final rootKey = _rootKeyForPath(key);
      if (rootKey == null) continue;

      if (_values.length >= maxKeys && !_values.containsKey(rootKey)) {
        _emitBudgetViolation(
          eventName: 'runtime.state.budget_rejected',
          severity: DiagnosticSeverity.warn,
          fingerprint:
              'runtime.state.budget_rejected:budget=max_keys:key=$rootKey',
          payload: <String, Object?>{
            'budgetName': 'max_keys',
            'limit': maxKeys,
            'stateKey': rootKey,
          },
        );
        continue;
      }

      final sanitized = _sanitizeValue(entry.value, key: key);
      if (_setPath(key, sanitized)) {
        changed = true;
      }
    }

    if (changed) {
      _syncNotifiers();
      notifyListeners();
    }
  }

  /// Removes the value at [key] (treated as a dotted JSON path).
  ///
  /// Returns `true` if a value was removed.
  bool removeValue(String key) {
    if (key.isEmpty) return false;
    final removed = _removePath(key);
    if (!removed) return false;
    _syncNotifiers();
    notifyListeners();
    return true;
  }

  /// Increments the numeric value at [key] by [by].
  ///
  /// If missing, treats the current value as 0.
  /// If non-numeric, this is a no-op.
  bool incrementValue(String key, num by) {
    if (key.isEmpty) return false;
    final current = getValue(key);
    if (current == null) {
      setValue(key, by);
      return true;
    }
    if (current is! num) return false;
    setValue(key, current + by);
    return true;
  }

  /// Appends [value] to the list at [key].
  ///
  /// If missing, creates a new list containing [value].
  /// If the current value is not a list, this is a no-op.
  bool appendValue(String key, Object? value) {
    if (key.isEmpty) return false;
    final current = getValue(key);
    final sanitized = _sanitizeValue(value, key: key);
    if (current == null) {
      setValue(key, <Object?>[sanitized]);
      return true;
    }
    if (current is! List) return false;
    if (current.length >= maxJsonItemsPerList) {
      _emitBudgetViolation(
        eventName: 'runtime.state.budget_rejected',
        severity: DiagnosticSeverity.warn,
        fingerprint:
            'runtime.state.budget_rejected:budget=max_json_items_per_list:key=$key',
        payload: <String, Object?>{
          'budgetName': 'max_json_items_per_list',
          'limit': maxJsonItemsPerList,
          'stateKey': key,
        },
      );
      return false;
    }
    final next = <Object?>[...current, sanitized];
    setValue(key, next);
    return true;
  }

  /// Applies defaults only for keys that are currently unset.
  void applyDefaults(Map<String, Object?>? defaults) {
    if (defaults == null || defaults.isEmpty) return;

    var changed = false;
    for (final entry in defaults.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;

      if (getValue(key) != null) continue;

      final rootKey = _rootKeyForPath(key);
      if (rootKey == null) continue;
      if (_values.length >= maxKeys && !_values.containsKey(rootKey)) break;

      final sanitized = _sanitizeValue(entry.value, key: key);
      if (_setPath(key, sanitized)) {
        changed = true;
      }
    }

    if (changed) {
      _syncNotifiers();
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

    // Allow bounded JSON-like values (decoded Maps/Lists + primitives).
    if (value is Map || value is List) {
      final sanitizer = _JsonLikeSanitizer(
        maxDepth: maxJsonDepth,
        maxNodes: maxJsonNodes,
        maxEntriesPerMap: maxJsonEntriesPerMap,
        maxItemsPerList: maxJsonItemsPerList,
        maxKeyLength: maxJsonKeyLength,
        maxStringLength: maxStringLength,
        diagnostics: _diagnostics,
        diagnosticsContext: _diagnosticsContext,
        stateKeyForDiagnostics: key,
      );
      final out = sanitizer.sanitize(value);
      if (out != null) return out;
    }

    // Fail-closed: do not accept arbitrary objects.
    _emitBudgetViolation(
      eventName: 'runtime.state.budget_clamped',
      severity: DiagnosticSeverity.warn,
      fingerprint: 'runtime.state.budget_clamped:budget=non_json_like:key=$key',
      payload: <String, Object?>{
        'budgetName': 'non_json_like',
        'stateKey': key,
        'valueType': value.runtimeType.toString(),
      },
    );
    return value.toString();
  }

  String? _rootKeyForPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final idx = trimmed.indexOf('.');
    final rootKey = (idx == -1 ? trimmed : trimmed.substring(0, idx)).trim();
    if (rootKey.isEmpty) return null;
    return rootKey.length > maxJsonKeyLength
        ? rootKey.substring(0, maxJsonKeyLength)
        : rootKey;
  }

  bool _setPath(String path, Object? value) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;

    final segments = trimmed.split('.').map((s) => s.trim()).toList();
    if (segments.any((s) => s.isEmpty)) return false;
    if (segments.length > maxJsonDepth + 1) {
      _emitBudgetViolation(
        eventName: 'runtime.state.budget_rejected',
        severity: DiagnosticSeverity.warn,
        fingerprint:
            'runtime.state.budget_rejected:budget=max_json_depth:path=$path',
        payload: <String, Object?>{
          'budgetName': 'max_json_depth',
          'limit': maxJsonDepth,
          'stateKey': path,
        },
      );
      return false;
    }

    final next = _setIn(_values, segments, 0, value);
    if (next is! Map<String, Object?>) return false;

    // Sanitize the entire root to enforce budgets conservatively.
    final sanitizer = _JsonLikeSanitizer(
      maxDepth: maxJsonDepth,
      maxNodes: maxJsonNodes,
      maxEntriesPerMap: maxJsonEntriesPerMap,
      maxItemsPerList: maxJsonItemsPerList,
      maxKeyLength: maxJsonKeyLength,
      maxStringLength: maxStringLength,
      diagnostics: _diagnostics,
      diagnosticsContext: _diagnosticsContext,
      stateKeyForDiagnostics: path,
    );
    final sanitizedRoot = sanitizer.sanitize(next);
    if (sanitizedRoot is! Map) return false;

    final map =
        Map<String, Object?>.from(sanitizedRoot.cast<String, Object?>());
    if (mapEquals(_values, map)) return false;

    _values
      ..clear()
      ..addAll(map);
    return true;
  }

  Object? _setIn(
      Object? current, List<String> segments, int index, Object? value) {
    if (index >= segments.length) return value;

    final segment = segments[index];

    // Map branch.
    if (current is Map) {
      final map = Map<String, Object?>.from(current.cast<String, Object?>());
      var key = segment;
      if (key.length > maxJsonKeyLength) {
        key = key.substring(0, maxJsonKeyLength);
      }

      final exists = map.containsKey(key);
      if (!exists && map.length >= maxJsonEntriesPerMap) {
        _emitBudgetViolation(
          eventName: 'runtime.state.budget_rejected',
          severity: DiagnosticSeverity.warn,
          fingerprint:
              'runtime.state.budget_rejected:budget=max_json_entries_per_map:key=$key',
          payload: <String, Object?>{
            'budgetName': 'max_json_entries_per_map',
            'limit': maxJsonEntriesPerMap,
            'stateKey': key,
          },
        );
        return current;
      }

      final child = map[key];
      map[key] = _setIn(child, segments, index + 1, value);
      return map;
    }

    // List branch.
    if (current is List) {
      final i = int.tryParse(segment);
      if (i == null) {
        // Can't index into list with non-numeric; fail closed.
        return current;
      }
      if (i < 0 || i >= maxJsonItemsPerList) {
        _emitBudgetViolation(
          eventName: 'runtime.state.budget_rejected',
          severity: DiagnosticSeverity.warn,
          fingerprint:
              'runtime.state.budget_rejected:budget=max_json_items_per_list:index=$i',
          payload: <String, Object?>{
            'budgetName': 'max_json_items_per_list',
            'limit': maxJsonItemsPerList,
            'stateKey': segment,
          },
        );
        return current;
      }

      final list = List<Object?>.from(current);
      while (list.length <= i) {
        if (list.length >= maxJsonItemsPerList) break;
        list.add(null);
      }
      if (i >= list.length) return current;
      list[i] = _setIn(list[i], segments, index + 1, value);
      return list;
    }

    // Create a container if needed.
    return _setIn(<String, Object?>{}, segments, index, value);
  }

  bool _removePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    final segments = trimmed.split('.').map((s) => s.trim()).toList();
    if (segments.any((s) => s.isEmpty)) return false;

    final next = _removeIn(_values, segments, 0);
    if (next is! Map<String, Object?>) return false;

    if (mapEquals(_values, next)) return false;
    _values
      ..clear()
      ..addAll(next);
    return true;
  }

  Object? _removeIn(Object? current, List<String> segments, int index) {
    if (index >= segments.length) return current;
    final segment = segments[index];

    if (current is Map) {
      final map = Map<String, Object?>.from(current.cast<String, Object?>());
      var key = segment;
      if (key.length > maxJsonKeyLength) {
        key = key.substring(0, maxJsonKeyLength);
      }

      if (index == segments.length - 1) {
        map.remove(key);
        return map;
      }

      final child = map[key];
      final nextChild = _removeIn(child, segments, index + 1);
      map[key] = nextChild;
      return map;
    }

    if (current is List) {
      final i = int.tryParse(segment);
      if (i == null || i < 0 || i >= current.length) return current;
      final list = List<Object?>.from(current);

      if (index == segments.length - 1) {
        list.removeAt(i);
        return list;
      }

      list[i] = _removeIn(list[i], segments, index + 1);
      return list;
    }

    return current;
  }

  void _syncNotifiers() {
    if (_notifiers.isEmpty) return;
    for (final entry in _notifiers.entries) {
      entry.value.value = getValue(entry.key);
    }
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

final class _JsonLikeSanitizer {
  _JsonLikeSanitizer({
    required this.maxDepth,
    required this.maxNodes,
    required this.maxEntriesPerMap,
    required this.maxItemsPerList,
    required this.maxKeyLength,
    required this.maxStringLength,
    required this.diagnostics,
    required this.diagnosticsContext,
    required this.stateKeyForDiagnostics,
  }) : _remainingNodes = maxNodes;

  final int maxDepth;
  final int maxNodes;
  final int maxEntriesPerMap;
  final int maxItemsPerList;
  final int maxKeyLength;
  final int maxStringLength;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;
  final String stateKeyForDiagnostics;

  int _remainingNodes;

  Object? sanitize(Object? value) => _sanitize(value, depth: 0);

  Object? _sanitize(Object? value, {required int depth}) {
    if (_remainingNodes <= 0) {
      _emitReject('max_json_nodes');
      return null;
    }
    if (depth > maxDepth) {
      _emitReject('max_json_depth');
      return null;
    }

    if (value == null) {
      _remainingNodes -= 1;
      return null;
    }

    if (value is String) {
      _remainingNodes -= 1;
      if (value.length <= maxStringLength) return value;
      _emitClamp('max_string_length',
          actual: value.length, limit: maxStringLength);
      return value.substring(0, maxStringLength);
    }

    if (value is num || value is bool) {
      _remainingNodes -= 1;
      return value;
    }

    if (value is List) {
      _remainingNodes -= 1;
      final out = <Object?>[];
      final limit =
          value.length < maxItemsPerList ? value.length : maxItemsPerList;
      if (value.length > maxItemsPerList) {
        _emitClamp('max_json_items_per_list',
            actual: value.length, limit: maxItemsPerList);
      }
      for (var i = 0; i < limit; i++) {
        final child = _sanitize(value[i], depth: depth + 1);
        out.add(child);
        if (_remainingNodes <= 0) break;
      }
      return out;
    }

    if (value is Map) {
      _remainingNodes -= 1;
      final out = <String, Object?>{};
      var added = 0;

      for (final entry in value.entries) {
        if (added >= maxEntriesPerMap) break;
        if (_remainingNodes <= 0) break;

        final rawKey = entry.key;
        if (rawKey is! String) continue;
        var key = rawKey.trim();
        if (key.isEmpty) continue;
        if (key.length > maxKeyLength) {
          _emitClamp('max_json_key_length',
              actual: key.length, limit: maxKeyLength);
          key = key.substring(0, maxKeyLength);
        }

        final child = _sanitize(entry.value, depth: depth + 1);
        out[key] = child;
        added += 1;
      }

      if (value.length > maxEntriesPerMap) {
        _emitClamp('max_json_entries_per_map',
            actual: value.length, limit: maxEntriesPerMap);
      }

      return out;
    }

    _remainingNodes -= 1;
    _emitClamp('non_json_like', actual: null, limit: null);
    return value.toString();
  }

  void _emitClamp(String budgetName, {int? actual, int? limit}) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.state.budget_clamped',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.state.budget_clamped:budget=$budgetName:key=$stateKeyForDiagnostics',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'budgetName': budgetName,
          if (limit != null) 'limit': limit,
          if (actual != null) 'actual': actual,
          'stateKey': stateKeyForDiagnostics,
        },
      ),
    );
  }

  void _emitReject(String budgetName) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.state.budget_rejected',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.state.budget_rejected:budget=$budgetName:key=$stateKeyForDiagnostics',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'budgetName': budgetName,
          'stateKey': stateKeyForDiagnostics,
        },
      ),
    );
  }
}
