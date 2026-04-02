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
}
