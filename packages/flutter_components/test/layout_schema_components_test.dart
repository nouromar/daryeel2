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

SchemaWidgetRegistry _testRegistry() {
  final registry = SchemaWidgetRegistry();
  final context = _testComponentContext();

  registerRowSchemaComponent(registry: registry, context: context);
  registerColumnSchemaComponent(registry: registry, context: context);
  registerStackSchemaComponent(registry: registry, context: context);
  registerWrapSchemaComponent(registry: registry, context: context);
  registerPaddingSchemaComponent(registry: registry, context: context);
  registerAlignSchemaComponent(registry: registry, context: context);
  registerSizedBoxSchemaComponent(registry: registry, context: context);
  registerExpandedSchemaComponent(registry: registry, context: context);

  registry.register('Probe', (node, componentRegistry) {
    final id = (node.props['id'] as String?) ?? 'x';
    return SizedBox(
      key: ValueKey<String>('probe:$id'),
      width: 1,
      height: 1,
    );
  });

  return registry;
}

void main() {
  testWidgets('Row applies spacing between children', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Row',
      props: const <String, Object?>{
        'spacing': 10,
      },
      slots: <String, List<SchemaNode>>{
        'children': <SchemaNode>[
          _component('Probe', props: const <String, Object?>{'id': 'a'}),
          _component('Probe', props: const <String, Object?>{'id': 'b'}),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaRenderer(rootNode: root, registry: registry).render(),
      ),
    );

    expect(find.byType(Row), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.width == 10),
      findsOneWidget,
    );
  });

  testWidgets('Column applies spacing between children', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Column',
      props: const <String, Object?>{
        'spacing': 8,
      },
      slots: <String, List<SchemaNode>>{
        'children': <SchemaNode>[
          _component('Probe', props: const <String, Object?>{'id': 'a'}),
          _component('Probe', props: const <String, Object?>{'id': 'b'}),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaRenderer(rootNode: root, registry: registry).render(),
      ),
    );

    expect(find.byType(Column), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 8),
      findsOneWidget,
    );
  });

  testWidgets('Padding computes EdgeInsets from props', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Padding',
      props: const <String, Object?>{
        'horizontal': 4,
        'vertical': 6,
      },
      slots: <String, List<SchemaNode>>{
        'child': <SchemaNode>[
          _component('Probe', props: const <String, Object?>{'id': 'a'}),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaRenderer(rootNode: root, registry: registry).render(),
      ),
    );

    final padding = tester.widget<Padding>(find.byType(Padding));
    expect(padding.padding, const EdgeInsets.fromLTRB(4, 6, 4, 6));
    expect(find.byKey(const ValueKey<String>('probe:a')), findsOneWidget);
  });

  testWidgets('Align resolves alignment enum', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Align',
      props: const <String, Object?>{
        'alignment': 'topLeft',
      },
      slots: <String, List<SchemaNode>>{
        'child': <SchemaNode>[
          _component('Probe', props: const <String, Object?>{'id': 'a'}),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaRenderer(rootNode: root, registry: registry).render(),
      ),
    );

    final align = tester.widget<Align>(find.byType(Align));
    expect(align.alignment, Alignment.topLeft);
  });

  testWidgets('Stack resolves alignment + fit + clip', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Stack',
      props: const <String, Object?>{
        'alignment': 'bottomRight',
        'fit': 'expand',
        'clipBehavior': 'hardEdge',
      },
      slots: <String, List<SchemaNode>>{
        'children': <SchemaNode>[
          _component('Probe', props: const <String, Object?>{'id': 'a'}),
          _component('Probe', props: const <String, Object?>{'id': 'b'}),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaRenderer(rootNode: root, registry: registry).render(),
      ),
    );

    final stack = tester.widget<Stack>(find.byType(Stack));
    expect(stack.alignment, Alignment.bottomRight);
    expect(stack.fit, StackFit.expand);
    expect(stack.clipBehavior, Clip.hardEdge);
  });

  testWidgets('Wrap resolves direction + spacing', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Wrap',
      props: const <String, Object?>{
        'direction': 'vertical',
        'spacing': 2,
        'runSpacing': 3,
      },
      slots: <String, List<SchemaNode>>{
        'children': <SchemaNode>[
          _component('Probe', props: const <String, Object?>{'id': 'a'}),
          _component('Probe', props: const <String, Object?>{'id': 'b'}),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SchemaRenderer(rootNode: root, registry: registry).render(),
      ),
    );

    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.direction, Axis.vertical);
    expect(wrap.spacing, 2);
    expect(wrap.runSpacing, 3);
  });

  testWidgets('Expanded renders inside Row', (tester) async {
    final registry = _testRegistry();

    final root = _component(
      'Row',
      slots: <String, List<SchemaNode>>{
        'children': <SchemaNode>[
          _component(
            'Expanded',
            slots: <String, List<SchemaNode>>{
              'child': <SchemaNode>[
                _component('Probe', props: const <String, Object?>{'id': 'a'}),
              ],
            },
          ),
        ],
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 100,
          child: SchemaRenderer(rootNode: root, registry: registry).render(),
        ),
      ),
    );

    expect(find.byType(Row), findsOneWidget);
    expect(find.byType(Expanded), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('probe:a')), findsOneWidget);
  });
}
