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

const ComponentNode _paymentNode = ComponentNode(
  type: 'PaymentOptionsSection',
  props: <String, Object?>{
    'title': 'Payment',
    'methodTitle': 'Payment method',
    'timingTitle': 'Payment timing',
    'methodsPath': 'payment_options.methods',
    'timingsPath': 'payment_options.timings',
    'methodBind': r'$state.pharmacy.checkout.payment.method',
    'timingBind': r'$state.pharmacy.checkout.payment.timing',
    'showTiming': true,
  },
  slots: <String, List<SchemaNode>>{},
  actions: <String, String>{},
  bind: null,
  visibleWhen: null,
);

const ComponentNode _paymentMethodOnlyNode = ComponentNode(
  type: 'PaymentOptionsSection',
  props: <String, Object?>{
    'title': 'Payment',
    'methodTitle': 'Payment method',
    'methodsPath': 'payment_options.methods',
    'timingsPath': 'payment_options.timings',
    'methodBind': r'$state.pharmacy.checkout.payment.method',
    'timingBind': r'$state.pharmacy.checkout.payment.timing',
    'showTiming': false,
  },
  slots: <String, List<SchemaNode>>{},
  actions: <String, String>{},
  bind: null,
  visibleWhen: null,
);

void main() {
  testWidgets('PaymentOptionsSection reads options and updates state', (
    tester,
  ) async {
    final screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 'checkout',
      documentType: 'screen',
      product: 'test',
      service: null,
      themeId: 'test',
      themeMode: null,
      root: _paymentNode,
      actions: const <String, ActionDefinition>{},
    );

    final registry = SchemaWidgetRegistry();
    registerPaymentOptionsSectionSchemaComponent(
      registry: registry,
      context: _testContext(screen),
    );

    final store = SchemaStateStore(
      initial: const <String, Object?>{
        'pharmacy.checkout.payment.method': 'cash',
        'pharmacy.checkout.payment.timing': 'after_delivery',
      },
    );

    const data = <String, Object?>{
      'payment_options': <String, Object?>{
        'methods': <Object?>[
          <String, Object?>{
            'id': 'cash',
            'label': 'Cash',
            'description': 'Pay with cash',
          },
          <String, Object?>{
            'id': 'mobile_money',
            'label': 'Mobile money',
            'description': 'Pay with wallet',
          },
        ],
        'timings': <Object?>[
          <String, Object?>{
            'id': 'after_delivery',
            'label': 'After delivery',
          },
          <String, Object?>{
            'id': 'before_delivery',
            'label': 'Before delivery',
          },
        ],
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaStateScope(
            store: store,
            child: SchemaDataScope(
              data: data,
              child: SchemaRenderer(rootNode: _paymentNode, registry: registry)
                  .render(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Mobile money'), findsOneWidget);
    expect(find.text('After delivery'), findsOneWidget);
    expect(find.text('Before delivery'), findsOneWidget);

    await tester.tap(find.text('Mobile money'));
    await tester.pump();
    expect(store.getValue('pharmacy.checkout.payment.method'), 'mobile_money');

    await tester.tap(find.text('Before delivery'));
    await tester.pump();
    expect(
      store.getValue('pharmacy.checkout.payment.timing'),
      'before_delivery',
    );
  });

  testWidgets('PaymentOptionsSection can hide timing options', (tester) async {
    final screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 'checkout',
      documentType: 'screen',
      product: 'test',
      service: null,
      themeId: 'test',
      themeMode: null,
      root: _paymentMethodOnlyNode,
      actions: const <String, ActionDefinition>{},
    );

    final registry = SchemaWidgetRegistry();
    registerPaymentOptionsSectionSchemaComponent(
      registry: registry,
      context: _testContext(screen),
    );

    final store = SchemaStateStore(
      initial: const <String, Object?>{
        'pharmacy.checkout.payment.method': 'cash',
        'pharmacy.checkout.payment.timing': 'after_delivery',
      },
    );

    const data = <String, Object?>{
      'payment_options': <String, Object?>{
        'methods': <Object?>[
          <String, Object?>{'id': 'cash', 'label': 'Cash'},
          <String, Object?>{'id': 'mobile_money', 'label': 'Mobile money'},
        ],
        'timings': <Object?>[
          <String, Object?>{'id': 'after_delivery', 'label': 'After delivery'},
          <String, Object?>{
            'id': 'before_delivery',
            'label': 'Before delivery'
          },
        ],
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaStateScope(
            store: store,
            child: SchemaDataScope(
              data: data,
              child: SchemaRenderer(
                rootNode: _paymentMethodOnlyNode,
                registry: registry,
              ).render(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Mobile money'), findsOneWidget);
    expect(find.text('After delivery'), findsNothing);
    expect(find.text('Before delivery'), findsNothing);
    expect(
      store.getValue('pharmacy.checkout.payment.timing'),
      'after_delivery',
    );
  });
}
