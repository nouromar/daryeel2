import 'package:customer_app/src/actions/customer_action_dispatcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingDelegateDispatcher extends SchemaActionDispatcher {
  _RecordingDelegateDispatcher();

  ActionDefinition? last;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    last = action;
  }
}

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
      const ActionDefinition(
        type: CustomerActionDispatcher.pharmacyCartUpsert,
        value: <String, Object?>{
          'id': 'abc',
          'name': 'Item',
          'subtitle': '12 tablets',
          'rx_required': 'false',
          'price': 19,
          'icon': 'pharmacy',
          'route': '/catalog/item/abc',
        },
      ),
    );

    expect(store.getValue('pharmacy.cart.totalQuantity'), 1);
    expect(store.getValue('pharmacy.cart.hasRxItem'), false);

    final lines = store.getValue('pharmacy.cart.lines');
    expect(lines, isA<List>());
    expect((lines as List).length, 1);
    final first = lines.first as Map;
    expect(first['id'], 'abc');
    expect(first['name'], 'Item');
    expect(first['quantity'], 1);
    expect(first['price'], 19);
    expect(first['icon'], 'pharmacy');
    expect(first['route'], '/catalog/item/abc');
    expect(store.getValue('pharmacy.cart.summary.isRefreshing'), true);

    await dispatcher.dispatch(
      captured,
      const ActionDefinition(
        type: CustomerActionDispatcher.pharmacyCartUpsert,
        value: <String, Object?>{
          'id': 'abc',
          'name': 'Item',
          'subtitle': '12 tablets',
          'rx_required': 'false',
          'price': 19,
          'icon': 'pharmacy',
          'route': '/catalog/item/abc',
        },
      ),
    );

    final lines2 = store.getValue('pharmacy.cart.lines') as List;
    expect(lines2.length, 1);
    final first2 = lines2.first as Map;
    expect(first2['quantity'], 2);
    expect(first2['icon'], 'pharmacy');
    expect(first2['route'], '/catalog/item/abc');
    expect(store.getValue('pharmacy.cart.totalQuantity'), 2);

    await tester.pump(const Duration(milliseconds: 350));

    final summaryLines = store.getValue('pharmacy.cart.summary.lines') as List;
    expect(summaryLines, hasLength(3));
    expect((summaryLines.first as Map)['label'], 'Subtotal');

    final total = store.getValue('pharmacy.cart.summary.total') as Map;
    expect(total['amountText'], r'$38.00');
  });

  testWidgets(
    'pharmacy_cart_upsert accepts rxRequired boolean and drops price-only subtitle',
    (tester) async {
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
        const ActionDefinition(
          type: CustomerActionDispatcher.pharmacyCartUpsert,
          value: <String, Object?>{
            'id': 'rx1',
            'name': 'Rx Item',
            'subtitle': r'$19.00',
            'rxRequired': true,
            'price': 19,
          },
        ),
      );

      expect(store.getValue('pharmacy.cart.totalQuantity'), 1);
      expect(store.getValue('pharmacy.cart.hasRxItem'), true);

      final lines = store.getValue('pharmacy.cart.lines') as List;
      expect(lines, hasLength(1));
      final first = lines.first as Map;
      expect(first['rx_required'], true);
      expect(first['rxRequired'], true);
      expect(first['subtitle'], '');

      // Allow the cart summary refresh debounce timer to complete.
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets('pharmacy_cart_decrement removes line at 1', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'lines': <Object?>[
              <String, Object?>{
                'id': 'abc',
                'name': 'Item',
                'subtitle': '',
                'rx_required': false,
                'quantity': 1,
                'price': 19,
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
      const ActionDefinition(
        type: CustomerActionDispatcher.pharmacyCartDecrement,
        value: <String, Object?>{'id': 'abc'},
      ),
    );

    expect(store.getValue('pharmacy.cart.totalQuantity'), 0);
    final lines = store.getValue('pharmacy.cart.lines') as List;
    expect(lines, isEmpty);

    final total = store.getValue('pharmacy.cart.summary.total') as Map;
    expect(total['amount'], 0);
  });

  testWidgets(
    'pharmacy_cart_refresh_summary supports debounced manual refresh',
    (tester) async {
      final store = SchemaStateStore(
        initial: <String, Object?>{
          'pharmacy': <String, Object?>{
            'cart': <String, Object?>{
              'lines': <Object?>[
                <String, Object?>{
                  'id': 'abc',
                  'name': 'Item',
                  'subtitle': '',
                  'rx_required': false,
                  'quantity': 2,
                  'price': 12.5,
                },
              ],
              'discount': 2,
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
        const ActionDefinition(
          type: CustomerActionDispatcher.pharmacyCartRefreshSummary,
          value: <String, Object?>{'debounceMs': 50},
        ),
      );

      expect(store.getValue('pharmacy.cart.summary.total'), isNull);
      expect(store.getValue('pharmacy.cart.summary.isRefreshing'), true);

      await tester.pump(const Duration(milliseconds: 60));

      final total = store.getValue('pharmacy.cart.summary.total') as Map;
      expect(total['amountText'], r'$23.00');
    },
  );

  testWidgets('unknown action types delegate to fallback dispatcher', (
    tester,
  ) async {
    late BuildContext captured;
    final delegate = _RecordingDelegateDispatcher();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final dispatcher = CustomerActionDispatcher(delegate: delegate);
    const action = ActionDefinition(type: 'navigate', route: '/next');

    await dispatcher.dispatch(captured, action);

    expect(delegate.last, same(action));
  });
}
