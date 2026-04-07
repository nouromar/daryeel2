import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';

void registerTextButtonSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('TextButton', (node, componentRegistry) {
    final labelTemplate = node.props['label'] as String? ?? 'Link';
    final alignRaw = node.props['align'] as String?;

    final alignment = switch (alignRaw?.trim().toLowerCase()) {
      'right' => Alignment.centerRight,
      'center' => Alignment.center,
      _ => Alignment.centerLeft,
    };

    final tapAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'tap',
    );

    return Builder(
      builder: (buildContext) {
        Widget buildButton() {
          final label = interpolateSchemaString(labelTemplate, buildContext);

          return Align(
            alignment: alignment,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 0),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: tapAction == null
                  ? null
                  : () async {
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
              child: Text(label),
            ),
          );
        }

        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive =
            store != null && hasSchemaInterpolation(labelTemplate);

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (_, __) => buildButton(),
          );
        }

        return buildButton();
      },
    );
  });
}
