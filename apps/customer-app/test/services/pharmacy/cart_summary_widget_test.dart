import 'package:customer_app/src/services/pharmacy/ui/cart_summary_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CartSummaryWidget hides zero rows by default and shows total', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CartSummaryWidget(
            title: 'Order summary',
            lines: const <CartSummaryRowData>[
              CartSummaryRowData(
                label: 'Subtotal',
                amount: 12,
                amountText: r'$12.00',
              ),
              CartSummaryRowData(
                label: 'Tax',
                amount: 0,
                amountText: r'$0.00',
                kind: 'tax',
              ),
            ],
            total: const CartSummaryRowData(
              label: 'Total',
              amount: 12,
              amountText: r'$12.00',
              kind: 'total',
              emphasis: 'strong',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Order summary'), findsOneWidget);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Tax'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
  });

  testWidgets('CartSummaryWidget can show zero rows when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CartSummaryWidget(
            hideZeroLines: false,
            lines: <CartSummaryRowData>[
              CartSummaryRowData(
                label: 'Tax',
                amount: 0,
                amountText: r'$0.00',
                kind: 'tax',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Tax'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
  });
}
