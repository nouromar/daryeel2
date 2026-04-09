import 'package:customer_app/src/actions/customer_action_dispatcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pharmacy_cart_upsert upserts and increments quantity', (
    tester,
  ) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'lines': <Object?>[],
            'totalQuantity': 0,
            'hasRxItem': false,
          },
        },
      },
    );

    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final dispatcher = CustomerActionDispatcher(
      delegate: const UnsupportedSchemaActionDispatcher(),
    );

    await dispatcher.dispatch(
      captured,
      ActionDefinition(
        type: CustomerActionDispatcher.pharmacyCartUpsert,
        value: <String, Object?>{
          'id': 'abc',
          'title': 'Item',
          'subtitle': '\$19',
          'rxRequired': false,
        },
      ),
    );

    expect(store.getValue('pharmacy.cart.totalQuantity'), 1);
    expect(store.getValue('pharmacy.cart.hasRxItem'), false);

    final lines = store.getValue('pharmacy.cart.lines');
    expect(lines, isA<List>());
    expect((lines as List).length, 1);
    final first = (lines.first as Map);
    expect(first['id'], 'abc');
    expect(first['quantity'], 1);

    await dispatcher.dispatch(
      captured,
      ActionDefinition(
        type: CustomerActionDispatcher.pharmacyCartUpsert,
        value: <String, Object?>{
          'id': 'abc',
          'title': 'Item',
          'subtitle': '\$19',
          'rxRequired': false,
        },
      ),
    );

    final lines2 = store.getValue('pharmacy.cart.lines') as List;
    expect(lines2.length, 1);
    final first2 = lines2.first as Map;
    expect(first2['quantity'], 2);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 2);
  });

  testWidgets('pharmacy_cart_decrement removes line at 1', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'lines': <Object?>[
              <String, Object?>{
                'id': 'abc',
                'title': 'Item',
                'subtitle': '',
                'rxRequired': false,
                'quantity': 1,
                'meta': 'Qty: 1',
              },
            ],
            'totalQuantity': 1,
            'hasRxItem': false,
          },
        },
      },
    );

    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final dispatcher = CustomerActionDispatcher(
      delegate: const UnsupportedSchemaActionDispatcher(),
    );

    await dispatcher.dispatch(
      captured,
      ActionDefinition(
        type: CustomerActionDispatcher.pharmacyCartDecrement,
        value: <String, Object?>{'id': 'abc'},
      ),
    );

    expect(store.getValue('pharmacy.cart.totalQuantity'), 0);
    final lines = store.getValue('pharmacy.cart.lines') as List;
    expect(lines, isEmpty);
  });

  testWidgets('legacy itemsById migrates to lines', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'itemsById': <String, Object?>{
              'abc': <String, Object?>{
                'title': 'Old',
                'subtitle': '',
                'quantity': 2,
                'rxRequired': true,
              },
            },
          },
        },
      },
    );

    migrateLegacyPharmacyCartState(store);

    expect(store.getValue('pharmacy.cart.itemsById'), isNull);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 2);
    expect(store.getValue('pharmacy.cart.hasRxItem'), true);

    final lines = store.getValue('pharmacy.cart.lines') as List;
    expect(lines.length, 1);
    final first = lines.first as Map;
    expect(first['id'], 'abc');
    expect(first['quantity'], 2);
  });
}
