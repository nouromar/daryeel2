import 'package:shared_preferences/shared_preferences.dart';

/// Stores the last-known-good immutable schema document id (docId) per screen.
///
/// This is the client-side anchor for rollback-friendly schema delivery:
/// - Try pinned immutable doc first
/// - If it fails, fall back to cached pinned doc
/// - Then try selector (latest) and only promote to pinned after success
class PinnedSchemaStore {
  PinnedSchemaStore({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  static String keyFor({required String product, required String screenId}) =>
      'schema.pinned_doc_id.$product.$screenId';

  String? readPinnedDocId({required String product, required String screenId}) {
    final v = _prefs.getString(keyFor(product: product, screenId: screenId));
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Future<void> writePinnedDocId({
    required String product,
    required String screenId,
    required String docId,
  }) async {
    if (docId.isEmpty) return;
    await _prefs.setString(keyFor(product: product, screenId: screenId), docId);
  }

  Future<void> clearPinnedDocId({
    required String product,
    required String screenId,
  }) async {
    await _prefs.remove(keyFor(product: product, screenId: screenId));
  }
}
