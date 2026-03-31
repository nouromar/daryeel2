import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

typedef SchemaNodeBuilder = Widget Function(
    ComponentNode node, SchemaWidgetRegistry registry);

class SchemaWidgetRegistry {
  final Map<String, SchemaNodeBuilder> _builders = {};

  void register(String componentName, SchemaNodeBuilder builder) {
    _builders[componentName] = builder;
  }

  SchemaNodeBuilder? resolve(String componentName) {
    return _builders[componentName];
  }
}
