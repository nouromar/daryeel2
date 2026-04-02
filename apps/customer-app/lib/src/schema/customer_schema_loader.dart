import 'dart:convert';

import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;

import '../cache/http_json_cache.dart';

typedef RequestHeadersProvider = Map<String, String> Function();

class InMemorySchemaLoader implements SchemaLoader {
  const InMemorySchemaLoader({required this.bundle});

  final SchemaBundle bundle;

  @override
  Future<SchemaBundle> loadScreen(RuntimeScreenRequest request) async {
    if (request.screenId != bundle.schemaId) {
      throw StateError('No bundled schema found for ${request.screenId}');
    }
    return bundle;
  }
}

class InMemoryFragmentDocumentLoader implements FragmentDocumentLoader {
  const InMemoryFragmentDocumentLoader({required this.documents});

  final Map<String, Map<String, Object?>> documents;

  @override
  Future<Map<String, Object?>> loadFragmentDocument(String fragmentId) async {
    final doc = documents[fragmentId];
    if (doc == null) {
      throw StateError('No bundled fragment found for $fragmentId');
    }
    return doc;
  }
}

class HttpSchemaLoader implements SchemaLoader {
  HttpSchemaLoader({
    required this.baseUrl,
    http.Client? client,
    this.headersProvider,
    this.cache,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final RequestHeadersProvider? headersProvider;
  final HttpJsonCache? cache;

  @override
  Future<SchemaBundle> loadScreen(RuntimeScreenRequest request) async {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final uri = Uri.parse(
      '$normalizedBaseUrl/schemas/screens/${request.screenId}',
    );

    Map<String, Object?> document;
    String? docId;
    if (cache != null) {
      final result = await cache!.getOrFetch(
        uri: uri,
        cacheKey: 'schema_screen.${request.screenId}',
        headers: headersProvider?.call() ?? const <String, String>{},
        cacheResponseHeaders: const <String>{'x-daryeel-doc-id'},
      );

      if (result is! HttpJsonCacheSuccess) {
        final failure = result as HttpJsonCacheFailure;
        throw StateError(failure.message);
      }

      document = result.json;
      docId = result.headers['x-daryeel-doc-id'];
    } else {
      final response = await _client.get(uri, headers: headersProvider?.call());

      if (response.statusCode != 200) {
        throw StateError(
          'Schema service returned ${response.statusCode} for ${request.screenId}',
        );
      }

      if (response.bodyBytes.length > SecurityBudgets.maxSchemaJsonBytes) {
        throw StateError(
          'Response too large (${response.bodyBytes.length} bytes)',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException(
          'Schema service returned a non-object response',
        );
      }

      document = Map<String, Object?>.from(decoded.cast<String, Object?>());
      docId = response.headers['x-daryeel-doc-id'];
    }

    return SchemaBundle(
      schemaId: document['id'] as String? ?? request.screenId,
      schemaVersion: document['schemaVersion'] as String? ?? 'unknown',
      document: document,
      docId: docId,
    );
  }
}

/// Loads an immutable schema document by `docId`.
///
/// Intended for the schema pinning ladder.
class HttpSchemaDocLoader implements SchemaLoader {
  HttpSchemaDocLoader({
    required this.baseUrl,
    required this.docId,
    http.Client? client,
    this.headersProvider,
    this.cache,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String docId;
  final http.Client _client;
  final RequestHeadersProvider? headersProvider;
  final HttpJsonCache? cache;

  @override
  Future<SchemaBundle> loadScreen(RuntimeScreenRequest request) async {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final encoded = Uri.encodeComponent(docId);

    // Mirrors the theme doc endpoint shape: `/docs/by-id/<docId>`.
    final uri = Uri.parse(
      '$normalizedBaseUrl/schemas/screens/docs/by-id/$encoded',
    );

    Map<String, Object?> document;
    if (cache != null) {
      final result = await cache!.getOrFetch(
        uri: uri,
        cacheKey: 'schema_screen_doc.$docId',
        headers: headersProvider?.call() ?? const <String, String>{},
      );

      if (result is! HttpJsonCacheSuccess) {
        final failure = result as HttpJsonCacheFailure;
        throw StateError(failure.message);
      }

      document = result.json;
    } else {
      final response = await _client.get(uri, headers: headersProvider?.call());

      if (response.statusCode != 200) {
        throw StateError(
          'Schema service returned ${response.statusCode} for docId=$docId',
        );
      }

      if (response.bodyBytes.length > SecurityBudgets.maxSchemaJsonBytes) {
        throw StateError(
          'Response too large (${response.bodyBytes.length} bytes)',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException(
          'Schema service returned a non-object response',
        );
      }

      document = Map<String, Object?>.from(decoded.cast<String, Object?>());
    }

    return SchemaBundle(
      schemaId: document['id'] as String? ?? request.screenId,
      schemaVersion: document['schemaVersion'] as String? ?? 'unknown',
      document: document,
      docId: docId,
    );
  }
}

class HttpFragmentDocumentLoader implements FragmentDocumentLoader {
  HttpFragmentDocumentLoader({
    required this.baseUrl,
    http.Client? client,
    this.headersProvider,
    this.cache,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final RequestHeadersProvider? headersProvider;
  final HttpJsonCache? cache;

  @override
  Future<Map<String, Object?>> loadFragmentDocument(String fragmentId) async {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final encoded = Uri.encodeComponent(fragmentId);

    final uri = Uri.parse('$normalizedBaseUrl/schemas/fragments/$encoded');

    if (cache != null) {
      final result = await cache!.getOrFetch(
        uri: uri,
        cacheKey: 'schema_fragment.$encoded',
        headers: headersProvider?.call() ?? const <String, String>{},
      );

      if (result is! HttpJsonCacheSuccess) {
        final failure = result as HttpJsonCacheFailure;
        throw StateError(failure.message);
      }

      return result.json;
    }

    final response = await _client.get(uri, headers: headersProvider?.call());

    if (response.statusCode != 200) {
      throw StateError(
        'Schema service returned ${response.statusCode} for fragment $fragmentId',
      );
    }

    if (response.bodyBytes.length > SecurityBudgets.maxSchemaJsonBytes) {
      throw StateError(
        'Response too large (${response.bodyBytes.length} bytes)',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Schema service returned a non-object response',
      );
    }

    return Map<String, Object?>.from(decoded.cast<String, Object?>());
  }
}
