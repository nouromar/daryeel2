import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerRemoteQuerySchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('RemoteQuery', (node, componentRegistry) {
    final key = (node.props['key'] as String?)?.trim();
    final path = (node.props['path'] as String?)?.trim();
    final dataPath = (node.props['dataPath'] as String?)?.trim();
    final rawParams = node.props['params'];

    if (key == null || key.isEmpty) {
      return const UnknownSchemaWidget(
          componentName: 'RemoteQuery(missing-key)');
    }
    if (path == null || path.isEmpty) {
      return const UnknownSchemaWidget(
          componentName: 'RemoteQuery(missing-path)');
    }

    return _RemoteQueryWidget(
      queryKey: key,
      path: path,
      dataPath: dataPath,
      rawParams: rawParams,
      registry: componentRegistry,
      node: node,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
    );
  });
}

class _RemoteQueryWidget extends StatefulWidget {
  const _RemoteQueryWidget({
    required this.queryKey,
    required this.path,
    required this.dataPath,
    required this.rawParams,
    required this.registry,
    required this.node,
    required this.diagnostics,
    required this.diagnosticsContext,
  });

  final String queryKey;
  final String path;
  final String? dataPath;
  final Object? rawParams;
  final SchemaWidgetRegistry registry;
  final ComponentNode node;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;

  @override
  State<_RemoteQueryWidget> createState() => _RemoteQueryWidgetState();
}

class _RemoteQueryWidgetState extends State<_RemoteQueryWidget> {
  static const _debounceDuration = Duration(milliseconds: 250);

  ValueListenable<SchemaQuerySnapshot>? _listenable;
  String? _lastSignature;
  Timer? _debounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final store = SchemaQueryScope.maybeOf(context);
    if (store == null) return;

    _listenable ??= store.watchQuery(widget.queryKey);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _scheduleExecuteIfNeeded(
    SchemaQueryStore store,
    Map<String, String> params, {
    required bool debounce,
  }) {
    final signature = jsonEncode(<String, Object?>{
      'path': widget.path,
      'params': params,
    });

    if (_lastSignature == signature) return;
    _lastSignature = signature;

    _debounceTimer?.cancel();

    void execute() {
      if (!mounted) return;
      // ignore: discarded_futures
      store.executeGet(
        key: widget.queryKey,
        path: widget.path,
        params: params,
        forceRefresh: true,
      );
    }

    if (!debounce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => execute());
      return;
    }

    _debounceTimer = Timer(_debounceDuration, execute);
  }

  List<Widget> _buildSlot(String slotName) {
    return buildSchemaSlotWidgets(
      widget.node.slots[slotName],
      widget.registry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = SchemaQueryScope.maybeOf(context);
    if (store == null) {
      return const UnknownSchemaWidget(
          componentName: 'RemoteQuery(missing-query-scope)');
    }

    final formStore = SchemaFormScope.maybeOf(context);
    final stateStore = SchemaStateScope.maybeOf(context);
    final routeParams = SchemaRouteScope.maybeParamsOf(context);

    final listenable = _listenable ?? store.watchQuery(widget.queryKey);

    final dependencyListenables = <Listenable>[];
    if (formStore != null) dependencyListenables.add(formStore);
    if (stateStore != null) dependencyListenables.add(stateStore);

    return AnimatedBuilder(
      animation: dependencyListenables.isEmpty
          ? const _NoopListenable()
          : Listenable.merge(dependencyListenables),
      builder: (context, _) {
        final params = SchemaQuerySpec.sanitizeParams(
          SchemaQuerySpec.resolveParams(
            widget.rawParams,
            formStore: formStore,
            stateStore: stateStore,
            routeParams: routeParams,
          ),
        );

        _scheduleExecuteIfNeeded(
          store,
          params,
          debounce: formStore != null || stateStore != null,
        );

        return ValueListenableBuilder<SchemaQuerySnapshot>(
          valueListenable: listenable,
          builder: (context, snapshot, _) {
            if (snapshot.isLoading) {
              final slot = _buildSlot('loading');
              return slot.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: slot);
            }

            if (snapshot.hasError) {
              final slot = _buildSlot('error');
              if (slot.isNotEmpty) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: slot);
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(snapshot.errorMessage ?? 'Error'),
              );
            }

            final raw = snapshot.data;
            final scopedData = readJsonPath(raw, widget.dataPath) ?? raw;

            if (scopedData is List && scopedData.isEmpty) {
              final slot = _buildSlot('empty');
              if (slot.isNotEmpty) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: slot);
              }
            }

            final body = _buildSlot('child');
            return SchemaDataScope(
              data: scopedData,
              child: body.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: body),
            );
          },
        );
      },
    );
  }
}

final class _NoopListenable extends Listenable {
  const _NoopListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
