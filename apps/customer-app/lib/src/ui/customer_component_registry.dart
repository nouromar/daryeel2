import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../services/pharmacy/ui/catalog_item_tile_schema_component.dart';

SchemaWidgetRegistry buildCustomerComponentRegistry({
  required ScreenSchema screen,
  required SchemaActionDispatcher actionDispatcher,
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  final registry = SchemaWidgetRegistry();

  final componentContext = SchemaComponentContext(
    screen: screen,
    actionDispatcher: actionDispatcher,
    visibility: visibility,
    diagnostics: diagnostics,
    diagnosticsContext: diagnosticsContext,
  );

  registerCoreSchemaComponents(registry: registry, context: componentContext);

  registerCustomerCatalogItemTileSchemaComponent(
    registry: registry,
    context: componentContext,
  );

  return registry;
}
