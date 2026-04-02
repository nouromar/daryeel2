import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../config/daryeel_client_config.dart';
import '../runtime/daryeel_runtime_controller.dart';
import '../runtime/daryeel_runtime_view_model.dart';
import 'runtime_inspector_screen.dart';
import 'schema_service_screen.dart';
import 'schema_status_banner.dart';

class DaryeelClientAppShell extends StatefulWidget {
  const DaryeelClientAppShell({
    required this.config,
    required this.schemaBaseUrl,
    super.key,
  });

  final DaryeelClientAppConfig config;
  final String schemaBaseUrl;

  @override
  State<DaryeelClientAppShell> createState() => _DaryeelClientAppShellState();
}

class _DaryeelClientAppShellState extends State<DaryeelClientAppShell> {
  late final SchemaFormStore _formStore = SchemaFormStore();

  late final InMemoryDiagnosticsSink? _inMemoryDiagnosticsSink = kDebugMode
      ? InMemoryDiagnosticsSink(
          maxEvents: widget.config.diagnosticsBufferMaxEvents,
        )
      : null;

  late DaryeelRuntimeController _controller;
  late Future<DaryeelRuntimeViewModel> _vmFuture;

  @override
  void initState() {
    super.initState();
    _rebuildController();
  }

  @override
  void didUpdateWidget(covariant DaryeelClientAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schemaBaseUrl != widget.schemaBaseUrl ||
        oldWidget.config != widget.config) {
      _rebuildController();
    }
  }

  void _rebuildController() {
    final inMemory = _inMemoryDiagnosticsSink;
    _controller = DaryeelRuntimeController(
      config: widget.config.runtime,
      schemaBaseUrl: widget.schemaBaseUrl,
      additionalDiagnosticsSinks: inMemory == null
          ? const <DiagnosticsSink>[]
          : <DiagnosticsSink>[inMemory],
    );
    _vmFuture = _controller.loadInitialScreen();
  }

  @override
  void dispose() {
    _formStore.dispose();
    super.dispose();
  }

  ThemeData _baselineTheme() =>
      widget.config.runtime.resolveLocalTheme(const <String, Object?>{});

  Widget _buildLoadingApp() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _baselineTheme(),
      home: const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }

  Widget _buildBootstrapErrorApp(Object? error) {
    return MaterialApp(
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
    );
  }

  Widget _buildParseErrorApp(LoadedScreen loadedScreen) {
    return MaterialApp(
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
      widget.config.schemaServiceRouteName: (context) =>
          SchemaServiceScreen(baseUrl: widget.schemaBaseUrl),
      if (kDebugMode)
        widget.config.debugInspectorRouteName: (context) =>
            RuntimeInspectorScreen(
              configSnapshotId: loadedScreen.configSnapshotId,
              schemaDocId: loadedScreen.bundle.docId,
              schemaSource: schemaSourceWire,
              themeDocId: loadedScreen.themeDocId,
              themeSource: themeSourceWire,
              diagnostics:
                  (_inMemoryDiagnosticsSink?.events ??
                          const <DiagnosticEvent>[])
                      .toList(growable: false),
            ),
    };
  }

  Widget _buildLoadedApp(DaryeelRuntimeViewModel vm) {
    final loadedScreen = vm.screen;
    if (loadedScreen.schema == null) {
      return _buildParseErrorApp(loadedScreen);
    }

    final renderer = _buildRenderer(vm);
    final routes = _buildRoutes(loadedScreen);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: loadedScreen.theme,
      darkTheme: loadedScreen.darkTheme,
      themeMode: loadedScreen.themeMode,
      routes: routes,
      home: Scaffold(
        appBar: AppBar(title: Text(widget.config.appBarTitle)),
        body: Column(
          children: [
            SchemaStatusBanner(screen: loadedScreen),
            Expanded(
              child: SchemaFormScope(
                store: _formStore,
                child: renderer.render(),
              ),
            ),
          ],
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
