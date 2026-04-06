import 'package:flutter/widgets.dart';

import '../data/schema_data_scope.dart';
import '../runtime/schema_route_scope.dart';
import '../state/schema_state_scope.dart';

final RegExp _placeholder = RegExp(r'\$\{([^}]+)\}');

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

  final dataScope = SchemaDataScope.maybeOf(context);
  final item = dataScope?.item;
  final index = dataScope?.index;

  final params = SchemaRouteScope.maybeParamsOf(context);
  final store = SchemaStateScope.maybeOf(context);

  return template.replaceAllMapped(_placeholder, (m) {
    final rawExpr = m.group(1);
    final expr = rawExpr?.trim();
    if (expr == null || expr.isEmpty) return '';

    if (expr == 'index') {
      return index?.toString() ?? '';
    }

    const statePrefix = 'state.';
    const itemPrefix = 'item.';
    const paramsPrefix = 'params.';

    Object? value;
    if (expr.startsWith(statePrefix)) {
      final path = expr.substring(statePrefix.length).trim();
      if (path.isEmpty) return '';
      value = store?.getValue(path);
    } else if (expr.startsWith(itemPrefix)) {
      final path = expr.substring(itemPrefix.length).trim();
      value = readJsonPath(item, path);
    } else if (expr.startsWith(paramsPrefix)) {
      final path = expr.substring(paramsPrefix.length).trim();
      value = readJsonPath(params, path);
    } else {
      // Allow bare `item` reads like `${title}`? No: keep strict.
      value = null;
    }

    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return value.toString();
  });
}
