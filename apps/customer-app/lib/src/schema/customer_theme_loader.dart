import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_themes/flutter_themes.dart' as remote_themes;
import 'package:http/http.dart' as http;

import '../cache/http_json_cache.dart';
import 'pinned_theme_store.dart';

typedef RequestHeadersProvider = Map<String, String> Function();

enum ThemeLoadSource { pinnedImmutable, cachedPinned, selector }

class LoadedTheme {
  const LoadedTheme({
    required this.themeData,
    required this.themeId,
    required this.themeMode,
    this.docId,
    required this.fromRemote,
    required this.source,
  });

  final ThemeData themeData;
  final String themeId;
  final String themeMode;
  final String? docId;
  final bool fromRemote;
  final ThemeLoadSource source;
}

class CustomerThemeLoader {
  CustomerThemeLoader({
    required this.baseUrl,
    required this.product,
    required this.pinnedStore,
    http.Client? client,
    this.cache,
    this.headersProvider,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String product;
  final PinnedThemeStore pinnedStore;
  final http.Client _client;
  final HttpJsonCache? cache;
  final RequestHeadersProvider? headersProvider;

  static String _normalize(String baseUrl) => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  /// Loads a theme document using the safe fallback ladder:
  /// 1) pinned immutable doc (network)
  /// 2) cached pinned doc (LKG)
  /// 3) selector (latest)
  ///
  /// Returns null if no remote theme could be loaded.
  Future<LoadedTheme?> loadTheme({
    required String themeId,
    required String themeMode,
  }) async {
    final normalized = _normalize(baseUrl);

    remote_themes.ThemeDocument? parseTheme(Map<String, Object?> json) {
      try {
        final doc = remote_themes.ThemeDocument.fromJson(json);
        if (doc.themeId != themeId || doc.themeMode != themeMode) {
          return null;
        }
        return doc;
      } catch (_) {
        return null;
      }
    }

    ThemeData? buildTheme(remote_themes.ThemeDocument doc) {
      try {
        return remote_themes.resolveThemeData(theme: doc);
      } catch (_) {
        return null;
      }
    }

    final pinnedDocId = pinnedStore.readPinnedDocId(
      product: product,
      themeId: themeId,
      themeMode: themeMode,
    );

    if (pinnedDocId != null) {
      try {
        final encoded = Uri.encodeComponent(pinnedDocId);
        final uri = Uri.parse('$normalized/themes/docs/by-id/$encoded');

        Map<String, Object?> json;
        if (cache != null) {
          final result = await cache!.getOrFetch(
            uri: uri,
            cacheKey: 'theme_doc_id.$pinnedDocId',
            headers: headersProvider?.call() ?? const <String, String>{},
          );

          if (result is! HttpJsonCacheSuccess) {
            final failure = result as HttpJsonCacheFailure;
            throw StateError(failure.message);
          }

          json = result.json;
        } else {
          final response = await _client.get(
            uri,
            headers: headersProvider?.call(),
          );
          if (response.statusCode != 200) {
            throw StateError('Theme service returned ${response.statusCode}');
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map) {
            throw const FormatException(
              'Theme service returned non-object JSON',
            );
          }
          json = Map<String, Object?>.from(decoded.cast<String, Object?>());
        }

        final doc = parseTheme(json);
        if (doc == null) {
          await pinnedStore.clearPinnedDocId(
            product: product,
            themeId: themeId,
            themeMode: themeMode,
          );
        } else {
          final themeData = buildTheme(doc);
          if (themeData != null) {
            return LoadedTheme(
              themeData: themeData,
              themeId: themeId,
              themeMode: themeMode,
              docId: pinnedDocId,
              fromRemote: true,
              source: ThemeLoadSource.pinnedImmutable,
            );
          }
        }
      } catch (_) {
        // Best-effort: fall back to cached pinned doc then selector.
      }

      if (cache != null) {
        final cachedPinnedJson = cache!.readCachedJson(
          'theme_doc_id.$pinnedDocId',
        );
        if (cachedPinnedJson != null) {
          final doc = parseTheme(cachedPinnedJson);
          if (doc != null) {
            final themeData = buildTheme(doc);
            if (themeData != null) {
              return LoadedTheme(
                themeData: themeData,
                themeId: themeId,
                themeMode: themeMode,
                docId: pinnedDocId,
                fromRemote: true,
                source: ThemeLoadSource.cachedPinned,
              );
            }
          }
        }
      }
    }

    // Selector (latest)
    final selectorUri = Uri.parse('$normalized/themes/$themeId/$themeMode');
    Map<String, Object?> selectorJson;
    String? selectorDocId;
    String? selectorEtag;

    if (cache != null) {
      final result = await cache!.getOrFetch(
        uri: selectorUri,
        cacheKey: 'theme_doc.$themeId.$themeMode',
        headers: headersProvider?.call() ?? const <String, String>{},
        cacheResponseHeaders: const <String>{'x-daryeel-doc-id'},
      );

      if (result is! HttpJsonCacheSuccess) {
        final failure = result as HttpJsonCacheFailure;
        throw StateError(failure.message);
      }

      selectorJson = result.json;
      selectorDocId = result.headers['x-daryeel-doc-id'];
      selectorEtag = result.etag;
    } else {
      final response = await _client.get(
        selectorUri,
        headers: headersProvider?.call(),
      );

      if (response.statusCode != 200) {
        throw StateError('Theme service returned ${response.statusCode}');
      }

      selectorDocId = response.headers['x-daryeel-doc-id'];
      selectorEtag = response.headers['etag'];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Theme service returned non-object JSON');
      }
      selectorJson = Map<String, Object?>.from(decoded.cast<String, Object?>());
    }

    final selectorDoc = parseTheme(selectorJson);
    if (selectorDoc == null) {
      return null;
    }

    final selectorThemeData = buildTheme(selectorDoc);
    if (selectorThemeData == null) {
      return null;
    }

    // Promote to pinned only after successfully building ThemeData.
    if (selectorDocId != null && selectorDocId.isNotEmpty) {
      await pinnedStore.writePinnedDocId(
        product: product,
        themeId: themeId,
        themeMode: themeMode,
        docId: selectorDocId,
      );

      // Ensure LKG cache by docId exists.
      if (cache != null) {
        await cache!.write(
          cacheKey: 'theme_doc_id.$selectorDocId',
          json: selectorJson,
          etag: selectorEtag,
        );
      }
    }

    return LoadedTheme(
      themeData: selectorThemeData,
      themeId: themeId,
      themeMode: themeMode,
      docId: selectorDocId,
      fromRemote: true,
      source: ThemeLoadSource.selector,
    );
  }
}
