import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingDispatcher extends SchemaActionDispatcher {
  final List<ActionDefinition> dispatched = <ActionDefinition>[];

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    dispatched.add(action);
  }
}

SchemaComponentContext _testContext(
    _RecordingDispatcher dispatcher, ScreenSchema screen) {
  return SchemaComponentContext(
    screen: screen,
    actionDispatcher: dispatcher,
    visibility: const SchemaVisibilityContext(),
  );
}

ComponentNode _cartItemNode() {
  return const ComponentNode(
    type: 'CartItem',
    props: <String, Object?>{
      'title': r'${item.title}',
      'subtitle': r'${item.subtitle}',
      'quantity': r'${item.quantity}',
      'unitPriceText': r'${item.unitPriceText}',
      'lineTotalText': r'${item.lineTotalText}',
      'badgeLabel': r'${item.badgeLabel}',
    },
    slots: <String, List<SchemaNode>>{},
    actions: <String, String>{
      'increment': 'inc',
      'decrement': 'dec',
    },
    bind: null,
    visibleWhen: null,
  );
}

ComponentNode _readonlyCartItemNode() {
  return const ComponentNode(
    type: 'CartItem',
    props: <String, Object?>{
      'title': r'${item.name}',
      'quantity': r'${item.quantity}',
      'readonly': true,
      'surface': 'flat',
      'density': 'compact',
    },
    slots: <String, List<SchemaNode>>{},
    actions: <String, String>{},
    bind: null,
    visibleWhen: null,
  );
}

ScreenSchema _screenWithActions() {
  return ScreenSchema(
    schemaVersion: '1.0',
    id: 'cart',
    documentType: 'screen',
    product: 'test',
    service: null,
    themeId: 'test',
    themeMode: null,
    root: _cartItemNode(),
    actions: const <String, ActionDefinition>{
      'inc': ActionDefinition(type: 'custom', value: 'increment'),
      'dec': ActionDefinition(type: 'custom', value: 'decrement'),
    },
  );
}

ScreenSchema _screenNoActions() {
  return ScreenSchema(
    schemaVersion: '1.0',
    id: 'request-detail',
    documentType: 'screen',
    product: 'test',
    service: null,
    themeId: 'test',
    themeMode: null,
    root: _readonlyCartItemNode(),
    actions: const <String, ActionDefinition>{},
  );
}

void main() {
  testWidgets('CartItem schema component renders interpolated item data', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();
    final screen = _screenWithActions();

    final registry = SchemaWidgetRegistry();
    registerCartItemSchemaComponent(
      registry: registry,
      context: _testContext(dispatcher, screen),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaDataScope(
            item: const <String, Object?>{
              'title': 'Vitamin C',
              'subtitle': 'Bottle of 60',
              'quantity': 3,
              'unitPriceText': r'$7.50',
              'lineTotalText': r'$22.50',
              'badgeLabel': 'Popular',
            },
            child: SchemaRenderer(
              rootNode: _cartItemNode(),
              registry: registry,
            ).render(),
          ),
        ),
      ),
    );

    expect(find.text('Vitamin C'), findsOneWidget);
    expect(find.text('Bottle of 60'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('CartItem schema component dispatches increment and decrement', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();
    final screen = _screenWithActions();

    final registry = SchemaWidgetRegistry();
    registerCartItemSchemaComponent(
      registry: registry,
      context: _testContext(dispatcher, screen),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaDataScope(
            item: const <String, Object?>{
              'title': 'Vitamin C',
              'quantity': 1,
            },
            child: SchemaRenderer(
              rootNode: _cartItemNode(),
              registry: registry,
            ).render(),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.tap(find.byTooltip('Remove item'));
    await tester.pump();

    expect(dispatcher.dispatched.length, 2);
    expect(dispatcher.dispatched[0].value, 'increment');
    expect(dispatcher.dispatched[1].value, 'decrement');
  });

  testWidgets(
      'CartItem schema component readonly shows badge and no stepper', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();
    final screen = _screenNoActions();

    final registry = SchemaWidgetRegistry();
    registerCartItemSchemaComponent(
      registry: registry,
      context: _testContext(dispatcher, screen),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaDataScope(
            item: const <String, Object?>{
              'name': 'Amoxicillin 500mg',
              'quantity': 2,
            },
            child: SchemaRenderer(
              rootNode: _readonlyCartItemNode(),
              registry: registry,
            ).render(),
          ),
        ),
      ),
    );

    expect(find.text('Amoxicillin 500mg'), findsOneWidget);
    expect(find.text('Qty 2'), findsOneWidget);
    expect(find.byTooltip('Increase quantity'), findsNothing);
    expect(find.byTooltip('Remove item'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets(
      'CartItem schema component readonly does not dispatch actions on tap', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();
    final screen = _screenNoActions();

    final registry = SchemaWidgetRegistry();
    registerCartItemSchemaComponent(
      registry: registry,
      context: _testContext(dispatcher, screen),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaDataScope(
            item: const <String, Object?>{
              'name': 'Ibuprofen 200mg',
              'quantity': 3,
            },
            child: SchemaRenderer(
              rootNode: _readonlyCartItemNode(),
              registry: registry,
            ).render(),
          ),
        ),
      ),
    );

    // No interactive controls should be present
    expect(find.byType(IconButton), findsNothing);
    expect(dispatcher.dispatched, isEmpty);
  });
}
