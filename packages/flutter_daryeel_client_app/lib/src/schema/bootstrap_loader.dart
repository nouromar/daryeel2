import 'dart:convert';

import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;

import '../cache/http_json_cache.dart';
import 'schema_loader.dart';

class ProductBootstrap {
  const ProductBootstrap({
    required this.bootstrapVersion,
    required this.product,
    required this.initialScreenId,
    required this.defaultThemeId,
    required this.defaultThemeMode,
    required this.configSchemaVersion,
    required this.configSnapshotId,
    required this.configTtlSeconds,
    required this.schemaServiceBaseUrl,
    required this.themeServiceBaseUrl,
    required this.configServiceBaseUrl,
    required this.telemetryIngestUrl,
  });

  final int bootstrapVersion;
  final String product;
  final String initialScreenId;
  final String defaultThemeId;
  final String defaultThemeMode;

  final int configSchemaVersion;
  final String configSnapshotId;
  final int configTtlSeconds;

  final String? schemaServiceBaseUrl;
  final String? themeServiceBaseUrl;
  final String? configServiceBaseUrl;
  final String? telemetryIngestUrl;

  static ProductBootstrap fromJson(Map<String, Object?> json) {
    int readInt(String key, {required int fallback}) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }

    String readString(String key, {required String fallback}) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    String? readNullableString(String key) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return ProductBootstrap(
      bootstrapVersion: readInt('bootstrapVersion', fallback: 1),
      product: readString('product', fallback: ''),
      initialScreenId: readString('initialScreenId', fallback: ''),
      defaultThemeId: readString('defaultThemeId', fallback: ''),
      defaultThemeMode: readString('defaultThemeMode', fallback: 'light'),
      configSchemaVersion: readInt('configSchemaVersion', fallback: 1),
      configSnapshotId: readString('configSnapshotId', fallback: ''),
      configTtlSeconds: readInt('configTtlSeconds', fallback: 3600),
      schemaServiceBaseUrl: readNullableString('schemaServiceBaseUrl'),
      themeServiceBaseUrl: readNullableString('themeServiceBaseUrl'),
      configServiceBaseUrl: readNullableString('configServiceBaseUrl'),
      telemetryIngestUrl: readNullableString('telemetryIngestUrl'),
    );
  }
}

class ConfigSnapshot {
  const ConfigSnapshot({
    required this.schemaVersion,
    required this.snapshotId,
    required this.flags,
    required this.telemetry,
    required this.runtime,
    required this.serviceCatalog,
  });

  final int schemaVersion;
  final String snapshotId;

  final Map<String, Object?> flags;
  final Map<String, Object?> telemetry;
  final Map<String, Object?> runtime;
  final Map<String, Object?> serviceCatalog;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'snapshotId': snapshotId,
      'flags': flags,
      'telemetry': telemetry,
      'runtime': runtime,
      'serviceCatalog': serviceCatalog,
    };
  }

  Set<String> get enabledFeatureFlags {
    final raw = flags['featureFlags'];
    if (raw is List) {
      return raw.whereType<String>().where((f) => f.isNotEmpty).toSet();
    }
    return const <String>{};
  }

  bool get enableRemoteIngest {
    final raw = telemetry['enableRemoteIngest'];
    return raw is bool ? raw : true;
  }

  bool get enableRemoteThemes {
    final raw = runtime['enableRemoteThemes'];
    return raw is bool ? raw : false;
  }

  SchemaCompatibilityPolicyOverlay? get schemaCompatibilityPolicyOverlay {
    final raw = runtime['schemaCompatibilityPolicyOverlay'];
    if (raw is! Map) return null;
    final m = Map<String, Object?>.from(raw.cast<String, Object?>());

    Set<String>? readStringSet(Object? v) {
      if (v == null) return null;
      if (v is Set) {
        return v.whereType<String>().where((s) => s.isNotEmpty).toSet();
      }
      if (v is List) {
        return v.whereType<String>().where((s) => s.isNotEmpty).toSet();
      }
      return null;
    }

    final supportedSchemaVersions = readStringSet(m['supportedSchemaVersions']);
    final supportedProducts = readStringSet(m['supportedProducts']);
    final supportedThemeIds = readStringSet(m['supportedThemeIds']);
    final supportedThemeModes = readStringSet(m['supportedThemeModes']);
    final requireRootNode = m['requireRootNode'] is bool
        ? (m['requireRootNode'] as bool)
        : null;

    if (supportedSchemaVersions == null &&
        supportedProducts == null &&
        supportedThemeIds == null &&
        supportedThemeModes == null &&
        requireRootNode == null) {
      return null;
    }

    return SchemaCompatibilityPolicyOverlay(
      supportedSchemaVersions: supportedSchemaVersions,
      supportedProducts: supportedProducts,
      supportedThemeIds: supportedThemeIds,
      supportedThemeModes: supportedThemeModes,
      requireRootNode: requireRootNode,
    );
  }

  int? get dedupeTtlSeconds {
    final raw = telemetry['dedupeTtlSeconds'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  int? get maxInfoPerSession {
    final raw = telemetry['maxInfoPerSession'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  int? get maxWarnPerSession {
    final raw = telemetry['maxWarnPerSession'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  static ConfigSnapshot fromJson(Map<String, Object?> json) {
    int readInt(String key, {required int fallback}) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }

    String readString(String key, {required String fallback}) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    Map<String, Object?> readMap(String key) {
      final v = json[key];
      if (v is Map) {
        return Map<String, Object?>.from(v.cast<String, Object?>());
      }
      return const <String, Object?>{};
    }

    return ConfigSnapshot(
      schemaVersion: readInt('schemaVersion', fallback: 1),
      snapshotId: readString('snapshotId', fallback: ''),
      flags: readMap('flags'),
      telemetry: readMap('telemetry'),
      runtime: readMap('runtime'),
      serviceCatalog: readMap('serviceCatalog'),
    );
  }
}

class DaryeelBootstrapLoader {
  DaryeelBootstrapLoader({
    required this.baseUrl,
    http.Client? client,
    this.headersProvider,
    this.cache,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final RequestHeadersProvider? headersProvider;
  final HttpJsonCache? cache;

  Future<ProductBootstrap> loadBootstrap({required String product}) async {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final uri = Uri.parse(
      '$normalizedBaseUrl/config/bootstrap',
    ).replace(queryParameters: <String, String>{'product': product});

    if (cache != null) {
      final result = await cache!.getOrFetch(
        uri: uri,
        cacheKey: 'config_bootstrap.$product',
        headers: headersProvider?.call() ?? const <String, String>{},
      );

      if (result is! HttpJsonCacheSuccess) {
        final failure = result as HttpJsonCacheFailure;
        throw StateError(failure.message);
      }

      return ProductBootstrap.fromJson(result.json);
    }

    final response = await _client.get(uri, headers: headersProvider?.call());
    if (response.statusCode != 200) {
      throw StateError('Bootstrap returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Bootstrap returned a non-object response');
    }

    return ProductBootstrap.fromJson(
      Map<String, Object?>.from(decoded.cast<String, Object?>()),
    );
  }

  Future<ConfigSnapshot> loadSnapshot({
    required String snapshotId,
    String? configBaseUrl,
  }) async {
    final resolvedBase = (configBaseUrl != null && configBaseUrl.isNotEmpty)
        ? configBaseUrl
        : baseUrl;

    final normalizedBaseUrl = resolvedBase.endsWith('/')
        ? resolvedBase.substring(0, resolvedBase.length - 1)
        : resolvedBase;

    final encoded = Uri.encodeComponent(snapshotId);
    final uri = Uri.parse('$normalizedBaseUrl/config/snapshots/$encoded');

    if (cache != null) {
      final result = await cache!.getOrFetch(
        uri: uri,
        cacheKey: 'config_snapshot.$snapshotId',
        headers: headersProvider?.call() ?? const <String, String>{},
      );

      if (result is! HttpJsonCacheSuccess) {
        final failure = result as HttpJsonCacheFailure;
        throw StateError(failure.message);
      }

      return ConfigSnapshot.fromJson(result.json);
    }

    final response = await _client.get(uri, headers: headersProvider?.call());
    if (response.statusCode != 200) {
      throw StateError('Config snapshot returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Config snapshot returned a non-object response',
      );
    }

    return ConfigSnapshot.fromJson(
      Map<String, Object?>.from(decoded.cast<String, Object?>()),
    );
  }
}
