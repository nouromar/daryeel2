import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_components/src/schema_components/schema_node_wrapper.dart';
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
        type: 'Text',
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

ComponentNode _textNode({required Map<String, Object?> visibleWhen}) {
  return ComponentNode(
    type: 'Text',
    props: const <String, Object?>{'text': 'Hello'},
    slots: const <String, List<SchemaNode>>{},
    actions: const <String, String>{},
    bind: null,
    visibleWhen: visibleWhen,
  );
}

void main() {
  testWidgets('visibleWhen.expr hides and shows based on \$state',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    final componentContext = _testComponentContext();
    registerCoreSchemaComponents(registry: registry, context: componentContext);

    final store =
        SchemaStateStore(initial: const <String, Object?>{'show': false});

    final node =
        _textNode(visibleWhen: const <String, Object?>{'expr': 'state.show'});

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: SchemaRenderer(
            rootNode: node,
            registry: registry,
            wrapperBuilder: buildVisibleWhenWrapper(
              visibility: componentContext.visibility,
              diagnostics: componentContext.diagnostics,
              diagnosticsContext: componentContext.diagnosticsContext,
            ),
          ).render(),
        ),
      ),
    );

    expect(find.text('Hello'), findsNothing);

    store.setValue('show', true);
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets(r'visibleWhen.expr accepts ${...} wrapper', (tester) async {
    final registry = SchemaWidgetRegistry();
    final componentContext = _testComponentContext();
    registerCoreSchemaComponents(registry: registry, context: componentContext);

    final store =
        SchemaStateStore(initial: const <String, Object?>{'show': true});

    final node = _textNode(
        visibleWhen: const <String, Object?>{'expr': r'${state.show}'});

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: SchemaRenderer(
            rootNode: node,
            registry: registry,
            wrapperBuilder: buildVisibleWhenWrapper(
              visibility: componentContext.visibility,
              diagnostics: componentContext.diagnostics,
              diagnosticsContext: componentContext.diagnosticsContext,
            ),
          ).render(),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
  });
}
