import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Best-effort persistence for selected `$state` paths.
///
/// Stores a JSON object `{ "<path>": <json-like value> }` in SharedPreferences.
///
/// Notes:
/// - Only paths configured by the app are persisted.
/// - Writes are debounced to avoid excessive I/O.
/// - Fail-closed: corrupt JSON is ignored.
final class SchemaStatePersistenceController {
  SchemaStatePersistenceController({
    required SharedPreferences prefs,
    required this.prefsKey,
    required List<String> paths,
    Duration debounce = const Duration(milliseconds: 400),
    this.maxEncodedChars = 64 * 1024,
  })  : _prefs = prefs,
        _paths = paths
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList(growable: false),
        _debounce = debounce;

  final SharedPreferences _prefs;
  final String prefsKey;
  final List<String> _paths;
  final Duration _debounce;

  /// Hard cap on the serialized JSON size we store.
  ///
  /// If exceeded, we skip the write (best-effort).
  final int maxEncodedChars;

  VoidCallback? _removeListener;
  Timer? _timer;

  static String defaultPrefsKey({
    required String product,
    required String appId,
  }) {
    final p = product.trim();
    final a = appId.trim();
    return 'daryeel_client.state.$p.$a';
  }

  Future<void> restoreInto(SchemaStateStore store) async {
    if (_paths.isEmpty) return;

    final raw = _prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }

    if (decoded is! Map) return;

    final m = Map<String, Object?>.from(decoded.cast<String, Object?>());
    for (final path in _paths) {
      if (!m.containsKey(path)) continue;
      store.setValue(path, m[path]);
    }
  }

  void startAutoSave(SchemaStateStore store) {
    if (_paths.isEmpty) return;

    // Avoid double-binding.
    stopAutoSave();

    void listener() {
      _timer?.cancel();
      _timer = Timer(_debounce, () => _flush(store));
    }

    store.addListener(listener);
    _removeListener = () => store.removeListener(listener);
  }

  void stopAutoSave() {
    _timer?.cancel();
    _timer = null;
    _removeListener?.call();
    _removeListener = null;
  }

  Future<void> clear() async {
    await _prefs.remove(prefsKey);
  }

  Future<void> _flush(SchemaStateStore store) async {
    if (_paths.isEmpty) return;

    final out = <String, Object?>{};
    for (final path in _paths) {
      final v = store.getValue(path);
      if (v == null) continue;
      out[path] = v;
    }

    if (out.isEmpty) {
      await _prefs.remove(prefsKey);
      return;
    }

    final encoded = jsonEncode(out);
    if (encoded.length > maxEncodedChars) {
      // Best-effort: refuse oversized writes.
      return;
    }

    await _prefs.setString(prefsKey, encoded);
  }

  void dispose() {
    stopAutoSave();
  }
}
