import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/primary_action_bar_widget.dart';
import 'schema_component_context.dart';

void registerPrimaryActionBarSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('PrimaryActionBar', (node, componentRegistry) {
    final labelTemplate = node.props['primaryLabel'] as String? ?? 'Continue';
    final contentAlign = node.props['contentAlign'] as String?;
    final expand = node.props['expand'] as bool? ?? true;
    final primaryAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'primary',
    );

    final contentAlignment = switch (contentAlign) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };

    return Builder(
      builder: (buildContext) {
        Widget buildBar() {
          final label = interpolateSchemaString(labelTemplate, buildContext);

          return PrimaryActionBarWidget(
            primaryLabel: label,
            contentAlignment: contentAlignment,
            expand: expand,
            onPrimaryPressed: primaryAction == null
                ? null
                : () async {
                    final result = await tryDispatchComponentAction(
                      context: buildContext,
                      screen: context.screen,
                      node: node,
                      actionKey: 'primary',
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
          );
        }

        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive =
            store != null && hasSchemaInterpolation(labelTemplate);

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (_, __) => buildBar(),
          );
        }

        return buildBar();
      },
    );
  });
}
