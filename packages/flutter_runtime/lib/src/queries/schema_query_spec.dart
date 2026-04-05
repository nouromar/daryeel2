/// A bounded query spec for schema-driven data fetching.
///
/// Design goals:
/// - Only supports relative API paths (must start with `/`)
/// - No arbitrary URLs, no `..`, no oversized inputs
/// - Query params are stringified and constrained by conservative budgets
import '../forms/schema_form_store.dart';
import '../state/schema_state_store.dart';

final class SchemaQuerySpec {
  const SchemaQuerySpec({
    required this.path,
    this.params = const <String, String>{},
  });

  /// Relative API path (e.g. `/v1/service-definitions`).
  final String path;

  /// Query parameters (e.g. `{ "q": "x", "limit": "20" }`).
  final Map<String, String> params;

  static const int maxPathLength = 512;
  static const int maxParamEntries = 25;
  static const int maxParamKeyLength = 64;
  static const int maxParamValueLength = 512;

  static const String _formPrefixDot = r'$form.';
  static const String _formPrefixColon = r'$form:';

  static const String _routePrefixDot = r'$route.';
  static const String _routePrefixColon = r'$route:';

  static const String _statePrefixDot = r'$state.';
  static const String _statePrefixColon = r'$state:';

  static Object? _readMapPath(Map<String, Object?> map, String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;

    Object? current = map;
    for (final rawSegment in trimmed.split('.')) {
      final segment = rawSegment.trim();
      if (segment.isEmpty) return null;

      if (current is Map) {
        current = current[segment];
        continue;
      }

      return null;
    }

    return current;
  }

  /// Returns a sanitized path, or null when invalid.
  static String? sanitizePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('/')) return null;
    if (trimmed.contains('://')) return null;
    if (trimmed.contains('..')) return null;
    if (trimmed.length > maxPathLength) return null;
    return trimmed;
  }

  /// Coerces a JSON-ish params object into a safe `Map<String, String>`.
  ///
  /// Accepted inputs:
  /// - `Map<String, String>`
  /// - `Map<String, Object?>` where values are `String|num|bool|null`
  static Map<String, String> coerceParams(Object? raw) {
    if (raw == null) return const <String, String>{};

    if (raw is Map<String, String>) {
      return raw;
    }

    if (raw is Map) {
      final out = <String, String>{};
      for (final entry in raw.entries) {
        final k = entry.key;
        if (k is! String) continue;

        final v = entry.value;
        if (v == null) continue;

        if (v is String) {
          out[k] = v;
          continue;
        }

        if (v is num || v is bool) {
          out[k] = v.toString();
          continue;
        }
      }
      return out;
    }

    return const <String, String>{};
  }

  /// Resolves bounded dynamic param bindings.
  ///
  /// Supported bindings:
  /// - `$form.<formId>.<fieldKey>` (or `$form:<formId>.<fieldKey>`)
  ///
  /// All other values are coerced with [coerceParams]. Unknown bindings resolve
  /// to null and are omitted.
  static Map<String, String> resolveParams(
    Object? raw, {
    SchemaFormStore? formStore,
    SchemaStateStore? stateStore,
    Map<String, Object?>? routeParams,
  }) {
    final base = coerceParams(raw);
    if (base.isEmpty) return const <String, String>{};

    final out = <String, String>{};
    for (final entry in base.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value.startsWith(_formPrefixDot) ||
          value.startsWith(_formPrefixColon)) {
        final store = formStore;
        if (store == null) continue;

        final bindingRaw = value.startsWith(_formPrefixDot)
            ? value.substring(_formPrefixDot.length)
            : value.substring(_formPrefixColon.length);

        final binding = SchemaFieldBinding.tryParse(bindingRaw);
        if (binding == null) continue;

        final v = store.getFieldValue(binding.formId, binding.fieldKey);
        if (v == null) continue;
        if (v is String) {
          if (v.trim().isEmpty) continue;
          out[key] = v;
          continue;
        }
        if (v is num || v is bool) {
          out[key] = v.toString();
          continue;
        }

        // Fail closed: only allow primitives.
        out[key] = v.toString();
        continue;
      }

      if (value.startsWith(_routePrefixDot) ||
          value.startsWith(_routePrefixColon)) {
        final params = routeParams;
        if (params == null || params.isEmpty) continue;

        final bindingRaw = value.startsWith(_routePrefixDot)
            ? value.substring(_routePrefixDot.length)
            : value.substring(_routePrefixColon.length);

        final v = _readMapPath(params, bindingRaw);
        if (v == null) continue;
        if (v is String) {
          if (v.trim().isEmpty) continue;
          out[key] = v;
          continue;
        }
        if (v is num || v is bool) {
          out[key] = v.toString();
          continue;
        }

        // Fail closed: only allow primitives.
        out[key] = v.toString();
        continue;
      }

      if (value.startsWith(_statePrefixDot) ||
          value.startsWith(_statePrefixColon)) {
        final store = stateStore;
        if (store == null) continue;

        final bindingRaw = value.startsWith(_statePrefixDot)
            ? value.substring(_statePrefixDot.length)
            : value.substring(_statePrefixColon.length);

        final stateKey = bindingRaw.trim();
        if (stateKey.isEmpty) continue;

        final v = store.getValue(stateKey);
        if (v == null) continue;
        if (v is String) {
          if (v.trim().isEmpty) continue;
          out[key] = v;
          continue;
        }
        if (v is num || v is bool) {
          out[key] = v.toString();
          continue;
        }

        // Fail closed: only allow primitives.
        out[key] = v.toString();
        continue;
      }

      out[key] = value;
    }

    return out;
  }

  /// Sanitizes params with budgets. Invalid entries are dropped.
  static Map<String, String> sanitizeParams(Map<String, String> raw) {
    if (raw.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    var count = 0;
    for (final entry in raw.entries) {
      if (count >= maxParamEntries) break;

      final key = entry.key.trim();
      if (key.isEmpty) continue;
      if (key.length > maxParamKeyLength) continue;

      final value = entry.value.trim();
      if (value.isEmpty) continue;
      if (value.length > maxParamValueLength) continue;

      out[key] = value;
      count++;
    }

    return out;
  }

  /// Returns a sanitized spec or null if the path is invalid.
  SchemaQuerySpec? sanitized() {
    final p = sanitizePath(path);
    if (p == null) return null;

    final safeParams = sanitizeParams(params);
    return SchemaQuerySpec(path: p, params: safeParams);
  }
}
