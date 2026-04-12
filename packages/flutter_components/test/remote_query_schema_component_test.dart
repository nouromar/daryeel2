import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _NoopActionDispatcher extends SchemaActionDispatcher {
  const _NoopActionDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {}
}

class _QueuedResponseClient extends http.BaseClient {
  _QueuedResponseClient(this._responses);

  final List<http.Response> _responses;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    final response = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

SchemaComponentContext _testComponentContext() {
  return SchemaComponentContext(
    screen: ScreenSchema(
      schemaVersion: '1',
      id: 'test',
      documentType: 'screen',
      product: 'test',
      service: null,
      themeId: 'test',
      themeMode: null,
      root: const ComponentNode(
        type: 'ScreenTemplate',
        props: <String, Object?>{},
        slots: <String, List<SchemaNode>>{},
        actions: <String, String>{},
        bind: null,
        visibleWhen: null,
      ),
      actions: const <String, ActionDefinition>{},
    ),
    actionDispatcher: const _NoopActionDispatcher(),
    visibility: const SchemaVisibilityContext(),
  );
}

ComponentNode _component(
  String type, {
  Map<String, Object?> props = const <String, Object?>{},
  Map<String, List<SchemaNode>> slots = const <String, List<SchemaNode>>{},
}) {
  return ComponentNode(
    type: type,
    props: props,
    slots: slots,
    actions: const <String, String>{},
    bind: null,
    visibleWhen: null,
  );
}

void main() {
  testWidgets(
      'RemoteQuery retries the same signature after an error on rebuild',
      (tester) async {
    final registry = SchemaWidgetRegistry();
    registerCoreSchemaComponents(
      registry: registry,
      context: _testComponentContext(),
    );

    registry.register('ProbeLoading', (node, componentRegistry) {
      return const Text('loading');
    });
    registry.register('ProbeError', (node, componentRegistry) {
      return const Text('error');
    });
    registry.register('ProbeSuccess', (node, componentRegistry) {
      return const Text('success');
    });

    final root = _component(
      'RemoteQuery',
      props: const <String, Object?>{
        'key': 'customer.requests',
        'path': '/v1/requests',
      },
      slots: <String, List<SchemaNode>>{
        'loading': <SchemaNode>[_component('ProbeLoading')],
        'error': <SchemaNode>[_component('ProbeError')],
        'child': <SchemaNode>[_component('ProbeSuccess')],
      },
    );

    final client = _QueuedResponseClient(<http.Response>[
      http.Response('not found', 404),
      http.Response(jsonEncode(<String, Object?>{'ok': true}), 200),
    ]);
    final queryStore = SchemaQueryStore(
      apiBaseUrl: 'http://example.com',
      client: client,
    );

    var generation = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() => generation += 1),
                    child: Text('rebuild-$generation'),
                  ),
                  Expanded(
                    child: SchemaQueryScope(
                      store: queryStore,
                      child: SchemaRenderer(
                        rootNode: root,
                        registry: registry,
                      ).render(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(client.requestCount, 1);
    expect(find.text('error'), findsOneWidget);

    await tester.tap(find.text('rebuild-0'));
    await tester.pump();
    await tester.pump();

    expect(client.requestCount, 2);
    expect(find.text('success'), findsOneWidget);
  });
}
