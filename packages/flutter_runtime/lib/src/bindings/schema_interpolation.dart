import 'package:flutter/widgets.dart';

import 'schema_expression_engine.dart';

bool hasSchemaInterpolation(String template) {
  return template.contains(r'${');
}

/// Interpolates a string containing `${...}` placeholders.
///
/// Supported placeholder roots (minimal, safe set):
/// - `state.<path>`: reads from `$state` via [SchemaStateScope]
/// - `item.<path>`: reads from current [SchemaDataScope.item]
/// - `params.<path>`: reads from [SchemaRouteScope] params
/// - `index`: reads from current [SchemaDataScope.index]
///
/// Unknown placeholders resolve to an empty string.
String interpolateSchemaString(String template, BuildContext context) {
  if (!hasSchemaInterpolation(template)) return template;
  return interpolateSchemaTemplate(template, context);
}
