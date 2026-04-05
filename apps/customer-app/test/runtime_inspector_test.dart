import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
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
          schemaBaseUrl: '',
          configBaseUrl: '',
          apiBaseUrl: '',
          bootstrapVersion: 1,
          bootstrapProduct: 'customer_app',
          bootstrapConfigSnapshotId: 'snap-1',
          configSnapshotId: 'snap-1',
          schemaBundleId: 'customer_home',
          schemaBundleVersion: '1.0',
          schemaDocId: 'doc-123',
          schemaSource: 'selector',
          schemaDocument: const <String, Object?>{},
          parseErrors: const <SchemaParseError>[],
          refErrors: const <RefResolutionError>[],
          themeId: 'customer-default',
          themeMode: 'light',
          themeDocId: null,
          themeSource: 'local',
          diagnostics: events,
        ),
      ),
    );

    expect(find.text('Config snapshot:'), findsOneWidget);
    expect(find.text('snap-1'), findsNWidgets(2));

    expect(find.text('Schema bundle:'), findsOneWidget);
    expect(find.text('customer_home@1.0'), findsOneWidget);

    expect(find.text('Schema docId:'), findsOneWidget);
    expect(find.text('doc-123'), findsOneWidget);

    expect(find.text('Schema source:'), findsOneWidget);
    expect(find.text('selector'), findsOneWidget);

    // The inspector uses a ListView; some rows may not be built until scrolled
    // into view.
    await tester.fling(find.byType(ListView), const Offset(0, -600), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Theme docId:'), findsOneWidget);
    expect(find.text('<none>'), findsOneWidget);

    expect(find.text('Theme id:'), findsOneWidget);
    expect(find.text('customer-default'), findsOneWidget);

    expect(find.text('Theme mode:'), findsOneWidget);
    expect(find.text('light'), findsOneWidget);

    expect(find.text('Theme source:'), findsOneWidget);
    expect(find.text('local'), findsOneWidget);

    expect(
      find.text('runtime.schema.ladder.source_used', skipOffstage: false),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.text('runtime.http_cache.corrupt_entry', skipOffstage: false),
      findsAtLeastNWidgets(1),
    );
  });
}
