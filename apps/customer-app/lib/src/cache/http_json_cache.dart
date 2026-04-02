import 'dart:convert';

import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

sealed class HttpJsonCacheResult {
  const HttpJsonCacheResult();
}

final class HttpJsonCacheSuccess extends HttpJsonCacheResult {
  const HttpJsonCacheSuccess({
    required this.json,
    required this.etag,
    required this.fromCache,
    this.headers = const <String, String>{},
  });

  final Map<String, Object?> json;
  final String? etag;
  final bool fromCache;

  /// Optional cached subset of response headers.
  final Map<String, String> headers;
}

enum HttpJsonCacheFailureKind {
  network,
  httpStatus,
  invalidJson,
  notModifiedWithoutBody,
}

final class HttpJsonCacheFailure extends HttpJsonCacheResult {
  const HttpJsonCacheFailure({
    required this.kind,
    required this.message,
    required this.uri,
    required this.cacheKey,
    this.statusCode,
    this.cacheWasCorrupt = false,
    this.errorType,
  });

  final HttpJsonCacheFailureKind kind;
  final String message;
  final Uri uri;
  final String cacheKey;
  final int? statusCode;
  final bool cacheWasCorrupt;
  final String? errorType;
}

class HttpJsonCache {
  HttpJsonCache({
    required SharedPreferences prefs,
    http.Client? client,
    RuntimeDiagnostics? diagnostics,
    Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  }) : _prefs = prefs,
       _client = client ?? http.Client(),
       _diagnostics = diagnostics,
       _diagnosticsContext = diagnosticsContext;

  final SharedPreferences _prefs;
  final http.Client _client;
  final RuntimeDiagnostics? _diagnostics;
  final Map<String, Object?> _diagnosticsContext;

  String _etagKey(String cacheKey) => 'http_cache.$cacheKey.etag';
  String _bodyKey(String cacheKey) => 'http_cache.$cacheKey.body_json';
  String _headerKey(String cacheKey, String headerName) =>
      'http_cache.$cacheKey.header.$headerName';

  void _emitCorruptEntryDiagnostic({
    required String cacheKey,
    required int rawLength,
    required Object error,
  }) {
    _diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.http_cache.corrupt_entry',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.http_cache.corrupt_entry:$cacheKey',
        context: _diagnosticsContext,
        payload: <String, Object?>{
          'cacheKey': cacheKey,
          'rawLength': rawLength,
          'errorType': error.runtimeType.toString(),
        },
      ),
    );
  }

  _CachedJsonRead _readCachedJson(String cacheKey) {
    final raw = _prefs.getString(_bodyKey(cacheKey));
    if (raw == null || raw.isEmpty) {
      return const _CachedJsonRead.miss();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _CachedJsonRead.hit(
          Map<String, Object?>.from(decoded.cast<String, Object?>()),
        );
      }
      return _CachedJsonRead.corrupt(
        rawLength: raw.length,
        error: const FormatException('Cached JSON is not an object'),
      );
    } catch (e) {
      return _CachedJsonRead.corrupt(rawLength: raw.length, error: e);
    }
  }

  Map<String, Object?>? readCachedJson(String cacheKey) {
    final read = _readCachedJson(cacheKey);
    if (read.isCorrupt) {
      _emitCorruptEntryDiagnostic(
        cacheKey: cacheKey,
        rawLength: read.rawLength ?? 0,
        error:
            read.error ?? const FormatException('Unknown cache decode error'),
      );
      return null;
    }
    return read.json;
  }

  String? readEtag(String cacheKey) => _prefs.getString(_etagKey(cacheKey));

  String? readHeader(String cacheKey, String headerName) {
    return _prefs.getString(_headerKey(cacheKey, headerName));
  }

  Map<String, String> readHeaders(String cacheKey, Set<String> headerNames) {
    if (headerNames.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    for (final name in headerNames) {
      final v = readHeader(cacheKey, name);
      if (v != null && v.isNotEmpty) {
        out[name] = v;
      }
    }
    return out;
  }

  Future<void> write({
    required String cacheKey,
    required Map<String, Object?> json,
    required String? etag,
    Map<String, String> headers = const <String, String>{},
  }) async {
    await _prefs.setString(_bodyKey(cacheKey), jsonEncode(json));
    if (etag != null && etag.isNotEmpty) {
      await _prefs.setString(_etagKey(cacheKey), etag);
    }

    for (final entry in headers.entries) {
      if (entry.key.isEmpty) continue;
      if (entry.value.isEmpty) continue;
      await _prefs.setString(_headerKey(cacheKey, entry.key), entry.value);
    }
  }

  Future<HttpJsonCacheResult> getOrFetch({
    required Uri uri,
    required String cacheKey,
    Map<String, String> headers = const <String, String>{},
    Set<String> cacheResponseHeaders = const <String>{},
  }) async {
    final cachedRead = _readCachedJson(cacheKey);
    if (cachedRead.isCorrupt) {
      _emitCorruptEntryDiagnostic(
        cacheKey: cacheKey,
        rawLength: cachedRead.rawLength ?? 0,
        error:
            cachedRead.error ??
            const FormatException('Unknown cache decode error'),
      );
    }

    final cachedJson = cachedRead.json;
    final cachedEtag = readEtag(cacheKey);
    final cachedHeaders = readHeaders(cacheKey, cacheResponseHeaders);

    final requestHeaders = <String, String>{...headers};
    if (cachedEtag != null && cachedEtag.isNotEmpty) {
      requestHeaders['if-none-match'] = cachedEtag;
    }

    http.Response response;
    try {
      response = await _client.get(uri, headers: requestHeaders);
    } catch (e) {
      return HttpJsonCacheFailure(
        kind: HttpJsonCacheFailureKind.network,
        message: 'Network error for $uri',
        uri: uri,
        cacheKey: cacheKey,
        cacheWasCorrupt: cachedRead.isCorrupt,
        errorType: e.runtimeType.toString(),
      );
    }

    if (response.statusCode == 304) {
      if (cachedJson != null) {
        return HttpJsonCacheSuccess(
          json: cachedJson,
          etag: cachedEtag,
          fromCache: true,
          headers: cachedHeaders,
        );
      }

      // Cache is missing (or corrupt) so we cannot satisfy a 304.
      // Attempt a self-healing retry without conditional headers.
      try {
        response = await _client.get(uri, headers: headers);
      } catch (e) {
        return HttpJsonCacheFailure(
          kind: HttpJsonCacheFailureKind.notModifiedWithoutBody,
          message: '304 Not Modified but no cached body for $uri',
          uri: uri,
          cacheKey: cacheKey,
          cacheWasCorrupt: cachedRead.isCorrupt,
          errorType: e.runtimeType.toString(),
        );
      }
    }

    if (response.statusCode != 200) {
      if (cachedJson != null) {
        return HttpJsonCacheSuccess(
          json: cachedJson,
          etag: cachedEtag,
          fromCache: true,
          headers: cachedHeaders,
        );
      }

      return HttpJsonCacheFailure(
        kind: HttpJsonCacheFailureKind.httpStatus,
        message: 'HTTP ${response.statusCode} for $uri',
        uri: uri,
        cacheKey: cacheKey,
        statusCode: response.statusCode,
        cacheWasCorrupt: cachedRead.isCorrupt,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      return HttpJsonCacheFailure(
        kind: HttpJsonCacheFailureKind.invalidJson,
        message: 'Response returned invalid JSON for $uri',
        uri: uri,
        cacheKey: cacheKey,
        cacheWasCorrupt: cachedRead.isCorrupt,
        errorType: e.runtimeType.toString(),
      );
    }
    if (decoded is! Map) {
      return HttpJsonCacheFailure(
        kind: HttpJsonCacheFailureKind.invalidJson,
        message: 'Response returned a non-object JSON for $uri',
        uri: uri,
        cacheKey: cacheKey,
        cacheWasCorrupt: cachedRead.isCorrupt,
      );
    }

    final json = Map<String, Object?>.from(decoded.cast<String, Object?>());
    final etag = response.headers['etag'];

    final selectedHeaders = cacheResponseHeaders.isEmpty
        ? const <String, String>{}
        : <String, String>{
            for (final name in cacheResponseHeaders)
              if (response.headers[name] != null &&
                  response.headers[name]!.isNotEmpty)
                name: response.headers[name]!,
          };

    await write(
      cacheKey: cacheKey,
      json: json,
      etag: etag,
      headers: selectedHeaders,
    );

    return HttpJsonCacheSuccess(
      json: json,
      etag: etag,
      fromCache: false,
      headers: selectedHeaders,
    );
  }
}

final class _CachedJsonRead {
  const _CachedJsonRead._({
    required this.json,
    required this.isCorrupt,
    required this.rawLength,
    required this.error,
  });

  const _CachedJsonRead.miss()
    : this._(json: null, isCorrupt: false, rawLength: null, error: null);

  const _CachedJsonRead.hit(Map<String, Object?> json)
    : this._(json: json, isCorrupt: false, rawLength: null, error: null);

  const _CachedJsonRead.corrupt({required int rawLength, required Object error})
    : this._(json: null, isCorrupt: true, rawLength: rawLength, error: error);

  final Map<String, Object?>? json;
  final bool isCorrupt;
  final int? rawLength;
  final Object? error;
}
