import 'dart:convert';

import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('SchemaQueryStore rejects invalid paths', () async {
    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: MockClient((_) async {
        throw StateError('should not be called');
      }),
    );

    await store.executeGet(key: 'k1', path: 'https://evil.com');
    expect(store.snapshot('k1').hasError, isTrue);

    await store.executeGet(key: 'k2', path: 'no-leading-slash');
    expect(store.snapshot('k2').hasError, isTrue);

    await store.executeGet(key: 'k3', path: '/../admin');
    expect(store.snapshot('k3').hasError, isTrue);
  });

  test('SchemaQueryStore decodes JSON on success', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'http://example.com/v1/services');
      return http.Response(
          jsonEncode({
            'items': [1, 2, 3]
          }),
          200);
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
    );

    await store.executeGet(key: 'services', path: '/v1/services');
    final snap = store.snapshot('services');
    expect(snap.hasData, isTrue);
    expect((snap.data as Map)['items'], [1, 2, 3]);
  });

  test('SchemaQueryStore appends sanitized query params', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/search');
      expect(request.url.queryParameters['q'], 'abc');
      expect(request.url.queryParameters['limit'], '10');
      expect(request.url.queryParameters.containsKey(''), isFalse);
      expect(request.url.queryParameters.containsKey('   '), isFalse);
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
    );

    await store.executeGet(
      key: 'search',
      path: '/v1/search',
      params: <String, String>{
        'q': 'abc',
        'limit': '10',
        '': 'nope',
        '   ': 'nope',
        'emptyValue': '   ',
      },
    );

    expect(store.snapshot('search').hasData, isTrue);
  });

  test('SchemaQueryStore enforces response size budget', () async {
    final big = List.filled(600 * 1024, 65); // 'A'
    final client = MockClient((request) async {
      return http.Response.bytes(big, 200);
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
      maxResponseBytes: 512 * 1024,
    );

    await store.executeGet(key: 'big', path: '/v1/big');
    expect(store.snapshot('big').hasError, isTrue);
  });

  test('SchemaQueryStore merges default headers with per-call headers',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'http://example.com/v1/services');
      expect(request.headers['x-request-id'], 'r1');
      expect(request.headers['x-daryeel-session-id'], 's1');
      expect(request.headers['x-custom'], 'explicit');
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
      defaultHeadersProvider: () => <String, String>{
        'x-request-id': 'r1',
        'x-daryeel-session-id': 's1',
        'x-custom': 'default',
      },
    );

    await store.executeGet(
      key: 'services',
      path: '/v1/services',
      headers: const <String, String>{'x-custom': 'explicit'},
    );

    expect(store.snapshot('services').hasData, isTrue);
  });
}
