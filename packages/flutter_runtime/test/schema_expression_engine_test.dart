import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('evaluateSchemaExpression supports core operators',
      (tester) async {
    final store = SchemaStateStore();
    store.setValue('a', 2);
    store.setValue('items', const <Object?>['A', 'B']);

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: SchemaRouteScope(
            params: const {'n': 5},
            child: SchemaDataScope(
              data: const {
                'items': [
                  {'name': 'A'},
                  {'name': 'B'},
                ],
              },
              item: const {'qty': 2, 'name': 'Panadol'},
              index: 1,
              child: const _Home(),
            ),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    expect(evaluateSchemaExpression('1 + 2 * 3', context), 7);
    expect(evaluateSchemaExpression('true && false', context), false);
    expect(evaluateSchemaExpression('true || false', context), true);
    expect(evaluateSchemaExpression('!false', context), true);
    expect(evaluateSchemaExpression('true and false', context), false);
    expect(evaluateSchemaExpression('true or false', context), true);
    expect(evaluateSchemaExpression('not false', context), true);
    expect(
      evaluateSchemaExpression(
          'len(state.items) == 2 and state.a == 2', context),
      true,
    );

    expect(evaluateSchemaExpression('state.a + 1', context), 3);
    expect(evaluateSchemaExpression('item.qty * 2', context), 4);
    expect(evaluateSchemaExpression('index', context), 1);

    expect(evaluateSchemaExpression("'a' + 1", context), 'a1');
    expect(
      evaluateSchemaExpression("state.missing ?? 'fallback'", context),
      'fallback',
    );

    expect(
      evaluateSchemaExpression("state.a > 1 ? 'yes' : 'no'", context),
      'yes',
    );
  });

  testWidgets('evaluateSchemaExpression supports allowlisted functions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: SchemaStateStore(),
          child: const SchemaDataScope(
            data: {
              'items': [
                {'name': 'A'},
              ],
            },
            item: {'name': 'Panadol'},
            child: _Home(),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    expect(evaluateSchemaExpression("len('abc')", context), 3);
    expect(evaluateSchemaExpression("toString(null)", context), '');
    expect(evaluateSchemaExpression("toNum('3.5') + 1", context), 4.5);
    expect(evaluateSchemaExpression("toInt('3.9')", context), 3);

    expect(
      evaluateSchemaExpression("get(item, 'name', 'X')", context),
      'Panadol',
    );

    expect(
      evaluateSchemaExpression(
        "get(at(data.items, 0), 'name', 'X')",
        context,
      ),
      'A',
    );

    expect(evaluateSchemaExpression('isNull(null)', context), true);
    expect(evaluateSchemaExpression("isNull('')", context), false);
    expect(evaluateSchemaExpression('isNotNull(null)', context), false);
    expect(evaluateSchemaExpression("isNotNull('x')", context), true);

    expect(evaluateSchemaExpression("isEmpty('')", context), true);
    expect(evaluateSchemaExpression("isEmpty('   ')", context), false);
    expect(evaluateSchemaExpression('isEmpty(null)', context), false);
    expect(evaluateSchemaExpression("isNotEmpty('x')", context), true);

    expect(evaluateSchemaExpression('isBlank(null)', context), true);
    expect(evaluateSchemaExpression("isBlank('')", context), true);
    expect(evaluateSchemaExpression("isBlank('   ')", context), true);
    expect(evaluateSchemaExpression("isNotBlank('x')", context), true);
  });

  testWidgets('interpolateSchemaTemplate evaluates \${...} segments',
      (tester) async {
    final store = SchemaStateStore();
    store.setValue('a', 2);
    store.setValue('items', const <Object?>['x', 'y']);

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const SchemaDataScope(
            child: _Home(),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    expect(
      interpolateSchemaTemplate('x \${state.a + 1} y', context),
      'x 3 y',
    );

    // Ensure placeholder parsing ignores braces inside strings.
    expect(
      interpolateSchemaTemplate('x ' r'${"a}b"}' ' y', context),
      'x a}b y',
    );
  });

  testWidgets('evaluateSchemaValue supports typed and template rules',
      (tester) async {
    final store = SchemaStateStore();
    store.setValue('a', 2);

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: store,
          child: const SchemaDataScope(
            child: _Home(),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    expect(evaluateSchemaValue(r'${1 + 2}', context), 3);
    expect(evaluateSchemaValue('x \${1 + 2}', context), 'x 3');
    expect(evaluateSchemaValue(const {r'$expr': '1 + 2'}, context), 3);

    expect(
      evaluateSchemaValue(
        const {
          'a': r'${1 + 2}',
          'b': {r'$expr': 'state.a + 1'},
          'c': [r'${state.a}', 'x \${state.a}'],
        },
        context,
      ),
      {
        'a': 3,
        'b': 3,
        'c': [2, 'x 2'],
      },
    );
  });

  testWidgets('evaluateSchemaValue enforces key security budgets',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaStateScope(
          store: SchemaStateStore(),
          child: const SchemaDataScope(child: _Home()),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('home')));

    final tooLongExpr =
        List.filled(SecurityBudgets.maxExprChars + 1, '0').join();
    expect(evaluateSchemaValue('\${$tooLongExpr}', context), isNull);

    final tooLongTemplate = List.filled(
      SecurityBudgets.maxExprTemplateInputChars + 1,
      'a',
    ).join();
    expect(evaluateSchemaValue(tooLongTemplate, context), '');

    final hugeList = List<int>.generate(
      SecurityBudgets.maxExprValueItemsPerList + 1,
      (i) => i,
      growable: false,
    );
    expect(evaluateSchemaValue(hugeList, context), const <Object?>[]);

    final hugeMap = <String, Object?>{
      for (var i = 0; i < SecurityBudgets.maxExprValueEntriesPerMap + 1; i++)
        'k$i': i,
    };
    expect(evaluateSchemaValue(hugeMap, context), const <String, Object?>{});
  });
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox(key: Key('home')));
  }
}
