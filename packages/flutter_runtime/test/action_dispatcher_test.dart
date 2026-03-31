import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NavigatorSchemaActionDispatcher pushes named route', (
    tester,
  ) async {
    const dispatcher = NavigatorSchemaActionDispatcher();
    const action = ActionDefinition(type: 'navigate', route: '/next');

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => const _Home(),
          '/next': (context) => const Scaffold(body: Text('Next screen')),
        },
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    await dispatcher.dispatch(context, action);
    await tester.pumpAndSettle();

    expect(find.text('Next screen'), findsOneWidget);
  });

  testWidgets('NavigatorSchemaActionDispatcher rejects missing route', (
    tester,
  ) async {
    const dispatcher = NavigatorSchemaActionDispatcher();
    const action = ActionDefinition(type: 'navigate');

    await tester.pumpWidget(
      const MaterialApp(
        home: _Home(),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    await expectLater(
      () => dispatcher.dispatch(context, action),
      throwsA(isA<ArgumentError>()),
    );
  });

  testWidgets('NavigatorSchemaActionDispatcher rejects unsupported type', (
    tester,
  ) async {
    const dispatcher = NavigatorSchemaActionDispatcher();
    const action = ActionDefinition(type: 'unknown');

    await tester.pumpWidget(
      const MaterialApp(
        home: _Home(),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    await expectLater(
      () => dispatcher.dispatch(context, action),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox(key: Key('home')));
  }
}
