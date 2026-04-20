import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingDispatcher extends SchemaActionDispatcher {
  _RecordingDispatcher();

  int dispatchCount = 0;
  ActionDefinition? lastAction;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    dispatchCount++;
    lastAction = action;
  }
}

void main() {
  testWidgets('TapArea dispatches tap action and enforces min size',
      (tester) async {
    final dispatcher = _RecordingDispatcher();
    final registry = SchemaWidgetRegistry();

    const tapNode = ComponentNode(
      type: 'TapArea',
      props: <String, Object?>{},
      slots: <String, List<SchemaNode>>{
        'child': <SchemaNode>[
          ComponentNode(
            type: 'Text',
            props: <String, Object?>{'text': 'Tap me'},
            slots: <String, List<SchemaNode>>{},
            actions: <String, String>{},
            bind: null,
            visibleWhen: null,
          ),
        ],
      },
      actions: <String, String>{'tap': 'tap_action'},
      bind: null,
      visibleWhen: null,
    );

    const screen = ScreenSchema(
      schemaVersion: '1.0',
      id: 'test_screen',
      documentType: 'screen',
      product: 'test',
      service: null,
      themeId: 'test-theme',
      themeMode: null,
      root: tapNode,
      actions: <String, ActionDefinition>{
        'tap_action': ActionDefinition(type: 'test'),
      },
    );

    final context = SchemaComponentContext(
      screen: screen,
      actionDispatcher: dispatcher,
      visibility: const SchemaVisibilityContext(),
      diagnostics: null,
      diagnosticsContext: const <String, Object?>{},
    );

    registerCoreSchemaComponents(registry: registry, context: context);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaRenderer(rootNode: screen.root, registry: registry)
              .render(),
        ),
      ),
    );

    expect(dispatcher.dispatchCount, 0);

    await tester.tap(find.text('Tap me'));
    await tester.pump();

    expect(dispatcher.dispatchCount, 1);
    expect(dispatcher.lastAction?.type, 'test');

    final size = tester.getSize(find.byType(InkResponse));
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });
}
