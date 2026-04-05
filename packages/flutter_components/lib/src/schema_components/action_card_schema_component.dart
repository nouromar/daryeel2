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
    final title = node.props['title'] as String? ?? 'Untitled';
    final subtitle = node.props['subtitle'] as String? ?? '';
    final surface = node.props['surface'] as String? ?? 'raised';
    final icon = _resolveMaterialIcon(node.props['icon'] as String?);

    final tapAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'tap',
    );

    return Builder(
      builder: (buildContext) {
        return ActionCardWidget(
          title: title,
          subtitle: subtitle,
          icon: icon,
          surface: surface,
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
