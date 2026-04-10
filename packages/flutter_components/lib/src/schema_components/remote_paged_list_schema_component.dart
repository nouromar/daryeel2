import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import '../widgets/screen_primary_scroll_widget.dart';
import 'schema_component_utils.dart';
import 'schema_node_wrapper.dart';

void registerRemotePagedListSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('RemotePagedList', (node, componentRegistry) {
    final key = (node.props['key'] as String?)?.trim();
    final path = (node.props['path'] as String?)?.trim();

    final rawParams = node.props['params'];
    final itemsPath = (node.props['itemsPath'] as String?)?.trim();
    final nextCursorPath = (node.props['nextCursorPath'] as String?)?.trim();
    final cursorParam = (node.props['cursorParam'] as String?)?.trim();
    final itemKeyPath = (node.props['itemKeyPath'] as String?)?.trim();

    if (key == null || key.isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'RemotePagedList(missing-key)',
      );
    }
    if (path == null || path.isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'RemotePagedList(missing-path)',
      );
    }
    if (itemsPath == null || itemsPath.isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'RemotePagedList(missing-itemsPath)',
      );
    }
    if (nextCursorPath == null || nextCursorPath.isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'RemotePagedList(missing-nextCursorPath)',
      );
    }

    final template = node.slots['item'];
    if (template == null || template.isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'RemotePagedList(missing-item-slot)',
      );
    }

    return _RemotePagedListWidget(
      queryKey: key,
      path: path,
      rawParams: rawParams,
      itemsPath: itemsPath,
      nextCursorPath: nextCursorPath,
      cursorParam: cursorParam,
      itemKeyPath: itemKeyPath,
      template: template,
      node: node,
      registry: componentRegistry,
      componentContext: context,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
    );
  });
}

class _RemotePagedListWidget extends StatefulWidget
    implements ScreenPrimaryScrollWidget {
  const _RemotePagedListWidget({
    required this.queryKey,
    required this.path,
    required this.rawParams,
    required this.itemsPath,
    required this.nextCursorPath,
    required this.cursorParam,
    required this.itemKeyPath,
    required this.template,
    required this.node,
    required this.registry,
    required this.componentContext,
    required this.diagnostics,
    required this.diagnosticsContext,
  });

  final String queryKey;
  final String path;
  final Object? rawParams;
  final String itemsPath;
  final String nextCursorPath;
  final String? cursorParam;
  final String? itemKeyPath;
  final List<SchemaNode> template;
  final ComponentNode node;
  final SchemaWidgetRegistry registry;
  final SchemaComponentContext componentContext;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;

  @override
  State<_RemotePagedListWidget> createState() => _RemotePagedListWidgetState();
}

class _RemotePagedListWidgetState extends State<_RemotePagedListWidget> {
  static const _debounceDuration = Duration(milliseconds: 250);

  final _controller = ScrollController();
  ValueListenable<SchemaPagedQuerySnapshot>? _listenable;
  String? _lastSignature;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;

    // Basic near-end detection; no extra UX knobs.
    const thresholdPx = 200.0;
    final pos = _controller.position;
    if (pos.maxScrollExtent - pos.pixels <= thresholdPx) {
      final store = SchemaQueryScope.maybeOf(context);
      if (store == null) return;
      // ignore: discarded_futures
      store.loadMorePagedGet(widget.queryKey);
    }
  }

  List<Widget> _buildSlot(String slotName) {
    return buildSchemaSlotWidgets(
      widget.node.slots[slotName],
      widget.registry,
      context: widget.componentContext,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final store = SchemaQueryScope.maybeOf(context);
    if (store == null) return;

    _listenable ??= store.watchPagedQuery(widget.queryKey);
  }

  void _scheduleExecuteIfNeeded(
    SchemaQueryStore store,
    Map<String, String> params, {
    required bool debounce,
  }) {
    final signature = jsonEncode(<String, Object?>{
      'path': widget.path,
      'params': params,
      'itemsPath': widget.itemsPath,
      'nextCursorPath': widget.nextCursorPath,
      'cursorParam': (widget.cursorParam == null || widget.cursorParam!.isEmpty)
          ? 'cursor'
          : widget.cursorParam!,
    });

    if (_lastSignature == signature) return;

    final hadPreviousSignature = _lastSignature != null;
    _lastSignature = signature;

    // If the query changes (e.g., new filter/search), the list resets and
    // should return the user to the top.
    if (hadPreviousSignature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_controller.hasClients) return;
        try {
          _controller.jumpTo(0);
        } catch (_) {
          // No-op: can happen if the scrollable detaches mid-frame.
        }
      });
    }

    _debounceTimer?.cancel();

    void execute() {
      if (!mounted) return;
      // ignore: discarded_futures
      store.executePagedGet(
        key: widget.queryKey,
        path: widget.path,
        params: params,
        itemsPath: widget.itemsPath,
        nextCursorPath: widget.nextCursorPath,
        cursorParam: (widget.cursorParam == null || widget.cursorParam!.isEmpty)
            ? 'cursor'
            : widget.cursorParam!,
        forceRefresh: true,
      );
    }

    if (!debounce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => execute());
      return;
    }

    _debounceTimer = Timer(_debounceDuration, execute);
  }

  @override
  Widget build(BuildContext context) {
    final store = SchemaQueryScope.maybeOf(context);
    if (store == null) {
      return const UnknownSchemaWidget(
        componentName: 'RemotePagedList(missing-query-scope)',
      );
    }

    final formStore = SchemaFormScope.maybeOf(context);
    final stateStore = SchemaStateScope.maybeOf(context);
    final routeParams = SchemaRouteScope.maybeParamsOf(context);

    final listenable = _listenable ?? store.watchPagedQuery(widget.queryKey);

    final dependencyListenables = <Listenable>[];
    if (formStore != null) dependencyListenables.add(formStore);
    if (stateStore != null) dependencyListenables.add(stateStore);

    return AnimatedBuilder(
      animation: dependencyListenables.isEmpty
          ? const _NoopListenable()
          : Listenable.merge(dependencyListenables),
      builder: (context, _) {
        final wrapperBuilder = buildVisibleWhenWrapper(
          visibility: widget.componentContext.visibility,
          diagnostics: widget.diagnostics,
          diagnosticsContext: widget.diagnosticsContext,
        );

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

        return ValueListenableBuilder<SchemaPagedQuerySnapshot>(
          valueListenable: listenable,
          builder: (context, snapshot, _) {
            if (snapshot.isLoading) {
              final slot = _buildSlot('loading');
              return slot.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: slot,
                    );
            }

            if (snapshot.hasError) {
              final slot = _buildSlot('error');
              if (slot.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: slot,
                );
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(snapshot.errorMessage ?? 'Error'),
              );
            }

            if (!snapshot.hasItems) {
              final slot = _buildSlot('empty');
              if (slot.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: slot,
                );
              }
              return const SizedBox.shrink();
            }

            final itemCount = snapshot.items.length;
            final showFooter =
                snapshot.isLoadingMore || snapshot.hasLoadMoreError;

            return ListView.builder(
              controller: _controller,
              itemCount: itemCount + (showFooter ? 1 : 0),
              itemBuilder: (context, index) {
                if (showFooter && index == itemCount) {
                  if (snapshot.isLoadingMore) {
                    final slot = _buildSlot('loadingMore');
                    return slot.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: slot,
                          );
                  }

                  final slot = _buildSlot('errorMore');
                  if (slot.isNotEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: slot,
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(snapshot.loadMoreErrorMessage ?? 'Error'),
                  );
                }

                final item = snapshot.items[index];

                String? stableKeyForItem(Object? item) {
                  final rawPath = widget.itemKeyPath;
                  final path =
                      (rawPath == null || rawPath.isEmpty) ? 'id' : rawPath;
                  final v = readJsonPath(item, path);
                  if (v is String) {
                    final trimmed = v.trim();
                    return trimmed.isEmpty ? null : trimmed;
                  }
                  if (v is num || v is bool) {
                    return v.toString();
                  }
                  return null;
                }

                final stable = stableKeyForItem(item);
                final itemKey = ValueKey<String>(
                  stable == null ? 'item_index:$index' : 'item:$stable',
                );

                return SchemaDataScope(
                  key: itemKey,
                  data: snapshot.raw,
                  item: item,
                  index: index,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.template
                        .map(
                          (child) => SchemaRenderer(
                            rootNode: child,
                            registry: widget.registry,
                            wrapperBuilder: wrapperBuilder,
                          ).render(),
                        )
                        .toList(growable: false),
                  ),
                );
              },
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
