import 'package:customer_app/src/services/pharmacy/ui/pharmacy_cart_items_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows Attach Prescription link when Rx items exist and none attached',
    (tester) async {
      final store = SchemaStateStore(
        initial: <String, Object?>{
          'pharmacy': <String, Object?>{
            'cart': <String, Object?>{
              'totalQuantity': 1,
              'itemsById': <String, Object?>{
                'abc': <String, Object?>{
                  'id': 'abc',
                  'title': 'Rx Item',
                  'quantity': 1,
                  'rxRequired': true,
                },
              },
            },
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SchemaStateScope(
            store: store,
            child: const Scaffold(body: PharmacyCartItemsWidget()),
          ),
        ),
      );

      expect(find.text('Attach Prescription'), findsOneWidget);
      expect(find.text('Checkout'), findsOneWidget);
    },
  );

  testWidgets(
    'shows "Prescription attached" when legacy prescriptionUploadId exists',
    (tester) async {
      final store = SchemaStateStore(
        initial: <String, Object?>{
          'pharmacy': <String, Object?>{
            'cart': <String, Object?>{
              'totalQuantity': 1,
              'prescriptionUploadId': 'upload_123',
              'itemsById': <String, Object?>{
                'abc': <String, Object?>{
                  'id': 'abc',
                  'title': 'Rx Item',
                  'quantity': 1,
                  'rxRequired': true,
                },
              },
            },
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SchemaStateScope(
            store: store,
            child: const Scaffold(body: PharmacyCartItemsWidget()),
          ),
        ),
      );

      expect(find.text('Prescription attached'), findsOneWidget);
      expect(find.text('Attach Prescription'), findsNothing);
    },
  );

  testWidgets('shows attached filenames when prescriptionUploads exist', (
    tester,
  ) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'totalQuantity': 1,
            'prescriptionUploads': <Object?>[
              <String, Object?>{'filename': 'rx1.jpg'},
              <String, Object?>{'filename': 'rx2.pdf'},
            ],
            'itemsById': <String, Object?>{
              'abc': <String, Object?>{
                'id': 'abc',
                'title': 'Rx Item',
                'quantity': 1,
                'rxRequired': true,
              },
            },
          },
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const Scaffold(body: PharmacyCartItemsWidget()),
        ),
      ),
    );

    expect(find.text('rx1.jpg'), findsOneWidget);
    expect(find.text('rx2.pdf'), findsOneWidget);
    expect(find.text('Attach Prescription'), findsNothing);
  });

  testWidgets('increase quantity increments line and total', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'totalQuantity': 1,
            'itemsById': <String, Object?>{
              'abc': <String, Object?>{
                'id': 'abc',
                'title': 'Item',
                'quantity': 1,
                'rxRequired': false,
              },
            },
          },
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const Scaffold(body: PharmacyCartItemsWidget()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();

    expect(store.getValue('pharmacy.cart.itemsById.abc.quantity'), 2);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 2);
  });

  testWidgets('decrease quantity removes line at 1', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'totalQuantity': 1,
            'itemsById': <String, Object?>{
              'abc': <String, Object?>{
                'id': 'abc',
                'title': 'Item',
                'quantity': 1,
                'rxRequired': false,
              },
            },
          },
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const Scaffold(body: PharmacyCartItemsWidget()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();

    expect(store.getValue('pharmacy.cart.itemsById.abc'), isNull);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 0);
    expect(find.text('Cart is empty'), findsOneWidget);
  });

  testWidgets('decrease quantity twice removes line at 2', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'totalQuantity': 2,
            'itemsById': <String, Object?>{
              'abc': <String, Object?>{
                'id': 'abc',
                'title': 'Item',
                'quantity': 2,
                'rxRequired': false,
              },
            },
          },
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const Scaffold(body: PharmacyCartItemsWidget()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();

    expect(store.getValue('pharmacy.cart.itemsById.abc.quantity'), 1);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 1);

    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();

    expect(store.getValue('pharmacy.cart.itemsById.abc'), isNull);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 0);
  });

  testWidgets('clear cart removes all items and resets total', (tester) async {
    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy': <String, Object?>{
          'cart': <String, Object?>{
            'totalQuantity': 2,
            'prescriptionUploads': <Object?>[
              <String, Object?>{'filename': 'rx1.jpg'},
            ],
            'itemsById': <String, Object?>{
              'abc': <String, Object?>{
                'id': 'abc',
                'title': 'Item',
                'quantity': 2,
                'rxRequired': false,
              },
            },
          },
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const Scaffold(body: PharmacyCartItemsWidget()),
        ),
      ),
    );

    await tester.tap(find.text('Clear cart'));
    await tester.pump();

    expect(store.getValue('pharmacy.cart.itemsById'), isNull);
    expect(store.getValue('pharmacy.cart.totalQuantity'), 0);
    expect(store.getValue('pharmacy.cart.prescriptionUploads'), isNull);
    expect(find.text('Cart is empty'), findsOneWidget);
  });
}
