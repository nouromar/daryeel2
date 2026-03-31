import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evaluateVisibleWhen returns true when null/empty', () {
    const context = SchemaVisibilityContext();
    expect(evaluateVisibleWhen(null, context), isTrue);
    expect(evaluateVisibleWhen(const {}, context), isTrue);
  });

  test('evaluateVisibleWhen defaults to visible on unknown keys', () {
    const context = SchemaVisibilityContext();
    expect(evaluateVisibleWhen({'unknown': true}, context), isTrue);
  });

  test('evaluateVisibleWhen emits diagnostics for unknown keys', () {
    const context = SchemaVisibilityContext();

    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);

    expect(
      evaluateVisibleWhen(
        {'unknown': true},
        context,
        diagnostics: diagnostics,
        nodeType: 'InfoCard',
      ),
      isTrue,
    );

    expect(sink.events, isNotEmpty);
    expect(sink.events.first.eventName, 'runtime.visibility.unknown_rule_key');
  });

  test('evaluateVisibleWhen supports featureFlag string', () {
    final context = SchemaVisibilityContext(
      enabledFeatureFlags: {'a', 'b'},
    );

    expect(evaluateVisibleWhen({'featureFlag': 'a'}, context), isTrue);
    expect(evaluateVisibleWhen({'featureFlag': 'c'}, context), isFalse);
    expect(evaluateVisibleWhen({'featureFlag': ''}, context), isTrue);
  });

  test('evaluateVisibleWhen supports featureFlag list', () {
    final context = SchemaVisibilityContext(
      enabledFeatureFlags: {'b'},
    );

    expect(
      evaluateVisibleWhen({
        'featureFlag': ['a', 'b'],
      }, context),
      isTrue,
    );

    expect(
      evaluateVisibleWhen({
        'featureFlag': ['a', 'c'],
      }, context),
      isFalse,
    );
  });
}
