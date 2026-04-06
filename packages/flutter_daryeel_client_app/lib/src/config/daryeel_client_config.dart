import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../schema/bootstrap_loader.dart';

typedef DaryeelLocalThemeResolver =
    ThemeData Function(Map<String, Object?> document, {String? overrideMode});

typedef DaryeelThemeModeResolver =
    ThemeMode Function(Map<String, Object?> document);

typedef DaryeelRegistryBuilder =
    SchemaWidgetRegistry Function({
      required ScreenSchema screen,
      required SchemaActionDispatcher actionDispatcher,
      required SchemaVisibilityContext visibility,
      RuntimeDiagnostics? diagnostics,
      Map<String, Object?> diagnosticsContext,
    });

typedef DaryeelCompatibilityCheckerBuilder =
    SchemaCompatibilityChecker Function(
      SchemaCompatibilityPolicyOverlay? overlay,
    );

typedef DaryeelActionPolicyBuilder =
    SchemaActionPolicy Function({
      required String schemaBaseUrl,
      required String apiBaseUrl,
      required ConfigSnapshot? configSnapshot,
    });

SchemaActionPolicy defaultDaryeelActionPolicyBuilder({
  required String schemaBaseUrl,
  required String apiBaseUrl,
  required ConfigSnapshot? configSnapshot,
}) {
  final schemaHost = Uri.tryParse(schemaBaseUrl)?.host;
  final apiHost = Uri.tryParse(apiBaseUrl)?.host;

  final allowedHosts = <String>{
    if (schemaHost != null && schemaHost.isNotEmpty) schemaHost,
    if (apiHost != null && apiHost.isNotEmpty) apiHost,
  };

  return SchemaActionPolicy(
    allowedActionTypes: <String>{
      SchemaActionTypes.navigate,
      SchemaActionTypes.openUrl,
      SchemaActionTypes.submitForm,
      SchemaActionTypes.trackEvent,
      SchemaActionTypes.setState,
      SchemaActionTypes.patchState,
    },
    openUrlPolicy: UriPolicy(
      allowedSchemes: const <String>{'https'},
      allowedHosts: allowedHosts,
    ),
  );
}

/// Runtime-only configuration for the shared schema client.
///
/// Apps provide domain-specific pieces (registry/theme/compatibility/fallback)
/// while the runtime provides caching, ladders, diagnostics, and action wiring.
class DaryeelRuntimeConfig {
  const DaryeelRuntimeConfig({
    required this.appId,
    required this.product,
    required this.fallbackBundle,
    required this.fallbackFragmentDocuments,
    required this.resolveLocalTheme,
    required this.resolveThemeMode,
    required this.buildCompatibilityChecker,
    this.buildActionPolicy = defaultDaryeelActionPolicyBuilder,
    this.statePersistence,
    this.lkgConfigSnapshotPrefsKey,
    this.defaultThemeId,
    this.defaultThemeMode,
    this.enableSchemaPinning = false,
    this.enableThemePinning = true,
  });

  final String appId;
  final String product;

  final SchemaBundle fallbackBundle;
  final Map<String, Map<String, Object?>> fallbackFragmentDocuments;

  final DaryeelLocalThemeResolver resolveLocalTheme;
  final DaryeelThemeModeResolver resolveThemeMode;

  final DaryeelCompatibilityCheckerBuilder buildCompatibilityChecker;
  final DaryeelActionPolicyBuilder buildActionPolicy;

  /// Optional persistence for selected `$state` paths.
  ///
  /// When configured, the runtime restores the persisted state once per session
  /// (best-effort) and auto-saves changes with a small debounce.
  final SchemaStatePersistenceConfig? statePersistence;

  /// Where to store last-known-good config snapshot JSON.
  ///
  /// If null, uses `daryeel_client.lkg_config_snapshot_json.<product>`.
  final String? lkgConfigSnapshotPrefsKey;

  /// Optional theme defaults if schema/bootstrap omit theme identifiers.
  final String? defaultThemeId;
  final String? defaultThemeMode;

  /// Enables promoting selector results to a pinned immutable docId.
  ///
  /// When disabled, the runtime always uses the selector/bundled fallback ladder
  /// and never reads/writes pinned schema docIds.
  final bool enableSchemaPinning;

  /// Enables promoting selector results to a pinned immutable docId for themes.
  ///
  /// When disabled, the runtime always uses the theme selector and never
  /// reads/writes pinned theme docIds.
  final bool enableThemePinning;

  String get effectiveLkgConfigSnapshotPrefsKey {
    return lkgConfigSnapshotPrefsKey ??
        'daryeel_client.lkg_config_snapshot_json.$product';
  }
}

/// Configuration for persisting selected `$state` paths.
///
/// This is intentionally simple: a list of dot-path prefixes that should be
/// persisted as JSON via `SharedPreferences`.
class SchemaStatePersistenceConfig {
  const SchemaStatePersistenceConfig({
    required this.paths,
    this.prefsKey,
    this.debounceMilliseconds = 400,
  });

  /// Dot-paths relative to `$state` root (e.g. `pharmacy.cart`).
  final List<String> paths;

  /// Optional override for the SharedPreferences key.
  ///
  /// If null, the runtime uses a stable key derived from `{product, appId}`.
  final String? prefsKey;

  /// Debounce window for auto-save writes.
  final int debounceMilliseconds;
}

/// UI-shell configuration for the shared schema client app.
class DaryeelClientAppConfig {
  const DaryeelClientAppConfig({
    required this.runtime,
    required this.appBarTitle,
    required this.buildRegistry,
    this.diagnosticsBufferMaxEvents = 200,
    this.schemaServiceRouteName = 'schema.service',
    this.debugInspectorRouteName = 'debug.inspector',
    this.additionalRoutes = const <String, WidgetBuilder>{},
  });

  final DaryeelRuntimeConfig runtime;
  final String appBarTitle;
  final DaryeelRegistryBuilder buildRegistry;

  /// Debug-only in-memory diagnostics ring buffer.
  final int diagnosticsBufferMaxEvents;

  /// Stable route names used by the schema runtime.
  final String schemaServiceRouteName;
  final String debugInspectorRouteName;

  /// Optional app-defined routes (e.g., domain screens not yet schema-driven).
  final Map<String, WidgetBuilder> additionalRoutes;
}
