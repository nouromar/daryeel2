import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import 'schema_component_context.dart';

/// Shared helpers for schema component implementations.
///
/// This file is intentionally internal (not exported from the package barrel).

List<Widget> buildSchemaSlotWidgets(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  SchemaComponentContext? context,
  bool applyVisibilityWhen = false,
}) {
  if (children == null || children.isEmpty) return const <Widget>[];

  return children
      .where((child) {
        if (!applyVisibilityWhen || context == null) return true;
        if (child is ComponentNode) {
          return evaluateVisibleWhen(
            child.visibleWhen,
            context.visibility,
            diagnostics: context.diagnostics,
            diagnosticsContext: context.diagnosticsContext,
            nodeType: child.type,
          );
        }
        return true;
      })
      .map(
        (child) => SchemaRenderer(rootNode: child, registry: registry).render(),
      )
      .toList(growable: false);
}

Widget? buildSingleChildSchemaSlotWidget(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required String componentName,
  SchemaComponentContext? context,
  bool applyVisibilityWhen = false,
}) {
  if (children == null || children.isEmpty) return null;
  if (children.length != 1) {
    return UnknownSchemaWidget(
      componentName: '$componentName(multiple-children)',
    );
  }

  final child = children.single;
  if (applyVisibilityWhen && context != null && child is ComponentNode) {
    final visible = evaluateVisibleWhen(
      child.visibleWhen,
      context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
      nodeType: child.type,
    );
    if (!visible) return null;
  }

  return SchemaRenderer(rootNode: child, registry: registry).render();
}

double? schemaAsDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? schemaAsInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
