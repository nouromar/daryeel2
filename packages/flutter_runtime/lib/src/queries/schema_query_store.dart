import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/schema_data_scope.dart';
import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';
import '../security/security_budgets.dart';
import 'schema_query_spec.dart';

final class SchemaQueryStore extends ChangeNotifier {
  SchemaQueryStore({
    required this.apiBaseUrl,
    required http.Client client,
    RuntimeDiagnostics? diagnostics,
    Map<String, Object?> diagnosticsContext = const <String, Object?>{},
    Map<String, String> Function()? defaultHeadersProvider,
    this.maxResponseBytes = SecurityBudgets.maxQueryResponseBytes,
  })  : _client = client,
        _diagnostics = diagnostics,
        _diagnosticsContext = diagnosticsContext,
        _defaultHeadersProvider = defaultHeadersProvider;

  final String apiBaseUrl;
  final http.Client _client;
  RuntimeDiagnostics? _diagnostics;
  Map<String, Object?> _diagnosticsContext;
  Map<String, String> Function()? _defaultHeadersProvider;

  RuntimeDiagnostics? get diagnostics => _diagnostics;
  Map<String, Object?> get diagnosticsContext => _diagnosticsContext;

  void configure({
    RuntimeDiagnostics? diagnostics,
    Map<String, Object?> diagnosticsContext = const <String, Object?>{},
    Map<String, String> Function()? defaultHeadersProvider,
  }) {
    _diagnostics = diagnostics;
    _diagnosticsContext = diagnosticsContext;
    _defaultHeadersProvider = defaultHeadersProvider;
  }

  Map<String, String> _mergeHeaders(Map<String, String> headers) {
    final defaults = _defaultHeadersProvider?.call();
    if (defaults == null || defaults.isEmpty) return headers;
    if (headers.isEmpty) return defaults;
    return <String, String>{...defaults, ...headers};
  }

  /// Hard budget to avoid large/untrusted payloads overwhelming the client.
  final int maxResponseBytes;

  /// Hard cap to avoid unbounded in-memory growth for infinite scroll.
  final int maxItemsPerPagedQuery = SecurityBudgets.maxItemsPerPagedQuery;

  final Map<String, _SchemaQueryState> _queries = <String, _SchemaQueryState>{};
  final Map<String, _SchemaPagedQueryState> _pagedQueries =
      <String, _SchemaPagedQueryState>{};

  ValueListenable<SchemaQuerySnapshot> watchQuery(String key) {
    final state = _queries.putIfAbsent(key, () => _SchemaQueryState(key: key));
    return state.snapshotNotifier;
  }

  SchemaQuerySnapshot snapshot(String key) {
    return _queries[key]?.snapshot ?? SchemaQuerySnapshot(key: key);
  }

  void invalidate(String key) {
    final state = _queries.remove(key);
    state?.dispose();
    notifyListeners();
  }

  ValueListenable<SchemaPagedQuerySnapshot> watchPagedQuery(String key) {
    final state = _pagedQueries.putIfAbsent(
      key,
      () => _SchemaPagedQueryState(key: key),
    );
    return state.snapshotNotifier;
  }

  SchemaPagedQuerySnapshot pagedSnapshot(String key) {
    return _pagedQueries[key]?.snapshot ?? SchemaPagedQuerySnapshot(key: key);
  }

  void invalidatePaged(String key) {
    final state = _pagedQueries.remove(key);
    state?.dispose();
    notifyListeners();
  }

  Future<void> executeGet({
    required String key,
    required String path,
    Map<String, String> params = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    bool forceRefresh = false,
  }) async {
    final state = _queries.putIfAbsent(key, () => _SchemaQueryState(key: key));

    if (!forceRefresh) {
      if (state.snapshot.isLoading) return;
      if (state.snapshot.hasData || state.snapshot.hasError) {
        // Cache within a screen session for now; higher-level TTL can be added
        // later without changing the widget contract.
        return;
      }
    }

    final sanitizedPath = SchemaQuerySpec.sanitizePath(path);
    if (sanitizedPath == null) {
      _setError(
        state,
        'Invalid query path',
        errorType: 'invalid_path',
        extra: <String, Object?>{'path': path},
      );
      return;
    }

    final sanitizedParams = SchemaQuerySpec.sanitizeParams(params);

    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      _setError(state, 'API base URL is not configured', errorType: 'no_base');
      return;
    }

    final uri = _buildUri(base, sanitizedPath, sanitizedParams);
    state.setLoading();

    final effectiveHeaders = _mergeHeaders(headers);
    final requestId = effectiveHeaders['x-request-id'];

    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.query.start',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.query.start:$key:${uri.path}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'key': key,
          'method': 'GET',
          'path': sanitizedPath,
          if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
          if (sanitizedParams.isNotEmpty) 'params': sanitizedParams,
        },
      ),
    );

    try {
      final response = await _client.get(uri, headers: effectiveHeaders);

      final bytes = response.bodyBytes;
      if (bytes.length > maxResponseBytes) {
        _setError(
          state,
          'Response too large',
          errorType: 'response_too_large',
          extra: <String, Object?>{
            'maxResponseBytes': maxResponseBytes,
            'actualBytes': bytes.length,
            'statusCode': response.statusCode,
          },
        );
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setError(
          state,
          'HTTP ${response.statusCode}',
          errorType: 'http_error',
          extra: <String, Object?>{
            'statusCode': response.statusCode,
          },
        );
        return;
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      state.setData(decoded);

      diagnostics?.emit(
        DiagnosticEvent(
          eventName: 'runtime.query.success',
          severity: DiagnosticSeverity.info,
          kind: DiagnosticKind.diagnostic,
          fingerprint: 'runtime.query.success:$key:${uri.path}',
          context: diagnosticsContext,
          payload: <String, Object?>{
            'key': key,
            'method': 'GET',
            'path': sanitizedPath,
            if (requestId != null && requestId.isNotEmpty)
              'requestId': requestId,
            'statusCode': response.statusCode,
          },
        ),
      );
    } catch (error) {
      _setError(
        state,
        'Query failed',
        errorType: error.runtimeType.toString(),
      );
    }
  }

  Future<void> executePagedGet({
    required String key,
    required String path,
    Map<String, String> params = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    required String itemsPath,
    required String nextCursorPath,
    String cursorParam = 'cursor',
    bool forceRefresh = false,
  }) async {
    final state = _pagedQueries.putIfAbsent(
      key,
      () => _SchemaPagedQueryState(key: key),
    );

    final sanitizedPath = SchemaQuerySpec.sanitizePath(path);
    if (sanitizedPath == null) {
      _setPagedError(
        state,
        'Invalid query path',
        errorType: 'invalid_path',
        extra: <String, Object?>{'path': path},
      );
      return;
    }

    final trimmedItemsPath = itemsPath.trim();
    final trimmedCursorPath = nextCursorPath.trim();
    if (trimmedItemsPath.isEmpty || trimmedCursorPath.isEmpty) {
      _setPagedError(
        state,
        'Invalid paging paths',
        errorType: 'invalid_paths',
        extra: <String, Object?>{
          'itemsPath': itemsPath,
          'nextCursorPath': nextCursorPath,
        },
      );
      return;
    }

    final safeCursorParam =
        cursorParam.trim().isEmpty ? 'cursor' : cursorParam.trim();

    final baseParams = SchemaQuerySpec.sanitizeParams(params);

    state.configure(
      path: sanitizedPath,
      baseParams: baseParams,
      userHeaders: headers,
      itemsPath: trimmedItemsPath,
      nextCursorPath: trimmedCursorPath,
      cursorParam: safeCursorParam,
    );

    if (!forceRefresh) {
      if (state.snapshot.isLoading) return;
      if (state.snapshot.hasItems || state.snapshot.hasError) return;
    }

    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      _setPagedError(
        state,
        'API base URL is not configured',
        errorType: 'no_base',
      );
      return;
    }

    state.setLoading(reset: true);
    await _fetchPagedPage(
      state: state,
      baseUrl: base,
      cursor: null,
      append: false,
    );
  }

  Future<void> loadMorePagedGet(String key) async {
    final state = _pagedQueries[key];
    if (state == null) return;

    if (state.snapshot.isLoading || state.snapshot.isLoadingMore) return;
    final cursor = state.snapshot.nextCursor;
    if (cursor == null || cursor.trim().isEmpty) return;

    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      _setPagedLoadMoreError(
        state,
        'API base URL is not configured',
        errorType: 'no_base',
      );
      return;
    }

    if (state.snapshot.items.length >= maxItemsPerPagedQuery) {
      _setPagedLoadMoreError(
        state,
        'Too many items',
        errorType: 'max_items',
        extra: <String, Object?>{'maxItems': maxItemsPerPagedQuery},
      );
      return;
    }

    state.setLoadingMore();
    await _fetchPagedPage(
      state: state,
      baseUrl: base,
      cursor: cursor,
      append: true,
    );
  }

  Future<void> _fetchPagedPage({
    required _SchemaPagedQueryState state,
    required String baseUrl,
    required String? cursor,
    required bool append,
  }) async {
    final config = state.config;
    if (config == null) {
      _setPagedError(state, 'Missing query config', errorType: 'no_config');
      return;
    }

    final params = <String, String>{...config.baseParams};
    if (cursor != null && cursor.trim().isNotEmpty) {
      params[config.cursorParam] = cursor.trim();
    } else {
      params.remove(config.cursorParam);
    }

    final uri = _buildUri(baseUrl, config.path, params);

    final effectiveHeaders = _mergeHeaders(config.userHeaders);
    final requestId = effectiveHeaders['x-request-id'];

    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.query.paged.start',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.query.paged.start:${state.key}:${uri.path}',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'key': state.key,
          'method': 'GET',
          'path': config.path,
          if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
          if (params.isNotEmpty) 'params': params,
          'append': append,
        },
      ),
    );

    try {
      final response = await _client.get(
        uri,
        headers: effectiveHeaders,
      );

      final bytes = response.bodyBytes;
      if (bytes.length > maxResponseBytes) {
        _setPagedError(
          state,
          'Response too large',
          errorType: 'response_too_large',
          extra: <String, Object?>{
            'maxResponseBytes': maxResponseBytes,
            'actualBytes': bytes.length,
            'statusCode': response.statusCode,
            'append': append,
          },
          isLoadMore: append,
        );
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setPagedError(
          state,
          'HTTP ${response.statusCode}',
          errorType: 'http_error',
          extra: <String, Object?>{
            'statusCode': response.statusCode,
            'append': append,
          },
          isLoadMore: append,
        );
        return;
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      final rawItems = readJsonPath(decoded, config.itemsPath);
      if (rawItems is! List) {
        _setPagedError(
          state,
          'Items is not a list',
          errorType: 'items_not_list',
          extra: <String, Object?>{
            'itemsPath': config.itemsPath,
            'append': append,
          },
          isLoadMore: append,
        );
        return;
      }

      final rawCursor = readJsonPath(decoded, config.nextCursorPath);
      final nextCursor = (rawCursor is String && rawCursor.trim().isNotEmpty)
          ? rawCursor.trim()
          : null;

      final nextItems = rawItems.toList(growable: false);

      if (append) {
        final merged = <Object?>[...state.snapshot.items, ...nextItems];
        if (merged.length > maxItemsPerPagedQuery) {
          _setPagedLoadMoreError(
            state,
            'Too many items',
            errorType: 'max_items',
            extra: <String, Object?>{'maxItems': maxItemsPerPagedQuery},
          );
          return;
        }

        state.setItems(
          items: merged,
          raw: decoded,
          nextCursor: nextCursor,
          clearLoadMoreError: true,
        );
      } else {
        state.setItems(
          items: nextItems,
          raw: decoded,
          nextCursor: nextCursor,
          clearLoadMoreError: true,
        );
      }

      diagnostics?.emit(
        DiagnosticEvent(
          eventName: 'runtime.query.paged.success',
          severity: DiagnosticSeverity.info,
          kind: DiagnosticKind.diagnostic,
          fingerprint: 'runtime.query.paged.success:${state.key}:${uri.path}',
          context: diagnosticsContext,
          payload: <String, Object?>{
            'key': state.key,
            'method': 'GET',
            'path': config.path,
            if (requestId != null && requestId.isNotEmpty)
              'requestId': requestId,
            'statusCode': response.statusCode,
            'append': append,
            'itemsCount': nextItems.length,
            'totalCount': state.snapshot.items.length,
            'hasMore': state.snapshot.hasMore,
          },
        ),
      );
    } catch (error) {
      _setPagedError(
        state,
        'Query failed',
        errorType: error.runtimeType.toString(),
        isLoadMore: append,
      );
    }
  }

  void _setError(
    _SchemaQueryState state,
    String message, {
    required String errorType,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    state.setError(message);

    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.query.failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.query.failed:${state.key}:$errorType',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'key': state.key,
          'errorType': errorType,
          'message': message,
          ...extra,
        },
      ),
    );
  }

  void _setPagedError(
    _SchemaPagedQueryState state,
    String message, {
    required String errorType,
    Map<String, Object?> extra = const <String, Object?>{},
    bool isLoadMore = false,
  }) {
    if (isLoadMore) {
      state.setLoadMoreError(message);
    } else {
      state.setError(message);
    }

    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.query.paged.failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.query.paged.failed:${state.key}:$errorType',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'key': state.key,
          'errorType': errorType,
          'message': message,
          'append': isLoadMore,
          ...extra,
        },
      ),
    );
  }

  void _setPagedLoadMoreError(
    _SchemaPagedQueryState state,
    String message, {
    required String errorType,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    _setPagedError(
      state,
      message,
      errorType: errorType,
      extra: extra,
      isLoadMore: true,
    );
  }

  Uri _buildUri(String baseUrl, String path, Map<String, String> params) {
    final base = Uri.parse(baseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    // base.resolve will replace the path if `path` begins with '/', so build
    // manually.
    final mergedPath = _joinPaths(base.path, normalizedPath);

    return base.replace(
      path: mergedPath,
      queryParameters: params.isEmpty ? null : params,
    );
  }

  String _joinPaths(String basePath, String relative) {
    final a = basePath.trim();
    final b = relative.trim();

    if (a.isEmpty || a == '/') return b;

    if (a.endsWith('/') && b.startsWith('/'))
      return '${a.substring(0, a.length - 1)}$b';
    if (!a.endsWith('/') && !b.startsWith('/')) return '$a/$b';
    return '$a$b';
  }
}

final class SchemaPagedQuerySnapshot {
  const SchemaPagedQuerySnapshot({
    required this.key,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.items = const <Object?>[],
    this.raw,
    this.nextCursor,
    this.errorMessage,
    this.loadMoreErrorMessage,
  });

  final String key;
  final bool isLoading;
  final bool isLoadingMore;
  final List<Object?> items;

  /// The most recent decoded JSON response.
  final Object? raw;

  final String? nextCursor;
  final String? errorMessage;
  final String? loadMoreErrorMessage;

  bool get hasItems => items.isNotEmpty;
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
  bool get hasLoadMoreError =>
      loadMoreErrorMessage != null && loadMoreErrorMessage!.isNotEmpty;
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

final class SchemaQuerySnapshot {
  const SchemaQuerySnapshot({
    required this.key,
    this.isLoading = false,
    this.data,
    this.errorMessage,
  });

  final String key;
  final bool isLoading;
  final Object? data;
  final String? errorMessage;

  bool get hasData => data != null;
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

final class _SchemaQueryState {
  _SchemaQueryState({required this.key})
      : snapshotNotifier = ValueNotifier<SchemaQuerySnapshot>(
          SchemaQuerySnapshot(key: key),
        );

  final String key;
  final ValueNotifier<SchemaQuerySnapshot> snapshotNotifier;

  SchemaQuerySnapshot get snapshot => snapshotNotifier.value;

  void setLoading() {
    snapshotNotifier.value = SchemaQuerySnapshot(
      key: key,
      isLoading: true,
      data: snapshot.data,
      errorMessage: null,
    );
  }

  void setData(Object? data) {
    snapshotNotifier.value = SchemaQuerySnapshot(
      key: key,
      isLoading: false,
      data: data,
      errorMessage: null,
    );
  }

  void setError(String message) {
    snapshotNotifier.value = SchemaQuerySnapshot(
      key: key,
      isLoading: false,
      data: null,
      errorMessage: message,
    );
  }

  void dispose() {
    snapshotNotifier.dispose();
  }
}

final class _SchemaPagedQueryConfig {
  const _SchemaPagedQueryConfig({
    required this.path,
    required this.baseParams,
    required this.userHeaders,
    required this.itemsPath,
    required this.nextCursorPath,
    required this.cursorParam,
  });

  final String path;
  final Map<String, String> baseParams;
  final Map<String, String> userHeaders;
  final String itemsPath;
  final String nextCursorPath;
  final String cursorParam;
}

final class _SchemaPagedQueryState {
  _SchemaPagedQueryState({required this.key})
      : snapshotNotifier = ValueNotifier<SchemaPagedQuerySnapshot>(
          SchemaPagedQuerySnapshot(key: key),
        );

  final String key;
  final ValueNotifier<SchemaPagedQuerySnapshot> snapshotNotifier;

  _SchemaPagedQueryConfig? config;

  SchemaPagedQuerySnapshot get snapshot => snapshotNotifier.value;

  void configure({
    required String path,
    required Map<String, String> baseParams,
    required Map<String, String> userHeaders,
    required String itemsPath,
    required String nextCursorPath,
    required String cursorParam,
  }) {
    config = _SchemaPagedQueryConfig(
      path: path,
      baseParams: baseParams,
      userHeaders: userHeaders,
      itemsPath: itemsPath,
      nextCursorPath: nextCursorPath,
      cursorParam: cursorParam,
    );
  }

  void setLoading({required bool reset}) {
    snapshotNotifier.value = SchemaPagedQuerySnapshot(
      key: key,
      isLoading: true,
      isLoadingMore: false,
      items: reset ? const <Object?>[] : snapshot.items,
      raw: reset ? null : snapshot.raw,
      nextCursor: reset ? null : snapshot.nextCursor,
      errorMessage: null,
      loadMoreErrorMessage: null,
    );
  }

  void setLoadingMore() {
    snapshotNotifier.value = SchemaPagedQuerySnapshot(
      key: key,
      isLoading: false,
      isLoadingMore: true,
      items: snapshot.items,
      raw: snapshot.raw,
      nextCursor: snapshot.nextCursor,
      errorMessage: snapshot.errorMessage,
      loadMoreErrorMessage: null,
    );
  }

  void setItems({
    required List<Object?> items,
    required Object? raw,
    required String? nextCursor,
    required bool clearLoadMoreError,
  }) {
    snapshotNotifier.value = SchemaPagedQuerySnapshot(
      key: key,
      isLoading: false,
      isLoadingMore: false,
      items: items,
      raw: raw,
      nextCursor: nextCursor,
      errorMessage: null,
      loadMoreErrorMessage:
          clearLoadMoreError ? null : snapshot.loadMoreErrorMessage,
    );
  }

  void setError(String message) {
    snapshotNotifier.value = SchemaPagedQuerySnapshot(
      key: key,
      isLoading: false,
      isLoadingMore: false,
      items: const <Object?>[],
      raw: null,
      nextCursor: null,
      errorMessage: message,
      loadMoreErrorMessage: null,
    );
  }

  void setLoadMoreError(String message) {
    snapshotNotifier.value = SchemaPagedQuerySnapshot(
      key: key,
      isLoading: false,
      isLoadingMore: false,
      items: snapshot.items,
      raw: snapshot.raw,
      nextCursor: snapshot.nextCursor,
      errorMessage: snapshot.errorMessage,
      loadMoreErrorMessage: message,
    );
  }

  void dispose() {
    snapshotNotifier.dispose();
  }
}
