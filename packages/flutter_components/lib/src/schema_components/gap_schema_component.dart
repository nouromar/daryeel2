import 'package:flutter/widgets.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerGapSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Gap', (node, componentRegistry) {
    final height = schemaAsDouble(node.props['height']) ?? 12.0;
    final width = schemaAsDouble(node.props['width']) ?? 0.0;

    return SizedBox(height: height, width: width);
  });
}
