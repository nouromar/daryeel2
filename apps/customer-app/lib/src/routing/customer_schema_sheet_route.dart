import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart'
    show DaryeelRuntimeViewModel;
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/runtime_session_scope.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/schema_node_wrapper.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/runtime/runtime_request_headers.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'customer_schema_screen_route.dart';

/// Presents a schema screen in a modal bottom sheet.
///
/// Contract (Navigator arguments): same as [CustomerSchemaScreenRoute].
class CustomerSchemaSheetRoute {
  static const name = 'customer.schema_sheet';

  static WidgetBuilder builder() {
    return (context) {
      final rawArgs = ModalRoute.of(context)?.settings.arguments;
      final request = CustomerSchemaScreenRouteRequest.tryParse(rawArgs);
      if (request == null) {
        return _InvalidRouteArgsScreen(rawArgs: rawArgs);
      }

      return _SchemaSheetLauncher(request: request);
    };
  }
}

class _SchemaSheetLauncher extends StatefulWidget {
  const _SchemaSheetLauncher({required this.request});

  final CustomerSchemaScreenRouteRequest request;

  @override
  State<_SchemaSheetLauncher> createState() => _SchemaSheetLauncherState();
}

class _SchemaSheetLauncherState extends State<_SchemaSheetLauncher> {
  bool _launched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_launched) return;
    _launched = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // ScreenTemplate already applies SafeArea; avoid double-insets.
        useSafeArea: false,
        builder: (sheetContext) {
          return FractionallySizedBox(
            heightFactor: 0.85,
            child: _CustomerSchemaSheetScreen(request: widget.request),
          );
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    // A lightweight placeholder while the sheet is shown.
    return const Scaffold(body: SizedBox.shrink());
  }
}

class _CustomerSchemaSheetScreen extends StatefulWidget {
  const _CustomerSchemaSheetScreen({required this.request});

  final CustomerSchemaScreenRouteRequest request;

  @override
  State<_CustomerSchemaSheetScreen> createState() =>
      _CustomerSchemaSheetScreenState();
}

class _CustomerSchemaSheetScreenState
    extends State<_CustomerSchemaSheetScreen> {
  late final SchemaFormStore _formStore = SchemaFormStore();
  Future<DaryeelRuntimeViewModel>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= RuntimeSessionScope.of(context).loadScreen(
      screenId: widget.request.screenId,
      service: widget.request.service,
    );
  }

  @override
  void dispose() {
    _formStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<DaryeelRuntimeViewModel>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load screen: ${widget.request.screenId}\n${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        final vm = snapshot.data!;
        final session = RuntimeSessionScope.of(context);
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
          defaultHeadersProvider: () => mergeRuntimeRequestHeaders(
            correlationHeaders: session.diagnosticsReporter
                .buildCorrelationHeaders(
                  schemaVersion:
                      '${loaded.bundle.schemaId}@${loaded.bundle.schemaVersion}',
                  configSnapshotId: loaded.configSnapshotId,
                ),
            requestHeadersProvider: session.requestHeadersProvider,
          ),
        );

        if (loaded.schema == null) {
          final errors = loaded.parseErrors.map((e) => e.toString()).join('\n');
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Schema parse failed:\n$errors',
              textAlign: TextAlign.center,
            ),
          );
        }

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
          'schema_sheet:${loaded.bundle.schemaId}:$schemaIdentity',
        );

        return KeyedSubtree(
          key: schemaTreeKey,
          child: Theme(
            data: loaded.theme,
            child: SchemaRouteScope(
              params: widget.request.params,
              child: SchemaStateScopeHost(
                child: SchemaFormScope(
                  store: _formStore,
                  child: renderer.render(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InvalidRouteArgsScreen extends StatelessWidget {
  const _InvalidRouteArgsScreen({required this.rawArgs});

  final Object? rawArgs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invalid route arguments')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Unable to parse schema route arguments.\n\n'
          'Expected a JSON object with at least: {"screenId": "..."}.\n\n'
          'Received: ${rawArgs.runtimeType}\n$rawArgs',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
