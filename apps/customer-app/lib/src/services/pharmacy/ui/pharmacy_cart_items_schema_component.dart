import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'pharmacy_cart_items_widget.dart';

void registerPharmacyCartItemsSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('PharmacyCartItems', (node, _) {
    final surface = (node.props['surface'] as String?)?.trim() ?? 'raised';

    return PharmacyCartItemsWidget(surface: surface);
  });
}
