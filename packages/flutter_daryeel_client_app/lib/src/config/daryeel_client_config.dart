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
      required ConfigSnapshot? configSnapshot,
    });

SchemaActionPolicy defaultDaryeelActionPolicyBuilder({
  required String schemaBaseUrl,
  required ConfigSnapshot? configSnapshot,
}) {
  final schemaHost = Uri.tryParse(schemaBaseUrl)?.host;

  return SchemaActionPolicy(
    allowedActionTypes: <String>{
      SchemaActionTypes.navigate,
      SchemaActionTypes.openUrl,
      SchemaActionTypes.submitForm,
      SchemaActionTypes.trackEvent,
    },
    openUrlPolicy: UriPolicy(
      allowedSchemes: const <String>{'https'},
      allowedHosts: schemaHost == null || schemaHost.isEmpty
          ? const <String>{}
          : <String>{schemaHost},
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
    this.lkgConfigSnapshotPrefsKey,
    this.defaultThemeId,
    this.defaultThemeMode,
  });

  final String appId;
  final String product;

  final SchemaBundle fallbackBundle;
  final Map<String, Map<String, Object?>> fallbackFragmentDocuments;

  final DaryeelLocalThemeResolver resolveLocalTheme;
  final DaryeelThemeModeResolver resolveThemeMode;

  final DaryeelCompatibilityCheckerBuilder buildCompatibilityChecker;
  final DaryeelActionPolicyBuilder buildActionPolicy;

  /// Where to store last-known-good config snapshot JSON.
  ///
  /// If null, uses `daryeel_client.lkg_config_snapshot_json.<product>`.
  final String? lkgConfigSnapshotPrefsKey;

  /// Optional theme defaults if schema/bootstrap omit theme identifiers.
  final String? defaultThemeId;
  final String? defaultThemeMode;

  String get effectiveLkgConfigSnapshotPrefsKey {
    return lkgConfigSnapshotPrefsKey ??
        'daryeel_client.lkg_config_snapshot_json.$product';
  }
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
  });

  final DaryeelRuntimeConfig runtime;
  final String appBarTitle;
  final DaryeelRegistryBuilder buildRegistry;

  /// Debug-only in-memory diagnostics ring buffer.
  final int diagnosticsBufferMaxEvents;

  /// Stable route names used by the schema runtime.
  final String schemaServiceRouteName;
  final String debugInspectorRouteName;
}
