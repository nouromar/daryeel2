import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_node_wrapper.dart';

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

  final wrapperBuilder = (context == null)
      ? null
      : buildVisibleWhenWrapper(
          visibility: context.visibility,
          diagnostics: context.diagnostics,
          diagnosticsContext: context.diagnosticsContext,
        );

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
        (child) => SchemaRenderer(
          rootNode: child,
          registry: registry,
          wrapperBuilder: wrapperBuilder,
        ).render(),
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

  final wrapperBuilder = buildVisibleWhenWrapper(
    visibility: context?.visibility ?? const SchemaVisibilityContext(),
    diagnostics: context?.diagnostics,
    diagnosticsContext:
        context?.diagnosticsContext ?? const <String, Object?>{},
  );

  return SchemaRenderer(
    rootNode: child,
    registry: registry,
    wrapperBuilder: (context == null) ? null : wrapperBuilder,
  ).render();
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
