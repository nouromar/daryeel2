import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/action_card_widget.dart';
import 'schema_component_context.dart';

void registerActionCardSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('ActionCard', (node, componentRegistry) {
    final titleTemplate = node.props['title'] as String? ?? 'Untitled';
    final subtitleTemplate = node.props['subtitle'] as String? ?? '';
    final surface = node.props['surface'] as String? ?? 'raised';
    final icon = _resolveMaterialIcon(node.props['icon'] as String?);

    final tapAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'tap',
    );

    return Builder(
      builder: (buildContext) {
        Widget buildCard() {
          final title = interpolateSchemaString(titleTemplate, buildContext);
          final subtitle = interpolateSchemaString(
            subtitleTemplate,
            buildContext,
          );

          return ActionCardWidget(
            title: title,
            subtitle: subtitle,
            icon: icon,
            surface: surface,
            density: (node.props['density'] as String?) ?? 'comfortable',
            titleVariant: node.props['titleVariant'] as String?,
            titleWeight: node.props['titleWeight'] as String?,
            titleColor: node.props['titleColor'] as String?,
            subtitleVariant: node.props['subtitleVariant'] as String?,
            subtitleWeight: node.props['subtitleWeight'] as String?,
            subtitleColor: node.props['subtitleColor'] as String?,
            onTap: tapAction == null
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
          );
        }

        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive = store != null &&
            (hasSchemaInterpolation(titleTemplate) ||
                hasSchemaInterpolation(subtitleTemplate));

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (_, __) => buildCard(),
          );
        }

        return buildCard();
      },
    );
  });
}

IconData? _resolveMaterialIcon(String? name) {
  if (name == null) return null;
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;

  return switch (key) {
    'ambulance' ||
    'local_hospital' ||
    'hospital' =>
      Icons.local_hospital_outlined,
    'home' || 'home_visit' => Icons.home_outlined,
    'pharmacy' || 'local_pharmacy' => Icons.local_pharmacy_outlined,
    'account' || 'person' || 'profile' => Icons.person_outline,
    'activities' || 'activity' || 'history' => Icons.history,
    _ => null,
  };
}
