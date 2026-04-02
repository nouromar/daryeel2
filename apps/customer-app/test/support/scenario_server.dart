import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ScenarioRequestLog {
  const ScenarioRequestLog({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;

  @override
  String toString() => '$method $path';
}

typedef _DocKey = String;

class ScenarioJsonDoc {
  const ScenarioJsonDoc({
    required this.json,
    this.statusCode = 200,
    this.headers = const <String, String>{},
    this.etag,
    this.abortConnection = false,
    this.headersOnNotModified = const <String, String>{},
  });

  final Map<String, Object?> json;
  final int statusCode;
  final Map<String, String> headers;
  final String? etag;

  /// If true, throws a [SocketException] from the client (simulates network failure).
  final bool abortConnection;

  /// Additional headers to include on a 304 response.
  final Map<String, String> headersOnNotModified;
}

/// Test-only in-process backend simulator.
///
/// This is intentionally NOT a real socket server: Flutter widget tests block
/// real network I/O. Instead, it exposes an in-memory [http.Client] that routes
/// requests through the same endpoint shapes as the production loaders.
///
/// Endpoints implemented (GET):
/// - /config/bootstrap?product=<id>
/// - /config/snapshots/<snapshotId>
/// - /schemas/screens/<screenId>
/// - /schemas/screens/docs/by-id/<docId>
/// - /schemas/fragments/<fragmentId>
/// - /themes/<themeId>/<themeMode>
/// - /themes/docs/by-id/<docId>
class ScenarioServer {
  ScenarioServer({Uri? baseUri})
    : _baseUri = baseUri ?? Uri.parse('http://scenario.local');

  final Uri _baseUri;

  Uri get baseUri => _baseUri;
  String get baseUrl => _baseUri.toString();

  late final http.Client client = _ScenarioHttpClient(this);

  final List<ScenarioRequestLog> _requests = <ScenarioRequestLog>[];
  List<ScenarioRequestLog> get requests => List.unmodifiable(_requests);

  final Map<String, Map<String, Object?>> _bootstrapByProduct =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _snapshotById =
      <String, Map<String, Object?>>{};

  final Map<String, ScenarioJsonDoc> _screenById = <String, ScenarioJsonDoc>{};
  final Map<String, ScenarioJsonDoc> _screenDocByDocId =
      <String, ScenarioJsonDoc>{};
  final Map<String, ScenarioJsonDoc> _fragmentById =
      <String, ScenarioJsonDoc>{};

  final Map<_DocKey, ScenarioJsonDoc> _themeByKey =
      <_DocKey, ScenarioJsonDoc>{};
  final Map<String, ScenarioJsonDoc> _themeDocByDocId =
      <String, ScenarioJsonDoc>{};

  void reset() {
    _requests.clear();
    _bootstrapByProduct.clear();
    _snapshotById.clear();
    _screenById.clear();
    _screenDocByDocId.clear();
    _fragmentById.clear();
    _themeByKey.clear();
    _themeDocByDocId.clear();
  }

  void stubBootstrap({
    required String product,
    required Map<String, Object?> json,
  }) {
    _bootstrapByProduct[product] = json;
  }

  void stubSnapshot({
    required String snapshotId,
    required Map<String, Object?> json,
  }) {
    _snapshotById[snapshotId] = json;
  }

  void stubScreen({required String screenId, required ScenarioJsonDoc doc}) {
    _screenById[screenId] = doc;
  }

  void stubScreenDoc({required String docId, required ScenarioJsonDoc doc}) {
    _screenDocByDocId[docId] = doc;
  }

  void stubFragment({
    required String fragmentId,
    required ScenarioJsonDoc doc,
  }) {
    _fragmentById[fragmentId] = doc;
  }

  void stubTheme({
    required String themeId,
    required String themeMode,
    required ScenarioJsonDoc doc,
  }) {
    _themeByKey[_themeKey(themeId, themeMode)] = doc;
  }

  void stubThemeDoc({required String docId, required ScenarioJsonDoc doc}) {
    _themeDocByDocId[docId] = doc;
  }

  static String _themeKey(String themeId, String themeMode) =>
      '$themeId/$themeMode';

  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, value) {
      if (value.isNotEmpty) {
        headers[name.toLowerCase()] = value;
      }
    });

    _requests.add(
      ScenarioRequestLog(
        method: request.method,
        path: request.url.path,
        query: request.url.queryParameters,
        headers: headers,
      ),
    );

    if (request.method != 'GET') {
      return _text(405, 'Method not allowed');
    }

    final segments = request.url.pathSegments;
    if (segments.isEmpty) {
      return _text(404, 'Not found');
    }

    // /config/bootstrap?product=<id>
    if (segments.length == 2 &&
        segments[0] == 'config' &&
        segments[1] == 'bootstrap') {
      final product = request.url.queryParameters['product'] ?? '';
      final doc = _bootstrapByProduct[product];
      if (doc == null) {
        return _text(404, 'No bootstrap for product=$product');
      }
      return _json(request, ScenarioJsonDoc(json: doc));
    }

    // /config/snapshots/<snapshotId>
    if (segments.length == 3 &&
        segments[0] == 'config' &&
        segments[1] == 'snapshots') {
      final snapshotId = segments[2];
      final doc = _snapshotById[snapshotId];
      if (doc == null) {
        return _text(404, 'No snapshot for id=$snapshotId');
      }
      return _json(request, ScenarioJsonDoc(json: doc));
    }

    // /schemas/screens/<screenId>
    if (segments.length == 3 &&
        segments[0] == 'schemas' &&
        segments[1] == 'screens') {
      final screenId = segments[2];
      final doc = _screenById[screenId];
      if (doc == null) {
        return _text(404, 'No screen for id=$screenId');
      }
      return _json(request, doc);
    }

    // /schemas/screens/docs/by-id/<docId>
    if (segments.length == 5 &&
        segments[0] == 'schemas' &&
        segments[1] == 'screens' &&
        segments[2] == 'docs' &&
        segments[3] == 'by-id') {
      final docId = segments[4];
      final doc = _screenDocByDocId[docId];
      if (doc == null) {
        return _text(404, 'No screen doc for docId=$docId');
      }
      return _json(request, doc);
    }

    // /schemas/fragments/<fragmentId>
    if (segments.length == 3 &&
        segments[0] == 'schemas' &&
        segments[1] == 'fragments') {
      final fragmentId = segments[2];
      final doc = _fragmentById[fragmentId];
      if (doc == null) {
        return _text(404, 'No fragment for id=$fragmentId');
      }
      return _json(request, doc);
    }

    // /themes/<themeId>/<themeMode>
    if (segments.length == 3 && segments[0] == 'themes') {
      final themeId = segments[1];
      final themeMode = segments[2];
      final doc = _themeByKey[_themeKey(themeId, themeMode)];
      if (doc == null) {
        return _text(404, 'No theme for $themeId/$themeMode');
      }
      return _json(request, doc);
    }

    // /themes/docs/by-id/<docId>
    if (segments.length == 4 &&
        segments[0] == 'themes' &&
        segments[1] == 'docs' &&
        segments[2] == 'by-id') {
      final docId = segments[3];
      final doc = _themeDocByDocId[docId];
      if (doc == null) {
        return _text(404, 'No theme doc for docId=$docId');
      }
      return _json(request, doc);
    }

    return _text(404, 'Not found');
  }

  http.StreamedResponse _text(int status, String body) {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: <String, String>{'content-type': 'text/plain; charset=utf-8'},
    );
  }

  http.StreamedResponse _json(http.BaseRequest request, ScenarioJsonDoc doc) {
    if (doc.abortConnection) {
      throw const SocketException('ScenarioServer forced connection abort');
    }

    final ifNoneMatch = request.headers['if-none-match'];
    final etag = doc.etag;

    if (etag != null && ifNoneMatch != null && ifNoneMatch == etag) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        304,
        headers: <String, String>{
          'etag': etag,
          ..._lowercaseKeys(doc.headersOnNotModified),
        },
      );
    }

    final bodyBytes = utf8.encode(jsonEncode(doc.json));
    return http.StreamedResponse(
      Stream<List<int>>.value(bodyBytes),
      doc.statusCode,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        if (etag != null && etag.isNotEmpty) 'etag': etag,
        ..._lowercaseKeys(doc.headers),
      },
    );
  }

  static Map<String, String> _lowercaseKeys(Map<String, String> headers) {
    if (headers.isEmpty) return const <String, String>{};
    return <String, String>{
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
  }
}

class _ScenarioHttpClient extends http.BaseClient {
  _ScenarioHttpClient(this._server);

  final ScenarioServer _server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // The production code uses absolute URIs based on baseUrl.
    // We accept any scheme/host and route only by path.
    return _server.handle(request);
  }
}
