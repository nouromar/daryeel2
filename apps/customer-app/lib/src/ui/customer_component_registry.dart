import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

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

  registerTextInputSchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerScreenTemplateSchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerInfoCardSchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerActionCardSchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerGapSchemaComponent(registry: registry, context: componentContext);
  registerBottomTabsSchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerPrimaryActionBarSchemaComponent(
    registry: registry,
    context: componentContext,
  );

  registerRemoteQuerySchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerRemotePagedListSchemaComponent(
    registry: registry,
    context: componentContext,
  );
  registerForEachSchemaComponent(registry: registry, context: componentContext);
  registerBoundActionCardSchemaComponent(
    registry: registry,
    context: componentContext,
  );

  return registry;
}
