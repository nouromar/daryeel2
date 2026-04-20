import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerTapAreaSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('TapArea', (node, componentRegistry) {
    final padding = _parseEdgeInsets(node.props);

    final minSizeRaw = schemaAsDouble(node.props['minSize']);
    final semanticLabelTemplate =
        (node.props['semanticLabel'] as String?)?.trim();

    final child = buildSingleChildSchemaSlotWidget(
      node.slots['child'],
      componentRegistry,
      componentName: 'TapArea',
      context: context,
      applyVisibilityWhen: true,
    );

    if (child == null) return const SizedBox.shrink();

    final tapAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'tap',
    );

    final isInteractive = tapAction != null;
    final defaultMinSize = isInteractive ? 40.0 : 0.0;
    final minSize = (minSizeRaw ?? defaultMinSize).clamp(0.0, 10000.0);

    Widget content = child;
    if (padding != EdgeInsets.zero) {
      content = Padding(padding: padding, child: content);
    }

    if (minSize > 0) {
      content = ConstrainedBox(
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        child: Align(alignment: Alignment.center, child: content),
      );
    }

    if (!isInteractive) return content;

    return Builder(
      builder: (buildContext) {
        final semanticLabel =
            (semanticLabelTemplate == null || semanticLabelTemplate.isEmpty)
                ? null
                : interpolateSchemaString(semanticLabelTemplate, buildContext)
                    .trim();

        return Semantics(
          button: true,
          label: semanticLabel,
          child: Material(
            type: MaterialType.transparency,
            child: InkResponse(
              onTap: () async {
                final result = await tryDispatchComponentAction(
                  context: buildContext,
                  screen: context.screen,
                  node: node,
                  actionKey: 'tap',
                  dispatcher: context.actionDispatcher,
                  diagnostics: context.diagnostics,
                  diagnosticsContext: context.diagnosticsContext,
                );

                final failure = result.failure;
                if (failure == null) return;
                if (!buildContext.mounted) return;

                ScaffoldMessenger.of(buildContext).showSnackBar(
                  SnackBar(content: Text(failure.message)),
                );
              },
              child: content,
            ),
          ),
        );
      },
    );
  });
}

EdgeInsets _parseEdgeInsets(Map<String, Object?> props) {
  double? read(String key) => schemaAsDouble(props[key]);

  double left = 0;
  double top = 0;
  double right = 0;
  double bottom = 0;

  final all = read('all');
  if (all != null) {
    left = all;
    top = all;
    right = all;
    bottom = all;
  }

  final horizontal = read('horizontal');
  if (horizontal != null) {
    left = horizontal;
    right = horizontal;
  }

  final vertical = read('vertical');
  if (vertical != null) {
    top = vertical;
    bottom = vertical;
  }

  final l = read('left');
  if (l != null) left = l;
  final t = read('top');
  if (t != null) top = t;
  final r = read('right');
  if (r != null) right = r;
  final b = read('bottom');
  if (b != null) bottom = b;

  return EdgeInsets.fromLTRB(left, top, right, bottom);
}
