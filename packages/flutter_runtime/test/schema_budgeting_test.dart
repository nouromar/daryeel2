import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _screenDoc({
  required List<Object?> body,
  Map<String, Object?>? extraRootProps,
}) {
  return <String, Object?>{
    'schemaVersion': '1.0',
    'id': 'budget_test',
    'documentType': 'screen',
    'product': 'customer_app',
    'themeId': 'customer-default',
    'themeMode': 'light',
    'root': <String, Object?>{
      'type': 'ScreenTemplate',
      if (extraRootProps != null && extraRootProps.isNotEmpty)
        'props': extraRootProps,
      'slots': <String, Object?>{
        'body': body,
      },
    },
    'actions': const <String, Object?>{},
  };
}

Map<String, Object?> _infoCardNode(String title) {
  return <String, Object?>{
    'type': 'InfoCard',
    'props': <String, Object?>{
      'title': title,
    },
  };
}

void main() {
  test('parseScreenSchemaWithDiagnostics rejects oversized JSON (no throw)',
      () {
    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: sink,
      config: const DiagnosticsConfig(enableDebug: true),
    );

    final doc = _screenDoc(
      body: const <Object?>[],
      extraRootProps: <String, Object?>{
        'debugBlob': 'x' * 200,
      },
    );

    final result = parseScreenSchemaWithDiagnostics(
      doc,
      diagnostics: diagnostics,
      diagnosticsContext: const <String, Object?>{'test': true},
      maxJsonBytes: 80,
      maxNodes: 5000,
    );

    expect(result.value, isNull);
    expect(result.errors, isNotEmpty);
    expect(result.errors.first.message, contains('Exceeded maxJsonBytes=80'));

    expect(sink.events, isNotEmpty);
    expect(sink.events.first.eventName, 'runtime.schema.budget_exceeded');
    expect(sink.events.first.payload['budgetName'], 'max_json_bytes');
  });

  test('parseScreenSchemaWithDiagnostics rejects node-count budget (no throw)',
      () {
    final sink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: sink,
      config: const DiagnosticsConfig(enableDebug: true),
    );

    final doc = _screenDoc(
      body: <Object?>[
        _infoCardNode('A'),
        _infoCardNode('B'),
        _infoCardNode('C'),
        _infoCardNode('D'),
      ],
    );

    final result = parseScreenSchemaWithDiagnostics(
      doc,
      diagnostics: diagnostics,
      diagnosticsContext: const <String, Object?>{'test': true},
      maxJsonBytes: 1024 * 1024,
      maxNodes: 3,
    );

    expect(result.value, isNull);
    expect(result.errors, isNotEmpty);
    expect(result.errors.first.message, contains('Exceeded maxNodes=3'));

    expect(sink.events, isNotEmpty);
    expect(sink.events.first.eventName, 'runtime.schema.budget_exceeded');
    expect(sink.events.first.payload['budgetName'], 'max_nodes');
    expect(sink.events.first.payload['limit'], 3);
  });
}
