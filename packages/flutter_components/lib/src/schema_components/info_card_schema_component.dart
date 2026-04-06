import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/info_card_widget.dart';
import 'schema_component_context.dart';

void registerInfoCardSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('InfoCard', (node, componentRegistry) {
    final titleTemplate = node.props['title'] as String? ?? 'Untitled';
    final subtitleTemplate = node.props['subtitle'] as String? ?? '';
    final surface = node.props['surface'] as String? ?? 'raised';

    return Builder(
      builder: (context) {
        Widget buildCard() {
          final title = interpolateSchemaString(titleTemplate, context);
          final subtitle = interpolateSchemaString(subtitleTemplate, context);
          return InfoCardWidget(
            title: title,
            subtitle: subtitle,
            surface: surface,
          );
        }

        final store = SchemaStateScope.maybeOf(context);
        final needsReactive = store != null &&
            (hasSchemaInterpolation(titleTemplate) ||
                hasSchemaInterpolation(subtitleTemplate));

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (_, __) => buildCard(),
          );
        }

        return buildCard();
      },
    );
  });
}
