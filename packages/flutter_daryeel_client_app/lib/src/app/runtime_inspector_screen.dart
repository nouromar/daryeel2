import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

class RuntimeInspectorScreen extends StatelessWidget {
  const RuntimeInspectorScreen({
    required this.schemaBaseUrl,
    required this.configBaseUrl,
    required this.apiBaseUrl,
    required this.bootstrapVersion,
    required this.bootstrapProduct,
    required this.bootstrapConfigSnapshotId,
    required this.configSnapshotId,
    required this.schemaBundleId,
    required this.schemaBundleVersion,
    required this.schemaDocId,
    required this.schemaSource,
    required this.schemaDocument,
    required this.parseErrors,
    required this.refErrors,
    required this.themeId,
    required this.themeMode,
    required this.themeDocId,
    required this.themeSource,
    required this.diagnostics,
    this.maxEvents = 50,
    super.key,
  });

  final String schemaBaseUrl;
  final String configBaseUrl;
  final String apiBaseUrl;

  final int? bootstrapVersion;
  final String? bootstrapProduct;
  final String? bootstrapConfigSnapshotId;

  final String? configSnapshotId;
  final String schemaBundleId;
  final String schemaBundleVersion;
  final String? schemaDocId;
  final String schemaSource;
  final Map<String, Object?> schemaDocument;
  final List<SchemaParseError> parseErrors;
  final List<RefResolutionError> refErrors;

  final String? themeId;
  final String? themeMode;
  final String? themeDocId;
  final String themeSource;

  final List<DiagnosticEvent> diagnostics;
  final int maxEvents;

  @override
  Widget build(BuildContext context) {
    String prettySchemaDocument() {
      try {
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(schemaDocument);
      } catch (e) {
        return '<failed to encode schemaDocument: $e>';
      }
    }

    final effectiveMaxEvents = maxEvents <= 0 ? 0 : maxEvents;
    final events = effectiveMaxEvents == 0
        ? const <DiagnosticEvent>[]
        : (diagnostics.length <= effectiveMaxEvents
              ? diagnostics
              : diagnostics.sublist(diagnostics.length - effectiveMaxEvents));

    final children = <Widget>[
      _kv('Schema baseUrl', schemaBaseUrl.isEmpty ? '<none>' : schemaBaseUrl),
      _kv('Config baseUrl', configBaseUrl.isEmpty ? '<none>' : configBaseUrl),
      _kv('API baseUrl', apiBaseUrl.isEmpty ? '<none>' : apiBaseUrl),
      _kv('Bootstrap product', bootstrapProduct ?? '<none>'),
      _kv(
        'Bootstrap version',
        bootstrapVersion == null ? '<none>' : '${bootstrapVersion!}',
      ),
      _kv('Bootstrap snapshot', bootstrapConfigSnapshotId ?? '<none>'),
      _kv('Config snapshot', configSnapshotId ?? '<none>'),
      _kv('Schema bundle', '$schemaBundleId@$schemaBundleVersion'),
      _kv('Schema docId', schemaDocId ?? '<none>'),
      _kv('Schema source', schemaSource),
      _kv('Parse errors', '${parseErrors.length}'),
      _kv('Ref errors', '${refErrors.length}'),
      _kv('Theme id', themeId ?? '<none>'),
      _kv('Theme mode', themeMode ?? '<none>'),
      _kv('Theme docId', themeDocId ?? '<none>'),
      _kv('Theme source', themeSource),
      const SizedBox(height: 12),
      Text(
        'Schema document (JSON)',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      SelectableText(prettySchemaDocument()),
      const SizedBox(height: 12),
      Text(
        'Diagnostics (last ${events.length})',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No diagnostics yet')),
        )
      else
        ...events.expand(
          (e) => <Widget>[
            Text(
              e.eventName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text('severity=${e.severity.name} kind=${e.kind.name}'),
            const Divider(height: 16),
          ],
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Runtime Inspector')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: children),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$key:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
