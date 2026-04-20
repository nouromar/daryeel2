import 'package:flutter/widgets.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'section_card_widget.dart';

void registerSectionCardSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('SectionCard', (node, componentRegistry) {
    final props = node.props;

    final titleTemplate = (props['title'] as String?) ?? '';
    final subtitleTemplate = (props['subtitle'] as String?) ?? '';

    final child = _buildSingleChildSlot(
      node.slots['child'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
    );

    if (child == null) {
      return const UnknownSchemaWidget(
        componentName: 'SectionCard(missing-child)',
      );
    }

    final surface = (props['surface'] as String?)?.trim() ?? 'raised';
    final density = (props['density'] as String?)?.trim() ?? 'comfortable';
    final contentGapRaw = _schemaAsDouble(props['contentGap']);

    return Builder(
      builder: (buildContext) {
        Widget buildCard(BuildContext ctx) {
          final title = interpolateSchemaString(titleTemplate, ctx);
          final subtitle = interpolateSchemaString(subtitleTemplate, ctx);

          return SectionCardWidget(
            title: title,
            subtitle: subtitle,
            surface: surface,
            density: density,
            titleVariant: props['titleVariant'] as String?,
            titleWeight: props['titleWeight'] as String?,
            titleColor: props['titleColor'] as String?,
            subtitleVariant: props['subtitleVariant'] as String?,
            subtitleWeight: props['subtitleWeight'] as String?,
            subtitleColor: props['subtitleColor'] as String?,
            contentGap: contentGapRaw,
            child: child,
          );
        }

        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive =
            store != null &&
            (hasSchemaInterpolation(titleTemplate) ||
                hasSchemaInterpolation(subtitleTemplate));

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (ctx, _) => buildCard(ctx),
          );
        }

        return buildCard(buildContext);
      },
    );
  });
}

Widget? _buildSingleChildSlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaComponentContext context,
  required bool applyVisibilityWhen,
}) {
  if (children == null || children.isEmpty) return null;
  if (children.length != 1) {
    return const UnknownSchemaWidget(
      componentName: 'SectionCard(multiple-children)',
    );
  }

  final child = children.single;
  if (applyVisibilityWhen && child is ComponentNode) {
    final visible = evaluateVisibleWhen(
      child.visibleWhen,
      context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
      nodeType: child.type,
    );
    if (!visible) return const SizedBox.shrink();
  }

  return SchemaRenderer(rootNode: child, registry: registry).render();
}

double? _schemaAsDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
