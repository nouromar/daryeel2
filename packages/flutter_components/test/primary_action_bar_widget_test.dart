import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PrimaryActionBarWidget shrink-wraps when expand=false', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  key: Key('outerAlign'),
                  alignment: Alignment.centerRight,
                  child: PrimaryActionBarWidget(
                    primaryLabel: 'Attach Prescription',
                    expand: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final alignBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('outerAlign')),
    );
    final buttonBox = tester.renderObject<RenderBox>(find.byType(FilledButton));

    // Align should fill the available width (because Column is stretched), but
    // the button should only be as wide as its content.
    expect(alignBox.size.width, 500);
    expect(buttonBox.size.width, lessThan(500));
  });
}
