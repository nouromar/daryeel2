import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CachedJsonResponse {
  const CachedJsonResponse({
    required this.json,
    required this.etag,
    required this.fromCache,
  });

  final Map<String, Object?> json;
  final String? etag;
  final bool fromCache;
}

class HttpJsonCache {
  HttpJsonCache({required SharedPreferences prefs, http.Client? client})
    : _prefs = prefs,
      _client = client ?? http.Client();

  final SharedPreferences _prefs;
  final http.Client _client;

  String _etagKey(String cacheKey) => 'http_cache.$cacheKey.etag';
  String _bodyKey(String cacheKey) => 'http_cache.$cacheKey.body_json';

  Map<String, Object?>? readCachedJson(String cacheKey) {
    final raw = _prefs.getString(_bodyKey(cacheKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded.cast<String, Object?>());
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  String? readEtag(String cacheKey) => _prefs.getString(_etagKey(cacheKey));

  Future<void> write({
    required String cacheKey,
    required Map<String, Object?> json,
    required String? etag,
  }) async {
    await _prefs.setString(_bodyKey(cacheKey), jsonEncode(json));
    if (etag != null && etag.isNotEmpty) {
      await _prefs.setString(_etagKey(cacheKey), etag);
    }
  }

  Future<CachedJsonResponse> getOrFetch({
    required Uri uri,
    required String cacheKey,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final cachedJson = readCachedJson(cacheKey);
    final cachedEtag = readEtag(cacheKey);

    final requestHeaders = <String, String>{...headers};
    if (cachedEtag != null && cachedEtag.isNotEmpty) {
      requestHeaders['if-none-match'] = cachedEtag;
    }

    final response = await _client.get(uri, headers: requestHeaders);

    if (response.statusCode == 304 && cachedJson != null) {
      return CachedJsonResponse(
        json: cachedJson,
        etag: cachedEtag,
        fromCache: true,
      );
    }

    if (response.statusCode != 200) {
      if (cachedJson != null) {
        return CachedJsonResponse(
          json: cachedJson,
          etag: cachedEtag,
          fromCache: true,
        );
      }
      throw StateError('HTTP ${response.statusCode} for $uri');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Response returned a non-object JSON');
    }

    final json = Map<String, Object?>.from(decoded.cast<String, Object?>());
    final etag = response.headers['etag'];
    await write(cacheKey: cacheKey, json: json, etag: etag);

    return CachedJsonResponse(json: json, etag: etag, fromCache: false);
  }
}
