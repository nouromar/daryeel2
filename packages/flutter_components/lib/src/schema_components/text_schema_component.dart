import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerTextSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Text', (node, componentRegistry) {
    final textTemplate = (node.props['text'] as String?) ?? '';

    final variantRaw = (node.props['variant'] as String?)?.trim();
    final colorRaw = (node.props['color'] as String?)?.trim();
    final weightRaw = (node.props['weight'] as String?)?.trim();
    final alignRaw = (node.props['align'] as String?)?.trim();
    final overflowRaw = (node.props['overflow'] as String?)?.trim();

    final fontSize = schemaAsDouble(node.props['size']);
    final maxLinesRaw = schemaAsInt(node.props['maxLines']);
    final maxLines = (maxLinesRaw == null) ? 1 : maxLinesRaw.clamp(1, 20);

    final softWrap = (node.props['softWrap'] is bool)
        ? node.props['softWrap'] as bool
        : false;

    final textAlign = switch (alignRaw?.toLowerCase()) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };

    final overflow = switch (overflowRaw?.toLowerCase()) {
      'clip' => TextOverflow.clip,
      'fade' => TextOverflow.fade,
      _ => TextOverflow.ellipsis,
    };

    return Builder(
      builder: (buildContext) {
        final theme = Theme.of(buildContext);
        final baseStyle = _resolveVariant(theme, variantRaw);

        final color = _resolveColor(theme, colorRaw);
        final weight = _resolveFontWeight(weightRaw);

        TextStyle? style = baseStyle;
        if (color != null || weight != null || fontSize != null) {
          style = (style ?? const TextStyle()).copyWith(
            color: color,
            fontWeight: weight,
            fontSize: fontSize,
          );
        }

        Widget buildText() {
          final text = interpolateSchemaString(textTemplate, buildContext);
          return Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
            softWrap: softWrap,
            textAlign: textAlign,
          );
        }

        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive =
            store != null && hasSchemaInterpolation(textTemplate);

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (_, __) => buildText(),
          );
        }

        return buildText();
      },
    );
  });
}

TextStyle? _resolveVariant(ThemeData theme, String? variantRaw) {
  final v = variantRaw?.toLowerCase();
  return switch (v) {
    'title' => theme.textTheme.titleMedium,
    'subtitle' => theme.textTheme.titleSmall,
    'label' => theme.textTheme.labelMedium,
    'caption' => theme.textTheme.bodySmall,
    'body' || null || '' => theme.textTheme.bodyMedium,
    _ => theme.textTheme.bodyMedium,
  };
}

Color? _resolveColor(ThemeData theme, String? colorRaw) {
  final v = colorRaw?.toLowerCase();
  final scheme = theme.colorScheme;

  return switch (v) {
    'muted' || 'subtle' || 'secondarytext' => scheme.onSurfaceVariant,
    'primary' => scheme.primary,
    'secondary' => scheme.secondary,
    'error' => scheme.error,
    'default' || null || '' => null,
    _ => null,
  };
}

FontWeight? _resolveFontWeight(String? weightRaw) {
  final v = weightRaw?.toLowerCase();
  return switch (v) {
    'regular' || 'normal' => FontWeight.w400,
    'medium' => FontWeight.w500,
    'semibold' || 'semi' => FontWeight.w600,
    'bold' => FontWeight.w700,
    null || '' => null,
    _ => null,
  };
}
