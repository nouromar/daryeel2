import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/catalog_item_tile_widget.dart';
import 'schema_component_context.dart';

void registerCatalogItemTileSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('CatalogItemTile', (node, componentRegistry) {
    final titlePath = (node.props['titlePath'] as String?)?.trim() ?? 'name';
    final subtitlePath =
        (node.props['subtitlePath'] as String?)?.trim() ?? 'subtitle';
    final rxRequiredPath =
        (node.props['rxRequiredPath'] as String?)?.trim() ?? 'rx_required';
    final surface = (node.props['surface'] as String?)?.trim() ?? 'flat';

    return Builder(
      builder: (buildContext) {
        final scope = SchemaDataScope.maybeOf(buildContext);
        final item = scope?.item;
        if (item == null) {
          return const UnknownSchemaWidget(
            componentName: 'CatalogItemTile(missing-item)',
          );
        }

        final title = (readJsonPath(item, titlePath) as String?) ?? 'Untitled';
        final subtitle = (readJsonPath(item, subtitlePath) as String?) ?? '';

        final rxRaw = readJsonPath(item, rxRequiredPath);
        final rxRequired = rxRaw == true ||
            (rxRaw is String && rxRaw.trim().toLowerCase() == 'true');

        final tapRouteRaw = readJsonPath(item, 'route');
        final String? route;
        final Object? routeValue;
        if (tapRouteRaw is String) {
          route = tapRouteRaw;
          routeValue = null;
        } else if (tapRouteRaw is Map) {
          final dynamic name = tapRouteRaw['route'] ?? tapRouteRaw['name'];
          route = name is String ? name : null;
          routeValue = tapRouteRaw['value'] ??
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

        Future<void> onAdd() async {
          // We don't have a cart state yet; track the event as a safe default.
          try {
            await context.actionDispatcher.dispatch(
              buildContext,
              ActionDefinition(
                type: SchemaActionTypes.trackEvent,
                eventName: 'catalog.add_to_cart',
                eventProperties: <String, Object?>{
                  'screenId': context.screen.id,
                  'schemaId': context.screen.id,
                  'itemId': readJsonPath(item, 'id')?.toString(),
                  'rxRequired': rxRequired,
                },
              ),
            );
          } catch (_) {
            // No-op: telemetry should never crash UI.
          }
        }

        return CatalogItemTileWidget(
          title: title,
          subtitle: subtitle,
          surface: surface,
          rxRequired: rxRequired,
          onTap: route == null ? null : () => onTap(),
          onAddPressed: () => onAdd(),
        );
      },
    );
  });
}
