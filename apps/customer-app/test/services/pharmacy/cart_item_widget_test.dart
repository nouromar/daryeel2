import 'package:customer_app/src/services/pharmacy/ui/cart_item_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CartItemWidget renders content and quantity controls', (
    tester,
  ) async {
    var incrementCount = 0;
    var decrementCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CartItemWidget(
            title: 'Paracetamol 500mg',
            subtitle: 'Pack of 20 tablets',
            quantity: 2,
            unitPriceText: r'$4.50',
            lineTotalText: r'$9.00',
            badgeLabel: 'Rx',
            onIncrement: () => incrementCount += 1,
            onDecrement: () => decrementCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('Paracetamol 500mg'), findsOneWidget);
    expect(find.text('Pack of 20 tablets'), findsOneWidget);
    expect(find.text('Rx'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(r'Price: $4.50'), findsOneWidget);
    expect(find.text(r'Line: $9.00'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();

    expect(incrementCount, 1);
    expect(decrementCount, 1);
  });

  testWidgets('CartItemWidget shows remove affordance at quantity one', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CartItemWidget(title: 'Item', quantity: 1)),
      ),
    );

    expect(find.byTooltip('Remove item'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets(
    'CartItemWidget hides duplicate subtitle and duplicate line price',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CartItemWidget(
              title: 'Item',
              subtitle: r'$4.50',
              quantity: 1,
              unitPriceText: r'$4.50',
              lineTotalText: r'$4.50',
              badgeLabel: 'Rx',
            ),
          ),
        ),
      );

      expect(find.text(r'$4.50'), findsNothing);
      expect(find.text(r'Price: $4.50'), findsOneWidget);
      expect(find.textContaining('Line:'), findsNothing);
      expect(find.text('Rx'), findsOneWidget);
    },
  );

  testWidgets('CartItemWidget readonly shows quantity badge, no stepper', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CartItemWidget(
            title: 'Amoxicillin 500mg',
            quantity: 3,
            readonly: true,
          ),
        ),
      ),
    );

    expect(find.text('Amoxicillin 500mg'), findsOneWidget);
    expect(find.text('Qty 3'), findsOneWidget);
    expect(find.byTooltip('Increase quantity'), findsNothing);
    expect(find.byTooltip('Decrease quantity'), findsNothing);
    expect(find.byTooltip('Remove item'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets(
    'CartItemWidget readonly renders subtitle and meta when provided',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CartItemWidget(
              title: 'Ibuprofen 200mg',
              subtitle: 'Pack of 16',
              quantity: 2,
              unitPriceText: r'$3.00',
              lineTotalText: r'$6.00',
              badgeLabel: 'OTC',
              readonly: true,
            ),
          ),
        ),
      );

      expect(find.text('Ibuprofen 200mg'), findsOneWidget);
      expect(find.text('Pack of 16'), findsOneWidget);
      expect(find.text(r'Price: $3.00'), findsOneWidget);
      expect(find.text(r'Line: $6.00'), findsOneWidget);
      expect(find.text('OTC'), findsOneWidget);
      expect(find.text('Qty 2'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    },
  );

  testWidgets('CartItemWidget readonly compact uses smaller badge padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CartItemWidget(
            title: 'Item',
            quantity: 1,
            density: 'compact',
            readonly: true,
          ),
        ),
      ),
    );

    expect(find.text('Qty 1'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
