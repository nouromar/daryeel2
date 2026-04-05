import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';

void registerForEachSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('ForEach', (node, componentRegistry) {
    final itemsPath = (node.props['itemsPath'] as String?)?.trim();
    final itemKeyPath = (node.props['itemKeyPath'] as String?)?.trim();

    final template = node.slots['item'];
    if (template == null || template.isEmpty) {
      return const UnknownSchemaWidget(
          componentName: 'ForEach(missing-item-slot)');
    }

    return Builder(
      builder: (buildContext) {
        final dataScope = SchemaDataScope.maybeOf(buildContext);
        final data = dataScope?.data;
        final items = itemsPath == null || itemsPath.isEmpty
            ? data
            : readJsonPath(data, itemsPath);

        if (items is! List) {
          return const UnknownSchemaWidget(
              componentName: 'ForEach(items-not-list)');
        }

        String? stableKeyForItem(Object? item, int index) {
          final path =
              (itemKeyPath == null || itemKeyPath.isEmpty) ? 'id' : itemKeyPath;

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

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final stable = stableKeyForItem(item, index);
            final key = ValueKey<String>(
              stable == null ? 'item_index:$index' : 'item:$stable',
            );

            return SchemaDataScope(
              key: key,
              data: dataScope?.data,
              item: item,
              index: index,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: template
                    .map(
                      (child) => SchemaRenderer(
                        rootNode: child,
                        registry: componentRegistry,
                      ).render(),
                    )
                    .toList(growable: false),
              ),
            );
          },
        );
      },
    );
  });
}
