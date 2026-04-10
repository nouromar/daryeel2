import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../runtime/daryeel_runtime_session.dart';
import '../runtime/daryeel_runtime_view_model.dart';
import 'runtime_inspector_screen.dart';
import 'runtime_session_scope.dart';
import 'schema_node_wrapper.dart';

const int _debugScreenLoadDelayMs = int.fromEnvironment(
  'DARYEEL_DEBUG_SCREEN_LOAD_DELAY_MS',
  defaultValue: 0,
);

typedef SchemaRoutedScreenAppBarActionsBuilder = List<Widget> Function(
    BuildContext context, LoadedScreen loaded);

class SchemaRoutedScreen extends StatefulWidget {
  const SchemaRoutedScreen({
    required this.screenId,
    this.service,
    this.title,
    this.routeParams,
    this.appBarActionsBuilder,
    super.key,
  });

  final String screenId;
  final String? service;
  final String? title;

  /// Optional route params exposed to schema interpolation via `${params.*}`.
  ///
  /// When omitted, params are derived from `Navigator.pushNamed(..., arguments:)`.
  /// Providing this lets hosts sanitize/guard route arguments while still
  /// allowing schema-driven screens to consume safe params.
  final Map<String, Object?>? routeParams;

  /// Optional host-provided app bar actions.
  ///
  /// This is intentionally app-owned (not schema-owned) so apps can keep
  /// platform-consistent chrome while still wiring stateful affordances like
  /// cart badges.
  final SchemaRoutedScreenAppBarActionsBuilder? appBarActionsBuilder;

  @override
  State<SchemaRoutedScreen> createState() => _SchemaRoutedScreenState();
}

class _SchemaRoutedScreenState extends State<SchemaRoutedScreen> {
  late final SchemaFormStore _formStore = SchemaFormStore();

  DaryeelRuntimeSession? _session;
  Future<DaryeelRuntimeViewModel>? _future;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = RuntimeSessionScope.of(context);
    if (!identical(_session, next)) {
      _session = next;
      _future = null;
      _scheduleLoad(next);
    }
  }

  void _scheduleLoad(DaryeelRuntimeSession session) {
    if (session.schemaBaseUrl.isEmpty) return;

    // Defer work until after the first frame so route transitions paint
    // immediately and the loading UI is visible right away.
    final generation = ++_loadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!identical(_session, session)) return;
      if (_loadGeneration != generation) return;

      setState(() {
        _future = _load(session);
      });
    });
  }

  Future<DaryeelRuntimeViewModel> _load(DaryeelRuntimeSession session) async {
    if (kDebugMode && _debugScreenLoadDelayMs > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: _debugScreenLoadDelayMs),
      );
    }

    return session.loadScreen(
      screenId: widget.screenId,
      service: widget.service,
    );
  }

  @override
  void didUpdateWidget(covariant SchemaRoutedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenId != widget.screenId ||
        oldWidget.service != widget.service) {
      final session = _session;
      if (session != null) {
        _future = null;
        _scheduleLoad(session);
      }
    }
  }

  @override
  void dispose() {
    _formStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session ?? RuntimeSessionScope.of(context);
    final title = widget.title ?? widget.screenId;

    Widget inspectorTitle({LoadedScreen? loaded}) {
      if (!kDebugMode || loaded == null) return Text(title);

      String schemaSourceWireValue(LoadedScreen loadedScreen) {
        return (loadedScreen.schemaLadderSource ??
                switch (loadedScreen.source) {
                  ScreenLoadSource.remote => SchemaLadderSource.selector,
                  ScreenLoadSource.bundled => SchemaLadderSource.bundled,
                  ScreenLoadSource.fallback =>
                    SchemaLadderSource.bundledFallback,
                })
            .wireValue;
      }

      String themeSourceWireValue(LoadedScreen loadedScreen) {
        return (loadedScreen.themeSource ?? ThemeLadderSource.local).wireValue;
      }

      return InkWell(
        onLongPress: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RuntimeInspectorScreen(
                schemaBaseUrl: session.schemaBaseUrl,
                configBaseUrl: session.configBaseUrl,
                apiBaseUrl: session.apiBaseUrl,
                bootstrapVersion: loaded.bootstrapVersion,
                bootstrapProduct: loaded.bootstrapProduct,
                bootstrapConfigSnapshotId: loaded.bootstrapConfigSnapshotId,
                configSnapshotId: loaded.configSnapshotId,
                schemaBundleId: loaded.bundle.schemaId,
                schemaBundleVersion: loaded.bundle.schemaVersion,
                schemaDocId: loaded.bundle.docId,
                schemaSource: schemaSourceWireValue(loaded),
                schemaDocument: loaded.bundle.document,
                parseErrors: loaded.parseErrors,
                refErrors: loaded.refErrors,
                themeId: loaded.resolvedThemeId,
                themeMode: loaded.resolvedThemeMode,
                themeDocId: loaded.themeDocId,
                themeSource: themeSourceWireValue(loaded),
                diagnostics: (session.inMemoryDiagnosticsSink?.events ??
                        const <DiagnosticEvent>[])
                    .toList(growable: false),
              ),
            ),
          );
        },
        child: Text(title),
      );
    }

    if (session.schemaBaseUrl.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: inspectorTitle()),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Schema base URL is not configured.\n'
            'Set SCHEMA_BASE_URL (or CONFIG_BASE_URL) to load routed screens from the backend.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final future = _future;
    if (future == null) {
      return Scaffold(
        appBar: AppBar(title: inspectorTitle()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<DaryeelRuntimeViewModel>(
      future: future,
      builder: (context, snapshot) {
        late final Widget current;

        if (snapshot.connectionState != ConnectionState.done) {
          current = const KeyedSubtree(
            key: ValueKey<String>('schema_routed_screen.loading'),
            child: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        } else if (snapshot.hasError) {
          current = KeyedSubtree(
            key: const ValueKey<String>('schema_routed_screen.error'),
            child: Scaffold(
              appBar: AppBar(title: inspectorTitle()),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load screen: ${widget.screenId}\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        } else {
          final vm = snapshot.data!;
          final loaded = vm.screen;

          // Ensure the shared `$state` store is wired to this screen's diagnostics.
          session.stateStore.configureDiagnostics(
            diagnostics: vm.diagnostics,
            diagnosticsContext: vm.rendererDiagnosticsContext,
          );

          session.queryStore.configure(
            diagnostics: vm.diagnostics,
            diagnosticsContext: <String, Object?>{
              ...vm.rendererDiagnosticsContext,
              'screenLoad': <String, Object?>{
                'id': session.diagnosticsReporter.screenLoadId,
              },
            },
            defaultHeadersProvider: () =>
                session.diagnosticsReporter.buildCorrelationHeaders(
              schemaVersion:
                  '${loaded.bundle.schemaId}@${loaded.bundle.schemaVersion}',
              configSnapshotId: loaded.configSnapshotId,
            ),
          );

          if (loaded.schema == null) {
            final errors =
                loaded.parseErrors.map((e) => e.toString()).join('\n');
            current = KeyedSubtree(
              key: const ValueKey<String>('schema_routed_screen.parse_error'),
              child: Scaffold(
                appBar: AppBar(
                  title: inspectorTitle(loaded: loaded),
                  actions: widget.appBarActionsBuilder?.call(context, loaded),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Schema parse failed:\n$errors',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          } else {
            final renderer = SchemaRenderer(
              rootNode: loaded.schema!.root,
              registry: session.appConfig.buildRegistry(
                screen: loaded.schema!,
                actionDispatcher: vm.actionDispatcher,
                visibility: vm.visibility,
                diagnostics: vm.diagnostics,
                diagnosticsContext: vm.rendererDiagnosticsContext,
              ),
              wrapperBuilder: buildVisibleWhenWrapperBuilder(
                visibility: vm.visibility,
                diagnostics: vm.diagnostics,
                diagnosticsContext: vm.rendererDiagnosticsContext,
              ),
            );

            final schemaIdentity =
                loaded.bundle.docId ?? loaded.bundle.schemaVersion;
            final schemaTreeKey = ValueKey<String>(
              'schema:${loaded.bundle.schemaId}:$schemaIdentity',
            );

            current = KeyedSubtree(
              key: schemaTreeKey,
              child: Theme(
                data: loaded.theme,
                child: Scaffold(
                  appBar: AppBar(
                    title: inspectorTitle(loaded: loaded),
                    actions: widget.appBarActionsBuilder?.call(context, loaded),
                  ),
                  body: SchemaRouteScope(
                    params: _coerceRouteParams(
                      widget.routeParams ??
                          ModalRoute.of(context)?.settings.arguments,
                    ),
                    child: SchemaStateScopeHost(
                      child: SchemaFormScope(
                        store: _formStore,
                        child: renderer.render(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: current,
        );
      },
    );
  }
}

Map<String, Object?> _coerceRouteParams(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) continue;
      out[entry.key as String] = entry.value;
    }
    return out;
  }
  return const <String, Object?>{};
}
