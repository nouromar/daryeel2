import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

SchemaComponentContext _testContext(ScreenSchema screen) {
  return SchemaComponentContext(
    screen: screen,
    actionDispatcher: const UnsupportedSchemaActionDispatcher(),
    visibility: const SchemaVisibilityContext(),
  );
}

const ComponentNode _cartSummaryNode = ComponentNode(
  type: 'CartSummary',
  props: <String, Object?>{
    'title': 'Order summary',
    'linesPath': r'$state.pharmacy.cart.summary.lines',
    'totalPath': r'$state.pharmacy.cart.summary.total',
  },
  slots: <String, List<SchemaNode>>{},
  actions: <String, String>{},
  bind: null,
  visibleWhen: null,
);

void main() {
  testWidgets('CartSummary schema component reads summary state',
      (tester) async {
    final screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 'cart',
      documentType: 'screen',
      product: 'test',
      service: null,
      themeId: 'test',
      themeMode: null,
      root: _cartSummaryNode,
      actions: const <String, ActionDefinition>{},
    );

    final registry = SchemaWidgetRegistry();
    registerCartSummarySchemaComponent(
      registry: registry,
      context: _testContext(screen),
    );

    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'summary': <String, Object?>{
              'lines': <Object?>[
                <String, Object?>{
                  'label': 'Subtotal',
                  'amount': 14,
                  'amountText': r'$14.00',
                },
                <String, Object?>{
                  'label': 'Tax',
                  'amount': 0,
                  'amountText': r'$0.00',
                },
              ],
              'total': <String, Object?>{
                'label': 'Total',
                'amount': 14,
                'amountText': r'$14.00',
              },
            },
          },
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaStateScope(
            store: store,
            child: SchemaRenderer(
              rootNode: _cartSummaryNode,
              registry: registry,
            ).render(),
          ),
        ),
      ),
    );

    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Tax'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
  });
}
