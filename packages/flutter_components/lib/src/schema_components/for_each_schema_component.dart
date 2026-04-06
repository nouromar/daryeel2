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

    const statePrefixDot = r'$state.';
    const statePrefixColon = r'$state:';
    final isStateItemsPath = itemsPath != null &&
        (itemsPath.startsWith(statePrefixDot) ||
            itemsPath.startsWith(statePrefixColon));
    final stateItemsKey = isStateItemsPath
        ? (itemsPath.startsWith(statePrefixDot)
            ? itemsPath.substring(statePrefixDot.length)
            : itemsPath.substring(statePrefixColon.length))
        : null;

    final template = node.slots['item'];
    if (template == null || template.isEmpty) {
      return const UnknownSchemaWidget(
          componentName: 'ForEach(missing-item-slot)');
    }

    return Builder(
      builder: (buildContext) {
        final dataScope = SchemaDataScope.maybeOf(buildContext);

        Object? resolveItems() {
          if (isStateItemsPath) {
            final key = (stateItemsKey ?? '').trim();
            if (key.isEmpty) return null;
            final store = SchemaStateScope.maybeOf(buildContext);
            return store?.getValue(key);
          }

          final data = dataScope?.data;
          if (itemsPath == null || itemsPath.isEmpty) return data;
          return readJsonPath(data, itemsPath);
        }

        Widget buildList() {
          final items = resolveItems();

          if (items is! List) {
            return const UnknownSchemaWidget(
                componentName: 'ForEach(items-not-list)');
          }

          String? stableKeyForItem(Object? item, int index) {
            final path = (itemKeyPath == null || itemKeyPath.isEmpty)
                ? 'id'
                : itemKeyPath;

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
        }

        if (!isStateItemsPath) return buildList();

        final store = SchemaStateScope.maybeOf(buildContext);
        if (store == null) {
          return const UnknownSchemaWidget(
            componentName: 'ForEach(missing-state-scope)',
          );
        }

        return AnimatedBuilder(
          animation: store,
          builder: (_, __) => buildList(),
        );
      },
    );
  });
}
