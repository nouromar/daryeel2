import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../config/daryeel_client_config.dart';
import '../runtime/daryeel_runtime_session.dart';
import '../runtime/daryeel_runtime_view_model.dart';
import 'runtime_inspector_screen.dart';
import 'runtime_session_scope.dart';
import 'schema_service_screen.dart';
import 'schema_status_banner.dart';

class DaryeelClientAppShell extends StatefulWidget {
  const DaryeelClientAppShell({
    required this.config,
    required this.schemaBaseUrl,
    this.configBaseUrl = '',
    this.apiBaseUrl = '',
    this.requestHeadersProvider,
    super.key,
  });

  final DaryeelClientAppConfig config;
  final String schemaBaseUrl;

  /// Base URL for bootstrap + config snapshot delivery.
  ///
  /// When unset, defaults to using [schemaBaseUrl].
  final String configBaseUrl;

  /// Base URL for the API service (used for host allowlisting).
  final String apiBaseUrl;

  /// Extra headers to attach to runtime requests (schema/theme/bootstrap) and
  /// API queries executed via [SchemaQueryStore].
  ///
  /// Common use: `Authorization: Bearer ...`.
  final Map<String, String> Function()? requestHeadersProvider;

  @override
  State<DaryeelClientAppShell> createState() => _DaryeelClientAppShellState();
}

class _DaryeelClientAppShellState extends State<DaryeelClientAppShell> {
  late final SchemaFormStore _formStore = SchemaFormStore();

  DaryeelRuntimeSession? _session;
  late Future<DaryeelRuntimeViewModel> _vmFuture;

  @override
  void initState() {
    super.initState();
    _rebuildSession();
  }

  @override
  void didUpdateWidget(covariant DaryeelClientAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schemaBaseUrl != widget.schemaBaseUrl ||
        oldWidget.configBaseUrl != widget.configBaseUrl ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.config != widget.config) {
      _rebuildSession();
    }
  }

  String get _effectiveSchemaBaseUrl {
    if (widget.schemaBaseUrl.isNotEmpty) return widget.schemaBaseUrl;
    if (widget.configBaseUrl.isNotEmpty) return widget.configBaseUrl;
    return '';
  }

  String get _effectiveConfigBaseUrl {
    if (widget.configBaseUrl.isNotEmpty) return widget.configBaseUrl;
    return _effectiveSchemaBaseUrl;
  }

  void _rebuildSession() {
    _session?.dispose();

    final effectiveSchemaBaseUrl = _effectiveSchemaBaseUrl;
    final effectiveConfigBaseUrl = _effectiveConfigBaseUrl;

    final next = DaryeelRuntimeSession(
      appConfig: widget.config,
      schemaBaseUrl: effectiveSchemaBaseUrl,
      configBaseUrl: effectiveConfigBaseUrl,
      apiBaseUrl: widget.apiBaseUrl,
      diagnosticsBufferMaxEvents: widget.config.diagnosticsBufferMaxEvents,
      requestHeadersProvider: widget.requestHeadersProvider,
    );

    _session = next;
    _vmFuture = next.loadBootstrapScreen();
  }

  @override
  void dispose() {
    _formStore.dispose();
    _session?.dispose();
    super.dispose();
  }

  Widget _wrapWithSession(Widget child) {
    final session = _session;
    if (session == null) return child;
    return RuntimeSessionScope(
      session: session,
      child: SchemaQueryScope(
        store: session.queryStore,
        child: SchemaStateScope(store: session.stateStore, child: child),
      ),
    );
  }

  ThemeData _baselineTheme() =>
      widget.config.runtime.resolveLocalTheme(const <String, Object?>{});

  Widget _buildLoadingApp() {
    return _wrapWithSession(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _baselineTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }

  Widget _buildBootstrapErrorApp(Object? error) {
    return _wrapWithSession(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _baselineTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load the schema.\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParseErrorApp(LoadedScreen loadedScreen) {
    return _wrapWithSession(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: loadedScreen.theme,
        darkTheme: loadedScreen.darkTheme,
        themeMode: loadedScreen.themeMode,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Schema parse failed:\n${loadedScreen.parseErrors.join('\n')}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  SchemaRenderer _buildRenderer(DaryeelRuntimeViewModel vm) {
    final loadedScreen = vm.screen;
    final screenSchema = loadedScreen.schema!;

    return SchemaRenderer(
      rootNode: screenSchema.root,
      registry: widget.config.buildRegistry(
        screen: screenSchema,
        actionDispatcher: vm.actionDispatcher,
        visibility: vm.visibility,
        diagnostics: vm.diagnostics,
        diagnosticsContext: vm.rendererDiagnosticsContext,
      ),
    );
  }

  String _schemaSourceWireValue(LoadedScreen loadedScreen) {
    return (loadedScreen.schemaLadderSource ??
            switch (loadedScreen.source) {
              ScreenLoadSource.remote => SchemaLadderSource.selector,
              ScreenLoadSource.bundled => SchemaLadderSource.bundled,
              ScreenLoadSource.fallback => SchemaLadderSource.bundledFallback,
            })
        .wireValue;
  }

  String _themeSourceWireValue(LoadedScreen loadedScreen) {
    return (loadedScreen.themeSource ?? ThemeLadderSource.local).wireValue;
  }

  Map<String, WidgetBuilder> _buildRoutes(LoadedScreen loadedScreen) {
    final schemaSourceWire = _schemaSourceWireValue(loadedScreen);
    final themeSourceWire = _themeSourceWireValue(loadedScreen);

    return <String, WidgetBuilder>{
      ...widget.config.additionalRoutes,
      widget.config.schemaServiceRouteName: (context) =>
          SchemaServiceScreen(baseUrl: _effectiveSchemaBaseUrl),
      if (kDebugMode)
        widget.config.debugInspectorRouteName: (context) =>
            RuntimeInspectorScreen(
              schemaBaseUrl: _effectiveSchemaBaseUrl,
              configBaseUrl: _effectiveConfigBaseUrl,
              apiBaseUrl: widget.apiBaseUrl,
              bootstrapVersion: loadedScreen.bootstrapVersion,
              bootstrapProduct: loadedScreen.bootstrapProduct,
              bootstrapConfigSnapshotId: loadedScreen.bootstrapConfigSnapshotId,
              configSnapshotId: loadedScreen.configSnapshotId,
              schemaBundleId: loadedScreen.bundle.schemaId,
              schemaBundleVersion: loadedScreen.bundle.schemaVersion,
              schemaDocId: loadedScreen.bundle.docId,
              schemaSource: schemaSourceWire,
              schemaDocument: loadedScreen.bundle.document,
              parseErrors: loadedScreen.parseErrors,
              refErrors: loadedScreen.refErrors,
              themeId: loadedScreen.resolvedThemeId,
              themeMode: loadedScreen.resolvedThemeMode,
              themeDocId: loadedScreen.themeDocId,
              themeSource: themeSourceWire,
              diagnostics:
                  (_session?.inMemoryDiagnosticsSink?.events ??
                          const <DiagnosticEvent>[])
                      .toList(growable: false),
            ),
    };
  }

  Widget _buildLoadedApp(DaryeelRuntimeViewModel vm) {
    final loadedScreen = vm.screen;

    // Ensure the shared `$state` store is wired to this screen's diagnostics.
    _session?.stateStore.configureDiagnostics(
      diagnostics: vm.diagnostics,
      diagnosticsContext: vm.rendererDiagnosticsContext,
    );

    final session = _session;
    if (session != null) {
      Map<String, String> buildDefaultHeaders() {
        final correlation = session.diagnosticsReporter.buildCorrelationHeaders(
          schemaVersion:
              '${loadedScreen.bundle.schemaId}@${loadedScreen.bundle.schemaVersion}',
          configSnapshotId: loadedScreen.configSnapshotId,
        );

        Map<String, String> extra;
        try {
          extra =
              session.requestHeadersProvider?.call() ??
              const <String, String>{};
        } catch (_) {
          extra = const <String, String>{};
        }

        if (extra.isEmpty) return correlation;
        if (correlation.isEmpty) return extra;

        // Let the runtime keep control of correlation IDs.
        return <String, String>{...extra, ...correlation};
      }

      session.queryStore.configure(
        diagnostics: vm.diagnostics,
        diagnosticsContext: <String, Object?>{
          ...vm.rendererDiagnosticsContext,
          'screenLoad': <String, Object?>{
            'id': session.diagnosticsReporter.screenLoadId,
          },
        },
        defaultHeadersProvider: buildDefaultHeaders,
      );
    }

    if (loadedScreen.schema == null) {
      return _buildParseErrorApp(loadedScreen);
    }

    final renderer = _buildRenderer(vm);
    final routes = _buildRoutes(loadedScreen);

    return _wrapWithSession(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: loadedScreen.theme,
        darkTheme: loadedScreen.darkTheme,
        themeMode: loadedScreen.themeMode,
        routes: routes,
        home: Scaffold(
          appBar: AppBar(
            title: kDebugMode
                ? Builder(
                    builder: (navigatorContext) {
                      return InkWell(
                        onLongPress: () {
                          Navigator.of(
                            navigatorContext,
                          ).pushNamed(widget.config.debugInspectorRouteName);
                        },
                        child: Text(widget.config.appBarTitle),
                      );
                    },
                  )
                : Text(widget.config.appBarTitle),
          ),
          body: Column(
            children: [
              SchemaStatusBanner(screen: loadedScreen),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    'schema:${loadedScreen.bundle.schemaId}:${loadedScreen.bundle.docId ?? loadedScreen.bundle.schemaVersion}',
                  ),
                  child: SchemaStateScopeHost(
                    child: SchemaFormScope(
                      store: _formStore,
                      child: renderer.render(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DaryeelRuntimeViewModel>(
      future: _vmFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLoadingApp();
        }
        if (snapshot.hasError) {
          return _buildBootstrapErrorApp(snapshot.error);
        }
        final vm = snapshot.data!;
        return _buildLoadedApp(vm);
      },
    );
  }
}
