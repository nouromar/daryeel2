import 'package:flutter/widgets.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/info_card_widget.dart';
import 'schema_component_context.dart';

void registerInfoCardSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('InfoCard', (node, componentRegistry) {
    final title = node.props['title'] as String? ?? 'Untitled';
    final subtitle = node.props['subtitle'] as String? ?? '';
    final surface = node.props['surface'] as String? ?? 'raised';

    return Builder(
      builder: (context) {
        return InfoCardWidget(
            title: title, subtitle: subtitle, surface: surface);
      },
    );
  });
}
