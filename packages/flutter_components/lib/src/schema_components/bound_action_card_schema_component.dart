import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/action_card_widget.dart';
import 'schema_component_context.dart';

void registerBoundActionCardSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('BoundActionCard', (node, componentRegistry) {
    final titlePath = (node.props['titlePath'] as String?)?.trim() ?? 'title';
    final subtitlePath =
        (node.props['subtitlePath'] as String?)?.trim() ?? 'subtitle';
    final iconPath = (node.props['iconPath'] as String?)?.trim() ?? 'icon';
    final routePath = (node.props['routePath'] as String?)?.trim() ?? 'route';
    final surface = node.props['surface'] as String? ?? 'raised';
    final density = node.props['density'] as String?;

    final titleVariant = node.props['titleVariant'] as String?;
    final titleWeight = node.props['titleWeight'] as String?;
    final titleColor = node.props['titleColor'] as String?;
    final subtitleVariant = node.props['subtitleVariant'] as String?;
    final subtitleWeight = node.props['subtitleWeight'] as String?;
    final subtitleColor = node.props['subtitleColor'] as String?;

    return Builder(
      builder: (buildContext) {
        final scope = SchemaDataScope.maybeOf(buildContext);
        final item = scope?.item;
        if (item == null) {
          return const UnknownSchemaWidget(
              componentName: 'BoundActionCard(missing-item)');
        }

        final title = (readJsonPath(item, titlePath) as String?) ?? 'Untitled';
        final subtitle = (readJsonPath(item, subtitlePath) as String?) ?? '';
        final iconName = readJsonPath(item, iconPath) as String?;
        final routeRaw = readJsonPath(item, routePath);

        final String? route;
        final Object? routeValue;
        if (routeRaw is String) {
          route = routeRaw;
          routeValue = null;
        } else if (routeRaw is Map) {
          final dynamic name = routeRaw['route'] ?? routeRaw['name'];
          route = name is String ? name : null;
          routeValue =
              routeRaw['value'] ?? routeRaw['args'] ?? routeRaw['params'];
        } else {
          route = null;
          routeValue = null;
        }

        return ActionCardWidget(
          title: title,
          subtitle: subtitle,
          icon: _resolveMaterialIcon(iconName),
          surface: surface,
          density: density ?? 'comfortable',
          titleVariant: titleVariant,
          titleWeight: titleWeight,
          titleColor: titleColor,
          subtitleVariant: subtitleVariant,
          subtitleWeight: subtitleWeight,
          subtitleColor: subtitleColor,
          onTap: (route == null || route.trim().isEmpty)
              ? null
              : () async {
                  try {
                    await context.actionDispatcher.dispatch(
                      buildContext,
                      ActionDefinition(
                        type: SchemaActionTypes.navigate,
                        route: route,
                        value: routeValue,
                      ),
                    );
                  } catch (error) {
                    if (!buildContext.mounted) return;
                    ScaffoldMessenger.of(buildContext).showSnackBar(
                      SnackBar(content: Text('Navigation failed: $error')),
                    );
                  }
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
