import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import '../schema/customer_schema_compatibility.dart';
import '../schema/fallback_fragment_documents.dart';
import '../schema/fallback_schema_bundle.dart';
import '../auth/customer_auth_gate.dart';
import '../auth/customer_auth_store.dart';
import '../routing/customer_schema_screen_route.dart';
import '../actions/customer_submit_form_handler.dart';
import '../ui/customer_component_registry.dart';
import '../ui/customer_theme.dart';

class CustomerApp extends StatefulWidget {
  const CustomerApp({
    super.key,
    this.schemaBaseUrl = const String.fromEnvironment('SCHEMA_BASE_URL'),
    this.configBaseUrl = const String.fromEnvironment('CONFIG_BASE_URL'),
    this.apiBaseUrl = const String.fromEnvironment('API_BASE_URL'),
  });

  final String schemaBaseUrl;
  final String configBaseUrl;
  final String apiBaseUrl;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  late final CustomerAuthStore _authStore = CustomerAuthStore();
  late final CustomerSubmitFormHandler _submitFormHandler =
      CustomerSubmitFormHandler();

  @override
  void dispose() {
    _submitFormHandler.dispose();
    _authStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedApp = DaryeelClientAppShell(
      schemaBaseUrl: widget.schemaBaseUrl,
      configBaseUrl: widget.configBaseUrl,
      apiBaseUrl: widget.apiBaseUrl,
      requestHeadersProvider: () {
        final token = _authStore.state.value.accessToken;
        if (token == null || token.trim().isEmpty) {
          return const <String, String>{};
        }

        final trimmed = token.trim();
        final value = trimmed.toLowerCase().startsWith('bearer ')
            ? trimmed
            : 'Bearer $trimmed';

        return <String, String>{'Authorization': value};
      },
      submitFormHandlerOverride: _submitFormHandler,
      config: DaryeelClientAppConfig(
        runtime: DaryeelRuntimeConfig(
          appId: 'customer-app',
          product: 'customer_app',
          fallbackBundle: fallbackCustomerHomeBundle,
          fallbackFragmentDocuments: fallbackFragmentDocuments,
          enableSchemaPinning: false,
          enableThemePinning: false,
          resolveLocalTheme: resolveCustomerTheme,
          resolveThemeMode: resolveThemeMode,
          defaultThemeId: 'custome-black-white-clear',
          defaultThemeMode: 'light',
          buildCompatibilityChecker: (overlay) =>
              CustomerSchemaCompatibilityChecker(overlay: overlay),
          statePersistence: const SchemaStatePersistenceConfig(
            paths: <String>['pharmacy.cart'],
          ),
        ),
        appBarTitle: 'Daryeel2 Customer',
        additionalRoutes: <String, WidgetBuilder>{
          CustomerSchemaScreenRoute.name: CustomerSchemaScreenRoute.builder(),
        },
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

    return CustomerAuthGate(
      authStore: _authStore,
      apiBaseUrl: widget.apiBaseUrl,
      authenticatedApp: authenticatedApp,
    );
  }
}
