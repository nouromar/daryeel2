import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'pharmacy_checkout_widget.dart';

void registerPharmacyCheckoutSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('PharmacyCheckout', (node, _) {
    return const PharmacyCheckoutWidget();
  });
}
