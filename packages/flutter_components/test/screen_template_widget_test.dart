import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ScreenTemplateWidget uses configurable headerGap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScreenTemplateWidget(
          header: <Widget>[Text('H')],
          body: <Widget>[Text('B')],
          footer: <Widget>[],
          headerGap: 12,
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 12,
      ),
      findsOneWidget,
    );
  });

  testWidgets('ScreenTemplateWidget uses configurable bodyPadding',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScreenTemplateWidget(
          header: <Widget>[],
          body: <Widget>[Text('B')],
          footer: <Widget>[],
          bodyPadding: EdgeInsets.all(20),
        ),
      ),
    );

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.padding, const EdgeInsets.all(20));
  });
}
