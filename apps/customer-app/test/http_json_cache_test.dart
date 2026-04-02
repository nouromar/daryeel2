import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/src/cache/http_json_cache.dart';

void main() {
  testWidgets('HttpJsonCache ignores corrupt JSON and fetches network', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Intentionally invalid JSON.
      'http_cache.test.body_json': '{not json',
      'http_cache.test.etag': '"etag-1"',
    });

    final prefs = await SharedPreferences.getInstance();

    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);

    final client = MockClient((request) async {
      return http.Response(
        '{"ok":true}',
        200,
        headers: <String, String>{'etag': '"etag-2"'},
      );
    });

    final cache = HttpJsonCache(
      prefs: prefs,
      client: client,
      diagnostics: diagnostics,
      diagnosticsContext: const <String, Object?>{'test': true},
    );

    final result = await cache.getOrFetch(
      uri: Uri.parse('https://example.test/resource'),
      cacheKey: 'test',
    );

    expect(result, isA<HttpJsonCacheSuccess>());
    final ok = result as HttpJsonCacheSuccess;
    expect(ok.fromCache, isFalse);
    expect(ok.json['ok'], true);

    final corruptEvents = sink.events
        .where((e) => e.eventName == 'runtime.http_cache.corrupt_entry')
        .toList(growable: false);
    expect(corruptEvents.length, 1);
  });

  testWidgets(
    'HttpJsonCache returns failure (no throw) on network error + corrupt cache',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        // Intentionally invalid JSON.
        'http_cache.test.body_json': '{not json',
        'http_cache.test.etag': '"etag-1"',
      });

      final prefs = await SharedPreferences.getInstance();

      final sink = InMemoryDiagnosticsSink();
      final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);

      final client = MockClient((request) async {
        throw Exception('offline');
      });

      final cache = HttpJsonCache(
        prefs: prefs,
        client: client,
        diagnostics: diagnostics,
        diagnosticsContext: const <String, Object?>{'test': true},
      );

      late final HttpJsonCacheResult result;
      result = await cache.getOrFetch(
        uri: Uri.parse('https://example.test/resource'),
        cacheKey: 'test',
      );

      expect(result, isA<HttpJsonCacheFailure>());
      final failure = result as HttpJsonCacheFailure;
      expect(failure.cacheWasCorrupt, isTrue);
      expect(failure.kind, HttpJsonCacheFailureKind.network);

      final corruptEvents = sink.events
          .where((e) => e.eventName == 'runtime.http_cache.corrupt_entry')
          .toList(growable: false);
      expect(corruptEvents.length, 1);
    },
  );

  testWidgets('HttpJsonCache reuses cached body + headers on 304', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final calls = <Map<String, String>>[];
    final client = MockClient((request) async {
      calls.add(Map<String, String>.from(request.headers));

      // First call: 200 w/ ETag + docId.
      if (calls.length == 1) {
        return http.Response(
          '{"ok":true}',
          200,
          headers: <String, String>{
            'etag': '"E1"',
            'x-daryeel-doc-id': 'doc-1',
          },
        );
      }

      // Second call: 304 when If-None-Match matches; omit docId header to
      // ensure the cache provides it.
      if (request.headers['if-none-match'] == '"E1"') {
        return http.Response(
          '',
          304,
          headers: const <String, String>{'etag': '"E1"'},
        );
      }

      return http.Response('{"unexpected":true}', 500);
    });

    final cache = HttpJsonCache(prefs: prefs, client: client);

    final uri = Uri.parse('https://example.test/schema');
    final cacheKey = 'schema_screen.customer_home';

    final first = await cache.getOrFetch(
      uri: uri,
      cacheKey: cacheKey,
      cacheResponseHeaders: const <String>{'x-daryeel-doc-id'},
    );

    expect(first, isA<HttpJsonCacheSuccess>());
    final firstOk = first as HttpJsonCacheSuccess;
    expect(firstOk.fromCache, isFalse);
    expect(firstOk.etag, '"E1"');
    expect(firstOk.headers['x-daryeel-doc-id'], 'doc-1');
    expect(firstOk.json['ok'], true);

    final second = await cache.getOrFetch(
      uri: uri,
      cacheKey: cacheKey,
      cacheResponseHeaders: const <String>{'x-daryeel-doc-id'},
    );

    expect(second, isA<HttpJsonCacheSuccess>());
    final secondOk = second as HttpJsonCacheSuccess;
    expect(secondOk.fromCache, isTrue);
    expect(secondOk.etag, '"E1"');
    expect(secondOk.headers['x-daryeel-doc-id'], 'doc-1');
    expect(secondOk.json['ok'], true);

    expect(calls.length, 2);
    expect(calls.last['if-none-match'], '"E1"');
  });

  testWidgets('HttpJsonCache keeps selector vs docId cache keys distinct', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.contains('by-id')) {
        return http.Response('{"id":"doc"}', 200);
      }
      return http.Response('{"id":"selector"}', 200);
    });

    final cache = HttpJsonCache(prefs: prefs, client: client);

    final selectorKey = 'schema_screen.customer_home';
    final docKey = 'schema_screen_doc.doc-123';

    await cache.getOrFetch(
      uri: Uri.parse('https://example.test/schemas/screens/customer_home'),
      cacheKey: selectorKey,
    );

    await cache.getOrFetch(
      uri: Uri.parse('https://example.test/schemas/screens/docs/by-id/doc-123'),
      cacheKey: docKey,
    );

    final selectorCached = cache.readCachedJson(selectorKey);
    final docCached = cache.readCachedJson(docKey);

    expect(selectorCached?['id'], 'selector');
    expect(docCached?['id'], 'doc');

    // Lock in the distinct SharedPreferences storage keys to prevent
    // accidental collisions during refactors.
    expect(prefs.getString('http_cache.$selectorKey.body_json'), isNotNull);
    expect(prefs.getString('http_cache.$docKey.body_json'), isNotNull);
  });
}
