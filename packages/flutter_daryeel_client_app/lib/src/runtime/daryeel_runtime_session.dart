import 'package:flutter/foundation.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/daryeel_client_config.dart';
import '../state/schema_state_persistence.dart';
import 'daryeel_diagnostics_reporter.dart';
import 'daryeel_runtime_controller.dart';
import 'daryeel_runtime_view_model.dart';

/// Long-lived runtime container owned by the app shell.
///
/// This is intentionally shared across all schema screens so that:
/// - caching/pinning policies remain consistent
/// - diagnostics sinks (including debug inspector buffers) are shared
/// - HTTP resources are reused and can be closed deterministically
class DaryeelRuntimeSession {
  DaryeelRuntimeSession({
    required this.appConfig,
    required this.schemaBaseUrl,
    required this.configBaseUrl,
    required this.apiBaseUrl,
    required int diagnosticsBufferMaxEvents,
    this.requestHeadersProvider,
    http.Client? httpClient,
  }) : _ownsHttpClient = (httpClient == null) {
    _httpClient = httpClient ?? http.Client();

    inMemoryDiagnosticsSink = kDebugMode
        ? InMemoryDiagnosticsSink(maxEvents: diagnosticsBufferMaxEvents)
        : null;

    diagnosticsReporter = DaryeelDiagnosticsReporter(
      appId: appConfig.runtime.appId,
      diagnosticsSinkOverride: null,
      additionalSinks: inMemoryDiagnosticsSink == null
          ? const <DiagnosticsSink>[]
          : <DiagnosticsSink>[inMemoryDiagnosticsSink!],
    );

    controller = DaryeelRuntimeController(
      config: appConfig.runtime,
      schemaBaseUrl: schemaBaseUrl,
      configBaseUrl: configBaseUrl,
      apiBaseUrl: apiBaseUrl,
      requestHeadersProvider: requestHeadersProvider,
      httpClient: _httpClient,
      diagnosticsReporter: diagnosticsReporter,
      additionalDiagnosticsSinks: inMemoryDiagnosticsSink == null
          ? const <DiagnosticsSink>[]
          : <DiagnosticsSink>[inMemoryDiagnosticsSink!],
    );

    queryStore = SchemaQueryStore(apiBaseUrl: apiBaseUrl, client: _httpClient);

    stateStore = SchemaStateStore();
  }

  final DaryeelClientAppConfig appConfig;
  final String schemaBaseUrl;
  final String configBaseUrl;
  final String apiBaseUrl;

  /// Extra headers to attach to all outbound runtime requests.
  ///
  /// Common use: `Authorization: Bearer ...`.
  final Map<String, String> Function()? requestHeadersProvider;

  late final SchemaQueryStore queryStore;
  late final SchemaStateStore stateStore;

  SchemaStatePersistenceController? _statePersistence;
  Future<void>? _stateRestoreFuture;

  Future<void> _ensureStatePersistenceInitialized() {
    final cfg = appConfig.runtime.statePersistence;
    if (cfg == null || cfg.paths.isEmpty) {
      return Future<void>.value();
    }

    return _stateRestoreFuture ??= () async {
      final prefs = await SharedPreferences.getInstance();
      final key = (cfg.prefsKey != null && cfg.prefsKey!.trim().isNotEmpty)
          ? cfg.prefsKey!.trim()
          : SchemaStatePersistenceController.defaultPrefsKey(
              product: appConfig.runtime.product,
              appId: appConfig.runtime.appId,
            );

      final controller = SchemaStatePersistenceController(
        prefs: prefs,
        prefsKey: key,
        paths: cfg.paths,
        debounce: Duration(milliseconds: cfg.debounceMilliseconds),
      );

      await controller.restoreInto(stateStore);
      controller.startAutoSave(stateStore);
      _statePersistence = controller;
    }();
  }

  late final DaryeelRuntimeController controller;
  late final InMemoryDiagnosticsSink? inMemoryDiagnosticsSink;

  late final DaryeelDiagnosticsReporter diagnosticsReporter;

  late final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<DaryeelRuntimeViewModel> loadBootstrapScreen() {
    return _ensureStatePersistenceInitialized()
        .then((_) => controller.loadInitialScreen());
  }

  Future<DaryeelRuntimeViewModel> loadScreen({
    required String screenId,
    String? service,
  }) {
    return _ensureStatePersistenceInitialized().then(
      (_) => controller.loadInitialScreen(
        screenIdOverride: screenId,
        serviceOverride: service,
      ),
    );
  }

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    // No explicit disposal needed; keep best-effort cleanup minimal.
    _statePersistence?.dispose();
    inMemoryDiagnosticsSink?.clear();
    queryStore.dispose();
    stateStore.dispose();
  }
}
