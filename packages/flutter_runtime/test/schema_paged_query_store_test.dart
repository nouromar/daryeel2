import 'dart:convert';

import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('SchemaQueryStore paged query refresh + loadMore appends items',
      () async {
    var call = 0;

    final client = MockClient((request) async {
      call++;
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/items');

      if (call == 1) {
        expect(request.url.queryParameters.containsKey('cursor'), isFalse);
        return http.Response(
          jsonEncode({
            'items': [1, 2],
            'next': {'cursor': 'c1'},
          }),
          200,
        );
      }

      expect(request.url.queryParameters['cursor'], 'c1');
      return http.Response(
        jsonEncode({
          'items': [3],
          'next': {'cursor': null},
        }),
        200,
      );
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
    );

    await store.executePagedGet(
      key: 'k',
      path: '/v1/items',
      itemsPath: 'items',
      nextCursorPath: 'next.cursor',
    );

    var snap = store.pagedSnapshot('k');
    expect(snap.hasError, isFalse);
    expect(snap.items, [1, 2]);
    expect(snap.nextCursor, 'c1');
    expect(snap.hasMore, isTrue);

    await store.loadMorePagedGet('k');

    snap = store.pagedSnapshot('k');
    expect(snap.items, [1, 2, 3]);
    expect(snap.nextCursor, isNull);
    expect(snap.hasMore, isFalse);
  });

  test('SchemaQueryStore paged query merges default headers', () async {
    var call = 0;

    final client = MockClient((request) async {
      call++;
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/items');
      expect(request.headers['x-request-id'], 'r1');
      expect(request.headers['x-daryeel-session-id'], 's1');
      expect(request.headers['x-custom'], 'explicit');

      if (call == 1) {
        return http.Response(
          jsonEncode({
            'items': [1],
            'next': {'cursor': 'c1'},
          }),
          200,
        );
      }

      return http.Response(
        jsonEncode({
          'items': [2],
          'next': {'cursor': null},
        }),
        200,
      );
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
      defaultHeadersProvider: () => const <String, String>{
        'x-request-id': 'r1',
        'x-daryeel-session-id': 's1',
      },
    );

    await store.executePagedGet(
      key: 'k',
      path: '/v1/items',
      headers: const <String, String>{'x-custom': 'explicit'},
      itemsPath: 'items',
      nextCursorPath: 'next.cursor',
    );

    await store.loadMorePagedGet('k');

    expect(store.pagedSnapshot('k').items, [1, 2]);
  });

  test('SchemaQueryStore paged query errors when itemsPath is not a list',
      () async {
    final client = MockClient((request) async {
      return http.Response(
          jsonEncode({
            'items': {'no': 'list'},
            'next': {}
          }),
          200);
    });

    final store = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
    );

    await store.executePagedGet(
      key: 'k',
      path: '/v1/items',
      itemsPath: 'items',
      nextCursorPath: 'next.cursor',
    );

    final snap = store.pagedSnapshot('k');
    expect(snap.hasError, isTrue);
  });
}
