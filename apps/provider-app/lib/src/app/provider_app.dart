import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import '../schema/fallback_fragment_documents.dart';
import '../schema/fallback_schema_bundle.dart';
import '../schema/provider_schema_compatibility.dart';
import '../ui/provider_component_registry.dart';
import '../ui/provider_theme.dart';

class ProviderApp extends StatefulWidget {
  const ProviderApp({
    super.key,
    this.schemaBaseUrl = const String.fromEnvironment('SCHEMA_BASE_URL'),
    this.configBaseUrl = const String.fromEnvironment('CONFIG_BASE_URL'),
    this.apiBaseUrl = const String.fromEnvironment('API_BASE_URL'),
  });

  final String schemaBaseUrl;
  final String configBaseUrl;
  final String apiBaseUrl;

  @override
  State<ProviderApp> createState() => _ProviderAppState();
}

class _ProviderAppState extends State<ProviderApp> {
  @override
  Widget build(BuildContext context) {
    return DaryeelClientAppShell(
      schemaBaseUrl: widget.schemaBaseUrl,
      configBaseUrl: widget.configBaseUrl,
      apiBaseUrl: widget.apiBaseUrl,
      config: DaryeelClientAppConfig(
        runtime: DaryeelRuntimeConfig(
          appId: 'provider-app',
          product: 'provider_app',
          fallbackBundle: fallbackProviderHomeBundle,
          fallbackFragmentDocuments: fallbackFragmentDocuments,
          enableSchemaPinning: true,
          resolveLocalTheme: resolveProviderTheme,
          resolveThemeMode: resolveThemeMode,
          defaultThemeId: 'provider-default',
          defaultThemeMode: 'light',
          buildCompatibilityChecker: (overlay) =>
              ProviderSchemaCompatibilityChecker(overlay: overlay),
        ),
        appBarTitle: 'Daryeel2 Provider',
        buildRegistry:
            ({
              required ScreenSchema screen,
              required SchemaActionDispatcher actionDispatcher,
              required SchemaVisibilityContext visibility,
              RuntimeDiagnostics? diagnostics,
              Map<String, Object?> diagnosticsContext =
                  const <String, Object?>{},
            }) {
              return buildProviderComponentRegistry(
                screen: screen,
                actionDispatcher: actionDispatcher,
                visibility: visibility,
                diagnostics: diagnostics,
                diagnosticsContext: diagnosticsContext,
              );
            },
      ),
    );
  }
}
