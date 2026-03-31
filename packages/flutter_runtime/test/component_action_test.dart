import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingDispatcher extends SchemaActionDispatcher {
  _RecordingDispatcher();

  ActionDefinition? last;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    last = action;
  }
}

void main() {
  group('resolveComponentAction', () {
    test('returns null when slot missing', () {
      const screen = ScreenSchema(
        schemaVersion: '1.0',
        id: 's',
        documentType: 'screen',
        product: 'p',
        service: null,
        themeId: 't',
        themeMode: null,
        root: ComponentNode(
          type: 'X',
          props: {},
          slots: {},
          actions: {},
          bind: null,
          visibleWhen: null,
        ),
        actions: {
          'a': ActionDefinition(type: 'navigate', route: '/next'),
        },
      );

      const node = ComponentNode(
        type: 'PrimaryActionBar',
        props: {},
        slots: {},
        actions: {},
        bind: null,
        visibleWhen: null,
      );

      expect(
          resolveComponentAction(
            screen: screen,
            node: node,
            actionKey: 'primary',
          ),
          isNull);
    });

    test('returns action when present', () {
      const screen = ScreenSchema(
        schemaVersion: '1.0',
        id: 's',
        documentType: 'screen',
        product: 'p',
        service: null,
        themeId: 't',
        themeMode: null,
        root: ComponentNode(
          type: 'X',
          props: {},
          slots: {},
          actions: {},
          bind: null,
          visibleWhen: null,
        ),
        actions: {
          'open': ActionDefinition(type: 'navigate', route: '/next'),
        },
      );

      const node = ComponentNode(
        type: 'PrimaryActionBar',
        props: {},
        slots: {},
        actions: {'primary': 'open'},
        bind: null,
        visibleWhen: null,
      );

      final resolved = resolveComponentAction(
        screen: screen,
        node: node,
        actionKey: 'primary',
      );

      expect(resolved, isNotNull);
      expect(resolved!.type, 'navigate');
      expect(resolved.route, '/next');
    });
  });

  testWidgets('dispatchComponentAction calls dispatcher with resolved action', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();

    const screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 's',
      documentType: 'screen',
      product: 'p',
      service: null,
      themeId: 't',
      themeMode: null,
      root: ComponentNode(
        type: 'X',
        props: {},
        slots: {},
        actions: {},
        bind: null,
        visibleWhen: null,
      ),
      actions: {
        'open': ActionDefinition(type: 'navigate', route: '/next'),
      },
    );

    const node = ComponentNode(
      type: 'PrimaryActionBar',
      props: {},
      slots: {},
      actions: {'primary': 'open'},
      bind: null,
      visibleWhen: null,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox(key: Key('home')))),
    );

    final context = tester.element(find.byKey(const Key('home')));

    await dispatchComponentAction(
      context: context,
      screen: screen,
      node: node,
      actionKey: 'primary',
      dispatcher: dispatcher,
    );

    expect(dispatcher.last, isNotNull);
    expect(dispatcher.last!.type, 'navigate');
  });

  testWidgets(
      'tryDispatchComponentAction returns failure when actionKey missing', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();
    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);

    const screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 's',
      documentType: 'screen',
      product: 'p',
      service: null,
      themeId: 't',
      themeMode: null,
      root: ComponentNode(
        type: 'X',
        props: {},
        slots: {},
        actions: {},
        bind: null,
        visibleWhen: null,
      ),
      actions: {},
    );

    const node = ComponentNode(
      type: 'PrimaryActionBar',
      props: {},
      slots: {},
      actions: {},
      bind: null,
      visibleWhen: null,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox(key: Key('home')))),
    );

    final context = tester.element(find.byKey(const Key('home')));

    final result = await tryDispatchComponentAction(
      context: context,
      screen: screen,
      node: node,
      actionKey: 'primary',
      dispatcher: dispatcher,
      diagnostics: diagnostics,
    );

    expect(result.isOk, isFalse);
    expect(result.failure, isA<MissingComponentActionKeyFailure>());
    expect(dispatcher.last, isNull);

    expect(
      sink.events
          .where((e) => e.eventName == 'runtime.action.missing_action_key'),
      isNotEmpty,
    );
  });

  testWidgets(
      'tryDispatchComponentAction returns failure when actionId unknown', (
    tester,
  ) async {
    final dispatcher = _RecordingDispatcher();
    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(sink: sink);

    const screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 's',
      documentType: 'screen',
      product: 'p',
      service: null,
      themeId: 't',
      themeMode: null,
      root: ComponentNode(
        type: 'X',
        props: {},
        slots: {},
        actions: {},
        bind: null,
        visibleWhen: null,
      ),
      actions: {},
    );

    const node = ComponentNode(
      type: 'PrimaryActionBar',
      props: {},
      slots: {},
      actions: {'primary': 'missing_action_id'},
      bind: null,
      visibleWhen: null,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox(key: Key('home')))),
    );

    final context = tester.element(find.byKey(const Key('home')));

    final result = await tryDispatchComponentAction(
      context: context,
      screen: screen,
      node: node,
      actionKey: 'primary',
      dispatcher: dispatcher,
      diagnostics: diagnostics,
    );

    expect(result.isOk, isFalse);
    expect(result.failure, isA<UnknownScreenActionIdFailure>());
    expect(dispatcher.last, isNull);

    expect(
      sink.events
          .where((e) => e.eventName == 'runtime.action.unknown_action_id'),
      isNotEmpty,
    );
  });
}
