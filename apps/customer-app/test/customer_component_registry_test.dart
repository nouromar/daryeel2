import 'package:customer_app/src/ui/customer_component_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

final class _NoopDispatcher extends SchemaActionDispatcher {
  const _NoopDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {}
}

void main() {
  const screen = ScreenSchema(
    schemaVersion: '1.0',
    id: 'test_screen',
    documentType: 'screen',
    product: 'customer_app',
    service: 'pharmacy',
    themeId: 'test-theme',
    themeMode: null,
    root: ComponentNode(
      type: 'Column',
      props: <String, Object?>{},
      slots: <String, List<SchemaNode>>{},
      actions: <String, String>{},
      bind: null,
      visibleWhen: null,
    ),
    actions: <String, ActionDefinition>{},
  );

  const componentContext = SchemaComponentContext(
    screen: screen,
    actionDispatcher: _NoopDispatcher(),
    visibility: SchemaVisibilityContext(),
    diagnostics: null,
    diagnosticsContext: <String, Object?>{},
  );

  test('registerCustomerSchemaComponents registers app builders', () {
    final registry = SchemaWidgetRegistry();

    registerCustomerSchemaComponents(
      registry: registry,
      context: componentContext,
    );

    expect(registry.resolve('CatalogItemTile'), isNotNull);
    expect(registry.resolve('PharmacyCartItems'), isNotNull);
    expect(registry.resolve('PharmacyCheckout'), isNotNull);
    expect(registry.resolve('PharmacyPrescriptionUpload'), isNotNull);
  });

  test('registerCustomerSchemaComponents overrides shared catalog tile', () {
    final registry = SchemaWidgetRegistry();

    registerCoreSchemaComponents(registry: registry, context: componentContext);
    final coreBuilder = registry.resolve('CatalogItemTile');

    registerCustomerSchemaComponents(
      registry: registry,
      context: componentContext,
    );

    final appBuilder = registry.resolve('CatalogItemTile');

    expect(coreBuilder, isNotNull);
    expect(appBuilder, isNotNull);
    expect(appBuilder, isNot(same(coreBuilder)));
  });
}
