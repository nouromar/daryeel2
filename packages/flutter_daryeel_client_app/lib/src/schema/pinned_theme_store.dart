import 'package:shared_preferences/shared_preferences.dart';

/// Stores the last-known-good immutable theme document id (docId) per selector.
///
/// This enables rollback-friendly theme delivery:
/// - Try pinned immutable doc first
/// - If it fails, fall back to cached pinned doc
/// - Then try selector (latest) and only promote to pinned after success
class PinnedThemeStore {
  PinnedThemeStore({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  static String keyFor({
    required String product,
    required String themeId,
    required String themeMode,
  }) => 'theme.pinned_doc_id.$product.$themeId.$themeMode';

  String? readPinnedDocId({
    required String product,
    required String themeId,
    required String themeMode,
  }) {
    final v = _prefs.getString(
      keyFor(product: product, themeId: themeId, themeMode: themeMode),
    );
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Future<void> writePinnedDocId({
    required String product,
    required String themeId,
    required String themeMode,
    required String docId,
  }) async {
    if (docId.isEmpty) return;
    await _prefs.setString(
      keyFor(product: product, themeId: themeId, themeMode: themeMode),
      docId,
    );
  }

  Future<void> clearPinnedDocId({
    required String product,
    required String themeId,
    required String themeMode,
  }) async {
    await _prefs.remove(
      keyFor(product: product, themeId: themeId, themeMode: themeMode),
    );
  }
}
