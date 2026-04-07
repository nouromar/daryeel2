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
  testWidgets('ForEach renders via ListView.builder and applies stable keys',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerForEachSchemaComponent(
      registry: registry,
      context: _testComponentContext(),
    );

    registry.register('Probe', (node, componentRegistry) {
      return Builder(
        builder: (context) {
          final scope = SchemaDataScope.of(context);
          final id = readJsonPath(scope.item, 'id');
          return Text('id:$id');
        },
      );
    });

    final root = _component(
      'ForEach',
      props: const <String, Object?>{
        'itemsPath': 'items',
        'itemKeyPath': 'id',
      },
      slots: <String, List<SchemaNode>>{
        'item': <SchemaNode>[
          _component('Probe'),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaDataScope(
          data: const <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'id': 'a'},
              <String, Object?>{'id': 'b'},
            ],
          },
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('id:a'), findsOneWidget);
    expect(find.text('id:b'), findsOneWidget);

    expect(find.byKey(const ValueKey<String>('item:a')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('item:b')), findsOneWidget);
  });

  testWidgets('ForEach defaults itemKeyPath to id', (tester) async {
    final registry = SchemaWidgetRegistry();
    registerForEachSchemaComponent(
      registry: registry,
      context: _testComponentContext(),
    );

    registry.register('Probe', (node, componentRegistry) {
      return Builder(
        builder: (context) {
          final scope = SchemaDataScope.of(context);
          final id = readJsonPath(scope.item, 'id');
          return Text('id:$id');
        },
      );
    });

    final root = _component(
      'ForEach',
      props: const <String, Object?>{
        'itemsPath': 'items',
      },
      slots: <String, List<SchemaNode>>{
        'item': <SchemaNode>[
          _component('Probe'),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaDataScope(
          data: const <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'id': 123},
            ],
          },
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('item:123')), findsOneWidget);
  });

  testWidgets('ForEach falls back to index key when missing id',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerForEachSchemaComponent(
      registry: registry,
      context: _testComponentContext(),
    );

    registry.register('Probe', (node, componentRegistry) {
      return const SizedBox(height: 10, width: 10);
    });

    final root = _component(
      'ForEach',
      props: const <String, Object?>{
        'itemsPath': 'items',
      },
      slots: <String, List<SchemaNode>>{
        'item': <SchemaNode>[
          _component('Probe'),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaDataScope(
          data: const <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'name': 'no-id'},
              <String, Object?>{'name': 'no-id-2'},
            ],
          },
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('item_index:0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('item_index:1')), findsOneWidget);
  });

  testWidgets('ForEach treats null items as empty list (data path)',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerForEachSchemaComponent(
      registry: registry,
      context: _testComponentContext(),
    );

    registry.register('Probe', (node, componentRegistry) {
      return const Text('probe');
    });

    final root = _component(
      'ForEach',
      props: const <String, Object?>{
        'itemsPath': 'items',
      },
      slots: <String, List<SchemaNode>>{
        'item': <SchemaNode>[
          _component('Probe'),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaDataScope(
          data: const <String, Object?>{},
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Unsupported schema component: ForEach(items-not-list)'),
      findsNothing,
    );
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('ForEach treats null items as empty list (state path)',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerForEachSchemaComponent(
      registry: registry,
      context: _testComponentContext(),
    );

    registry.register('Probe', (node, componentRegistry) {
      return const Text('probe');
    });

    final root = _component(
      'ForEach',
      props: const <String, Object?>{
        'itemsPath': r'$state.pharmacy.cart.prescriptionUploads',
      },
      slots: <String, List<SchemaNode>>{
        'item': <SchemaNode>[
          _component('Probe'),
        ],
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

    expect(
      find.text('Unsupported schema component: ForEach(items-not-list)'),
      findsNothing,
    );
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('ForEach still errors for non-null non-List items',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerForEachSchemaComponent(
      registry: registry,
      context: _testComponentContext(),
    );

    final root = _component(
      'ForEach',
      props: const <String, Object?>{
        'itemsPath': 'items',
      },
      slots: <String, List<SchemaNode>>{
        'item': <SchemaNode>[
          _component('Probe'),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaDataScope(
          data: const <String, Object?>{'items': <String, Object?>{}},
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Unsupported schema component: ForEach(items-not-list)'),
      findsOneWidget,
    );
  });
}
