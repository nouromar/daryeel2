import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../actions/customer_action_dispatcher.dart';
import '../services/pharmacy/ui/catalog_item_tile_schema_component.dart';
import '../services/pharmacy/ui/pharmacy_cart_items_schema_component.dart';
import '../services/pharmacy/ui/pharmacy_checkout_schema_component.dart';
import '../services/pharmacy/ui/pharmacy_prescription_upload_schema_component.dart';

typedef CustomerSchemaComponentRegistrar =
    void Function({
      required SchemaWidgetRegistry registry,
      required SchemaComponentContext context,
    });

const Map<String, CustomerSchemaComponentRegistrar>
_customerSchemaComponentRegistrarsByType =
    <String, CustomerSchemaComponentRegistrar>{
      'CatalogItemTile': registerCustomerCatalogItemTileSchemaComponent,
      'PharmacyCartItems': registerPharmacyCartItemsSchemaComponent,
      'PharmacyCheckout': registerPharmacyCheckoutSchemaComponent,
      'PharmacyPrescriptionUpload':
          registerPharmacyPrescriptionUploadSchemaComponent,
    };

void registerCustomerSchemaComponents({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  for (final registrar in _customerSchemaComponentRegistrarsByType.values) {
    registrar(registry: registry, context: context);
  }
}

SchemaWidgetRegistry buildCustomerComponentRegistry({
  required ScreenSchema screen,
  required SchemaActionDispatcher actionDispatcher,
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  final registry = SchemaWidgetRegistry();

  // Wrap the runtime dispatcher so the app can support higher-level behaviors
  // (like list-based cart upserts) without changing packages/*.
  final appDispatcher = CustomerActionDispatcher(delegate: actionDispatcher);

  final componentContext = SchemaComponentContext(
    screen: screen,
    actionDispatcher: appDispatcher,
    visibility: visibility,
    diagnostics: diagnostics,
    diagnosticsContext: diagnosticsContext,
  );

  registerCoreSchemaComponents(registry: registry, context: componentContext);

  registerCustomerSchemaComponents(
    registry: registry,
    context: componentContext,
  );

  return registry;
}
