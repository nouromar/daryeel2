import 'package:flutter/widgets.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';

void registerGapSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Gap', (node, componentRegistry) {
    final height = _asDouble(node.props['height']) ?? 12.0;
    final width = _asDouble(node.props['width']) ?? 0.0;

    return SizedBox(height: height, width: width);
  });
}

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
