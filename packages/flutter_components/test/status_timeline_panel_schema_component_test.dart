import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

final class _NoopDispatcher extends SchemaActionDispatcher {
  const _NoopDispatcher();

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
    actionDispatcher: const _NoopDispatcher(),
    visibility: const SchemaVisibilityContext(),
  );
}

ComponentNode _component(String type, {Map<String, Object?> props = const {}}) {
  return ComponentNode(
    type: type,
    props: props,
    slots: const <String, List<SchemaNode>>{},
    actions: const <String, String>{},
    bind: null,
    visibleWhen: null,
  );
}

void main() {
  testWidgets('StatusTimelinePanel renders items from data', (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
      registry: registry,
      context: _testComponentContext(),
    );

    final node = _component(
      'StatusTimelinePanel',
      props: const <String, Object?>{
        'title': 'Timeline',
        'itemsPath': 'timeline',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaDataScope(
            data: const <String, Object?>{
              'timeline': <Object?>[
                <String, Object?>{
                  'id': 'evt_1',
                  'title': 'Order placed',
                  'subtitle': '13:05',
                },
                <String, Object?>{
                  'id': 'evt_2',
                  'title': 'Processing',
                  'subtitle': '13:10',
                },
              ],
            },
            child: SchemaRenderer(rootNode: node, registry: registry).render(),
          ),
        ),
      ),
    );

    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Order placed'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('13:05'), findsOneWidget);
    expect(find.text('13:10'), findsOneWidget);

    expect(find.byKey(const ValueKey<String>('item:evt_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('item:evt_2')), findsOneWidget);
  });

  testWidgets('StatusTimelinePanel renders status left and date right',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
      registry: registry,
      context: _testComponentContext(),
    );

    final node = _component(
      'StatusTimelinePanel',
      props: const <String, Object?>{
        'title': 'Timeline',
        'itemsPath': 'timeline',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaDataScope(
            data: const <String, Object?>{
              'timeline': <Object?>[
                <String, Object?>{
                  'id': 'evt_1',
                  'title': 'Order placed',
                  'subtitle': '13:05',
                },
              ],
            },
            child: SchemaRenderer(rootNode: node, registry: registry).render(),
          ),
        ),
      ),
    );

    final rowFinder = find.descendant(
      of: find.byKey(const ValueKey<String>('item:evt_1')),
      matching: find.byType(Row),
    );

    expect(rowFinder, findsOneWidget);

    final row = tester.widget<Row>(rowFinder);
    expect(row.children.length, 3);

    final leftExpanded = row.children[0] as Expanded;
    final leftText = leftExpanded.child as Text;
    expect(leftText.data, 'Order placed');

    final rightFlexible = row.children[2] as Flexible;
    final rightText = rightFlexible.child as Text;
    expect(rightText.data, '13:05');
    expect(rightText.textAlign, TextAlign.right);
  });

  testWidgets('StatusTimelinePanel formats ISO subtitle dates by default',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
      registry: registry,
      context: _testComponentContext(),
    );

    final node = _component(
      'StatusTimelinePanel',
      props: const <String, Object?>{
        'title': 'Timeline',
        'itemsPath': 'timeline',
      },
    );

    final dt = DateTime.parse('2026-04-18T13:05:00Z').toLocal();
    final expected = DateFormat('dd/MM/yyyy hh:mm a', 'en_US').format(dt);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const <Locale>[Locale('en', 'US')],
        home: Scaffold(
          body: SchemaDataScope(
            data: <String, Object?>{
              'timeline': <Object?>[
                <String, Object?>{
                  'id': 'evt_1',
                  'title': 'Order placed',
                  'subtitle': '2026-04-18T13:05:00Z',
                },
              ],
            },
            child: SchemaRenderer(rootNode: node, registry: registry).render(),
          ),
        ),
      ),
    );

    expect(find.text(expected), findsOneWidget);
  });
}
