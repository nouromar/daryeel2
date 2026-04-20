import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

void registerServiceCapsulesSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('ServiceCapsules', (node, _) {
    final titlePath = (node.props['titlePath'] as String?)?.trim() ?? 'title';
    final iconPath = (node.props['iconPath'] as String?)?.trim() ?? 'icon';
    final imageUrlPath =
        (node.props['imageUrlPath'] as String?)?.trim() ?? 'imageUrl';
    final routePath = (node.props['routePath'] as String?)?.trim() ?? 'route';

    final maxItemsRaw = node.props['maxItems'];
    final maxItems = (maxItemsRaw is num)
        ? maxItemsRaw.toInt()
        : int.tryParse('${maxItemsRaw ?? ''}');

    return Builder(
      builder: (buildContext) {
        final dataScope = SchemaDataScope.maybeOf(buildContext);
        final raw = dataScope?.data;

        if (raw == null) {
          return const UnknownSchemaWidget(
            componentName: 'ServiceCapsules(missing-data)',
          );
        }

        final List items;
        if (raw is List) {
          items = raw;
        } else {
          return const UnknownSchemaWidget(
            componentName: 'ServiceCapsules(data-not-list)',
          );
        }

        final limit =
            (maxItems == null || maxItems <= 0 || maxItems > items.length)
            ? items.length
            : maxItems;

        final theme = Theme.of(buildContext);
        final colors = theme.colorScheme;

        Widget capsuleForItem(Object? item) {
          final title =
              (readJsonPath(item, titlePath) as String?)?.trim() ?? '';

          final iconName = (readJsonPath(item, iconPath) as String?)?.trim();
          final imageUrl = (readJsonPath(item, imageUrlPath) as String?)
              ?.trim();

          final tapRouteRaw = readJsonPath(item, routePath);
          final String? route;
          final Object? routeValue;
          if (tapRouteRaw is String) {
            route = tapRouteRaw;
            routeValue = null;
          } else if (tapRouteRaw is Map) {
            final dynamic name = tapRouteRaw['route'] ?? tapRouteRaw['name'];
            route = name is String ? name : null;
            routeValue =
                tapRouteRaw['value'] ??
                tapRouteRaw['args'] ??
                tapRouteRaw['params'];
          } else {
            route = null;
            routeValue = null;
          }

          Future<void> onTap() async {
            if (route == null || route.trim().isEmpty) return;
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
          }

          Widget? leading;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            leading = ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imageUrl,
                width: 20,
                height: 20,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            );
          } else if (iconName != null && iconName.isNotEmpty) {
            leading = Icon(
              _resolveIcon(iconName),
              size: 20,
              color: colors.onPrimaryContainer,
            );
          }

          final effectiveTitle = title.isEmpty ? 'Service' : title;

          return Material(
            color: colors.primaryContainer,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: (route == null || route.trim().isEmpty) ? null : onTap,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (leading != null) ...[
                      leading,
                      const SizedBox(height: 6),
                    ],
                    Text(
                      effectiveTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Wrap(
          direction: Axis.horizontal,
          spacing: 12,
          runSpacing: 12,
          children: [for (var i = 0; i < limit; i++) capsuleForItem(items[i])],
        );
      },
    );
  });
}

IconData _resolveIcon(String raw) {
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) return Icons.circle_outlined;

  // Keep this in sync with the core Icon component vocabulary.
  return switch (key) {
    'ambulance' ||
    'local_hospital' ||
    'hospital' => Icons.local_hospital_outlined,
    'home' || 'house' || 'home_visit' => Icons.home_outlined,
    'pharmacy' || 'local_pharmacy' || 'pill' => Icons.local_pharmacy_outlined,
    _ => Icons.circle_outlined,
  };
}
