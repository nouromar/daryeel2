import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../widgets/unknown_schema_widget.dart';
import 'schema_widget_registry.dart';

typedef SchemaNodeWrapperBuilder = Widget Function(
  ComponentNode node,
  Widget Function() buildChild,
);

class SchemaRenderer {
  const SchemaRenderer({
    required this.rootNode,
    required this.registry,
    this.wrapperBuilder,
  });

  final SchemaNode rootNode;
  final SchemaWidgetRegistry registry;
  final SchemaNodeWrapperBuilder? wrapperBuilder;

  Widget render() {
    return _buildNode(rootNode);
  }

  Widget _buildNode(SchemaNode node) {
    if (node is RefNode) {
      return UnknownSchemaWidget(componentName: 'ref:${node.ref}');
    }

    if (node is! ComponentNode) {
      return const UnknownSchemaWidget(componentName: '<unknown-node>');
    }

    final componentName = node.type;
    if (componentName.isEmpty) {
      return const UnknownSchemaWidget(componentName: '<missing-type>');
    }

    final builder = registry.resolve(componentName);
    if (builder == null) {
      return UnknownSchemaWidget(componentName: componentName);
    }

    final wrapper = wrapperBuilder;
    if (wrapper == null) {
      return builder(node, registry);
    }

    return wrapper(node, () => builder(node, registry));
  }
}
