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

  testWidgets('NavigatorSchemaActionDispatcher supports set_state {path,value}',
      (tester) async {
    final store = SchemaStateStore();
    const dispatcher = NavigatorSchemaActionDispatcher();
    const action1 = ActionDefinition(
      type: 'set_state',
      value: <String, Object?>{
        'path': 'q',
        'value': 'abc',
      },
    );

    const action2 = ActionDefinition(
      type: 'set_state',
      value: <String, Object?>{
        'path': 'limit',
        'value': 10,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const _Home(),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));
    await dispatcher.dispatch(context, action1);
    await dispatcher.dispatch(context, action2);

    expect(store.getValue('q'), 'abc');
    expect(store.getValue('limit'), 10);
  });

  testWidgets(
      'NavigatorSchemaActionDispatcher evaluates expressions in set_state/patch_state values',
      (tester) async {
    final store = SchemaStateStore();
    store.setValue('a', 2);
    const dispatcher = NavigatorSchemaActionDispatcher();

    const setTyped = ActionDefinition(
      type: 'set_state',
      value: <String, Object?>{
        'path': 'b',
        'value': r'${state.a + 1}',
      },
    );

    const setExprObject = ActionDefinition(
      type: 'set_state',
      value: <String, Object?>{
        'path': 'c',
        'value': <String, Object?>{r'$expr': 'state.a + 2'},
      },
    );

    const patch = ActionDefinition(
      type: 'patch_state',
      value: <String, Object?>{
        'ops': <Object?>[
          <String, Object?>{
            'op': 'increment',
            'path': 'a',
            'by': r'${2}',
          },
          <String, Object?>{
            'op': 'set',
            'path': 'msg',
            'value': 'x \${state.a}',
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const _Home(),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    await dispatcher.dispatch(context, setTyped);
    await dispatcher.dispatch(context, setExprObject);
    await dispatcher.dispatch(context, patch);

    expect(store.getValue('b'), 3);
    expect(store.getValue('c'), 4);
    expect(store.getValue('a'), 4);
    expect(store.getValue('msg'), 'x 4');
  });

  testWidgets('NavigatorSchemaActionDispatcher supports patch_state ops',
      (tester) async {
    final store = SchemaStateStore();
    const dispatcher = NavigatorSchemaActionDispatcher();
    const action = ActionDefinition(
      type: 'patch_state',
      value: <String, Object?>{
        'ops': <Object?>[
          <String, Object?>{
            'op': 'set',
            'path': 'pharmacy.cart.items',
            'value': <Object?>[],
          },
          <String, Object?>{
            'op': 'append',
            'path': 'pharmacy.cart.items',
            'value': <String, Object?>{'id': '1', 'quantity': 1},
          },
          <String, Object?>{
            'op': 'increment',
            'path': 'pharmacy.cart.totalQuantity',
            'by': 1,
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const _Home(),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));
    await dispatcher.dispatch(context, action);

    expect(store.getValue('pharmacy.cart.totalQuantity'), 1);
    final items = store.getValue('pharmacy.cart.items');
    expect(items, isA<List>());
    expect((items as List).length, 1);
    expect((items.first as Map)['id'], '1');
  });
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox(key: Key('home')));
  }
}
