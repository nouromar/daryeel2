import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import '../schema/customer_schema_compatibility.dart';
import '../schema/fallback_fragment_documents.dart';
import '../schema/fallback_schema_bundle.dart';
import '../ui/customer_component_registry.dart';
import '../ui/customer_theme.dart';

class CustomerApp extends StatefulWidget {
  const CustomerApp({
    super.key,
    this.schemaBaseUrl = const String.fromEnvironment('SCHEMA_BASE_URL'),
  });

  final String schemaBaseUrl;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  @override
  Widget build(BuildContext context) {
    return DaryeelClientAppShell(
      schemaBaseUrl: widget.schemaBaseUrl,
      config: DaryeelClientAppConfig(
        runtime: DaryeelRuntimeConfig(
          appId: 'customer-app',
          product: 'customer_app',
          fallbackBundle: fallbackCustomerHomeBundle,
          fallbackFragmentDocuments: fallbackFragmentDocuments,
          resolveLocalTheme: resolveCustomerTheme,
          resolveThemeMode: resolveThemeMode,
          defaultThemeId: 'customer-default',
          defaultThemeMode: 'light',
          buildCompatibilityChecker: (overlay) =>
              CustomerSchemaCompatibilityChecker(overlay: overlay),
        ),
        appBarTitle: 'Daryeel2 Customer',
        buildRegistry:
            ({
              required ScreenSchema screen,
              required SchemaActionDispatcher actionDispatcher,
              required SchemaVisibilityContext visibility,
              RuntimeDiagnostics? diagnostics,
              Map<String, Object?> diagnosticsContext =
                  const <String, Object?>{},
            }) {
              return buildCustomerComponentRegistry(
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
