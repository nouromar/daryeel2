import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopActionDispatcher extends SchemaActionDispatcher {
  const _NoopActionDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {}
}

SchemaComponentContext _testComponentContext() {
  return SchemaComponentContext(
    screen: ScreenSchema(
      schemaVersion: '1',
      id: 'test',
      documentType: 'screen',
      product: 'test',
      service: null,
      themeId: 'test',
      themeMode: null,
      root: const ComponentNode(
        type: 'ScreenTemplate',
        props: <String, Object?>{},
        slots: <String, List<SchemaNode>>{},
        actions: <String, String>{},
        bind: null,
        visibleWhen: null,
      ),
      actions: const <String, ActionDefinition>{},
    ),
    actionDispatcher: const _NoopActionDispatcher(),
    visibility: const SchemaVisibilityContext(),
  );
}

ComponentNode _component(
  String type, {
  Map<String, Object?> props = const <String, Object?>{},
  Map<String, List<SchemaNode>> slots = const <String, List<SchemaNode>>{},
  String? bind,
}) {
  return ComponentNode(
    type: type,
    props: props,
    slots: slots,
    actions: const <String, String>{},
    bind: bind,
    visibleWhen: null,
  );
}

void main() {
  testWidgets('AddressSection binds chosen address into state', (tester) async {
    final registry = SchemaWidgetRegistry();
    final context = _testComponentContext();

    registerCoreSchemaComponents(registry: registry, context: context);

    final node = _component(
      'AddressSection',
      props: const <String, Object?>{
        'title': 'Delivery address',
        'sources': <String, Object?>{
          'providerAutocomplete': false,
          'mapPin': false,
        },
      },
      bind: r'$state.pharmacy.cart.deliveryAddress',
    );

    final store = SchemaStateStore(initial: const <String, Object?>{});

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: SchemaRenderer(rootNode: node, registry: registry).render(),
        ),
      ),
    );

    expect(find.text('Add delivery address'), findsOneWidget);

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hodan');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use "Hodan"'));
    await tester.pumpAndSettle();

    final raw = store.getValue('pharmacy.cart.deliveryAddress');
    expect(raw, isA<Map>());
    final map = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
    expect(map['text'], 'Hodan');
  });
}
