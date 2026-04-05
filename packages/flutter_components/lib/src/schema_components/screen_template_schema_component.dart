import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/screen_template_widget.dart';
import 'schema_component_context.dart';

void registerScreenTemplateSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('ScreenTemplate', (node, componentRegistry) {
    final defaultsRaw = node.props['stateDefaults'];
    final stateDefaults = defaultsRaw is Map
        ? Map<String, Object?>.fromEntries(
            defaultsRaw.entries
                .where((e) => e.key is String)
                .map((e) => MapEntry(e.key as String, e.value)),
          )
        : null;

    final header = _buildSlot(
      node.slots['header'],
      componentRegistry,
      visibility: context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
    );
    final body = _buildSlot(
      node.slots['body'],
      componentRegistry,
      visibility: context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
    );
    final footer = _buildSlot(
      node.slots['footer'],
      componentRegistry,
      visibility: context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
    );

    return SchemaStateScopeHost(
      defaults: stateDefaults,
      child: ScreenTemplateWidget(header: header, body: body, footer: footer),
    );
  });
}

List<Widget> _buildSlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  if (children == null || children.isEmpty) {
    return const <Widget>[];
  }

  return children
      .where((child) {
        if (child is ComponentNode) {
          return evaluateVisibleWhen(
            child.visibleWhen,
            visibility,
            diagnostics: diagnostics,
            diagnosticsContext: diagnosticsContext,
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
