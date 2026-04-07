import 'package:flutter/widgets.dart';
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
}) {
  return ComponentNode(
    type: type,
    props: props,
    slots: slots,
    actions: const <String, String>{},
    bind: null,
    visibleWhen: null,
  );
}

void main() {
  testWidgets('If shows then when isNotEmpty over state list', (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
        registry: registry, context: _testComponentContext());

    registry.register('ProbeThen', (node, componentRegistry) {
      return const Text('then');
    });
    registry.register('ProbeElse', (node, componentRegistry) {
      return const Text('else');
    });

    final root = _component(
      'If',
      props: const <String, Object?>{
        'valuePath': r'$state.foo',
        'op': 'isNotEmpty',
      },
      slots: <String, List<SchemaNode>>{
        'then': <SchemaNode>[_component('ProbeThen')],
        'else': <SchemaNode>[_component('ProbeElse')],
      },
    );

    final store = SchemaStateStore(
      initial: <String, Object?>{
        'foo': <Object?>[1]
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaStateScope(
          store: store,
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('then'), findsOneWidget);
    expect(find.text('else'), findsNothing);

    store.setValue('foo', <Object?>[]);
    await tester.pumpAndSettle();

    expect(find.text('then'), findsNothing);
    expect(find.text('else'), findsOneWidget);
  });

  testWidgets('If treats null as empty for isEmpty', (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
        registry: registry, context: _testComponentContext());

    registry.register('ProbeThen', (node, componentRegistry) {
      return const Text('then');
    });

    final root = _component(
      'If',
      props: const <String, Object?>{
        'valuePath': r'$state.missing',
        'op': 'isEmpty',
      },
      slots: <String, List<SchemaNode>>{
        'then': <SchemaNode>[_component('ProbeThen')],
      },
    );

    final store = SchemaStateStore(initial: const <String, Object?>{});

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaStateScope(
          store: store,
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('then'), findsOneWidget);
  });

  testWidgets('If still renders unknown-op error for unsupported op',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
        registry: registry, context: _testComponentContext());

    final root = _component(
      'If',
      props: const <String, Object?>{
        'valuePath': r'$state.foo',
        'op': 'wat',
      },
      slots: <String, List<SchemaNode>>{
        'then': <SchemaNode>[_component('Gap')],
      },
    );

    final store =
        SchemaStateStore(initial: const <String, Object?>{'foo': true});

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaStateScope(
          store: store,
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.text('Unsupported schema component: If(unknown-op)'),
      findsOneWidget,
    );
  });
}
