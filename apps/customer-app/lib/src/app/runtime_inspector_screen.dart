import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

class RuntimeInspectorScreen extends StatelessWidget {
  const RuntimeInspectorScreen({
    required this.configSnapshotId,
    required this.schemaDocId,
    required this.schemaSource,
    required this.themeDocId,
    required this.themeSource,
    required this.diagnostics,
    this.maxEvents = 50,
    super.key,
  });

  final String? configSnapshotId;
  final String? schemaDocId;
  final String schemaSource;

  final String? themeDocId;
  final String themeSource;

  final List<DiagnosticEvent> diagnostics;
  final int maxEvents;

  @override
  Widget build(BuildContext context) {
    final effectiveMaxEvents = maxEvents <= 0 ? 0 : maxEvents;
    final events = effectiveMaxEvents == 0
        ? const <DiagnosticEvent>[]
        : (diagnostics.length <= effectiveMaxEvents
              ? diagnostics
              : diagnostics.sublist(diagnostics.length - effectiveMaxEvents));

    return Scaffold(
      appBar: AppBar(title: const Text('Runtime Inspector')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Config snapshot', configSnapshotId ?? '<none>'),
            _kv('Schema docId', schemaDocId ?? '<none>'),
            _kv('Schema source', schemaSource),
            _kv('Theme docId', themeDocId ?? '<none>'),
            _kv('Theme source', themeSource),
            const SizedBox(height: 12),
            Text(
              'Diagnostics (last ${events.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: events.isEmpty
                  ? const Center(child: Text('No diagnostics yet'))
                  : ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 16),
                      itemBuilder: (context, index) {
                        final e = events[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.eventName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'severity=${e.severity.name} kind=${e.kind.name}',
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
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
