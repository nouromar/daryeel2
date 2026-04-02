import 'package:customer_app/src/app/runtime_inspector_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RuntimeInspectorScreen renders required fields', (tester) async {
    final events = <DiagnosticEvent>[
      DiagnosticEvent(
        eventName: 'runtime.schema.ladder.source_used',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint: 'f1',
        context: const <String, Object?>{'test': true},
        payload: const <String, Object?>{'source': 'selector'},
      ),
      DiagnosticEvent(
        eventName: 'runtime.http_cache.corrupt_entry',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'f2',
        context: const <String, Object?>{'test': true},
        payload: const <String, Object?>{'cacheKey': 'k'},
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeInspectorScreen(
          configSnapshotId: 'snap-1',
          schemaDocId: 'doc-123',
          schemaSource: 'selector',
          themeDocId: null,
          themeSource: 'local',
          diagnostics: events,
        ),
      ),
    );

    expect(find.text('Config snapshot:'), findsOneWidget);
    expect(find.text('snap-1'), findsOneWidget);

    expect(find.text('Schema docId:'), findsOneWidget);
    expect(find.text('doc-123'), findsOneWidget);

    expect(find.text('Schema source:'), findsOneWidget);
    expect(find.text('selector'), findsOneWidget);

    expect(find.text('Theme docId:'), findsOneWidget);
    expect(find.text('<none>'), findsOneWidget);

    expect(find.text('Theme source:'), findsOneWidget);
    expect(find.text('local'), findsOneWidget);

    expect(find.text('runtime.schema.ladder.source_used'), findsOneWidget);
    expect(find.text('runtime.http_cache.corrupt_entry'), findsOneWidget);
  });
}
