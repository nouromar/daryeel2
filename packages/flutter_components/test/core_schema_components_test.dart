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
  test('registerCoreSchemaComponents registers core builders', () {
    final registry = SchemaWidgetRegistry();

    const screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 'test_screen',
      documentType: 'screen',
      product: 'test',
      service: null,
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

    const context = SchemaComponentContext(
      screen: screen,
      actionDispatcher: _NoopDispatcher(),
      visibility: SchemaVisibilityContext(),
      diagnostics: null,
      diagnosticsContext: <String, Object?>{},
    );

    registerCoreSchemaComponents(registry: registry, context: context);

    expect(registry.resolve('Padding'), isNotNull);
    expect(registry.resolve('Column'), isNotNull);
    expect(registry.resolve('CartItem'), isNotNull);
    expect(registry.resolve('CartSummary'), isNotNull);
    expect(registry.resolve('ScreenTemplate'), isNotNull);
    expect(registry.resolve('RemotePagedList'), isNotNull);
  });
}
