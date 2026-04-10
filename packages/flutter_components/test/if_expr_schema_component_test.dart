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

ComponentNode _textNode(String text) {
  return ComponentNode(
    type: 'Text',
    props: <String, Object?>{'text': text},
    slots: const <String, List<SchemaNode>>{},
    actions: const <String, String>{},
    bind: null,
    visibleWhen: null,
  );
}

void main() {
  testWidgets('If.expr shows then/else and listens to state changes',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    final context = _testComponentContext();
    registerCoreSchemaComponents(registry: registry, context: context);

    final node = ComponentNode(
      type: 'If',
      props: const <String, Object?>{
        'expr': 'state.a > 0',
      },
      slots: <String, List<SchemaNode>>{
        'then': <SchemaNode>[_textNode('THEN')],
        'else': <SchemaNode>[_textNode('ELSE')],
      },
      actions: const <String, String>{},
      bind: null,
      visibleWhen: null,
    );

    final store = SchemaStateStore(initial: const <String, Object?>{'a': 0});

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: SchemaRenderer(rootNode: node, registry: registry).render(),
        ),
      ),
    );

    expect(find.text('ELSE'), findsOneWidget);
    expect(find.text('THEN'), findsNothing);

    store.setValue('a', 1);
    await tester.pump();

    expect(find.text('THEN'), findsOneWidget);
    expect(find.text('ELSE'), findsNothing);
  });

  testWidgets('If.expr accepts "\${...}" wrapper', (tester) async {
    final registry = SchemaWidgetRegistry();
    final context = _testComponentContext();
    registerCoreSchemaComponents(registry: registry, context: context);

    final node = ComponentNode(
      type: 'If',
      props: const <String, Object?>{
        'expr': r'${state.a == 2}',
      },
      slots: <String, List<SchemaNode>>{
        'then': <SchemaNode>[_textNode('YES')],
        'else': <SchemaNode>[_textNode('NO')],
      },
      actions: const <String, String>{},
      bind: null,
      visibleWhen: null,
    );

    final store = SchemaStateStore(initial: const <String, Object?>{'a': 2});

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: SchemaRenderer(rootNode: node, registry: registry).render(),
        ),
      ),
    );

    expect(find.text('YES'), findsOneWidget);
    expect(find.text('NO'), findsNothing);
  });
}
