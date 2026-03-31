import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../widgets/unknown_schema_widget.dart';
import 'schema_widget_registry.dart';

class SchemaRenderer {
  const SchemaRenderer({required this.rootNode, required this.registry});

  final SchemaNode rootNode;
  final SchemaWidgetRegistry registry;

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

    return builder(node, registry);
  }
}
