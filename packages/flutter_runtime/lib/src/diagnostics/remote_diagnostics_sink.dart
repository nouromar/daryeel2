import 'dart:async';
import 'dart:convert';

import 'diagnostic_event.dart';
import 'diagnostics_sink.dart';

abstract class RemoteDiagnosticsTransport {
  const RemoteDiagnosticsTransport();

  Future<void> send({
    required Uri endpoint,
    required Map<String, Object?> body,
    Map<String, String>? headers,
  });
}

/// A best-effort remote diagnostics sink.
///
/// - Sends events in small batches.
/// - Drops events if the in-memory queue is full.
/// - Does not throw (telemetry must not crash the app).
class RemoteDiagnosticsSink extends DiagnosticsSink {
  RemoteDiagnosticsSink({
    required this.endpoint,
    required this.transport,
    this.headersProvider,
    this.maxQueuedEvents = 200,
    this.flushMaxBatchSize = 25,
  })  : assert(maxQueuedEvents > 0),
        assert(flushMaxBatchSize > 0);

  final Uri endpoint;
  final RemoteDiagnosticsTransport transport;

  /// Called right before a flush.
  /// Useful for adding correlation headers (x-request-id, x-daryeel-session-id).
  final Map<String, String> Function()? headersProvider;

  final int maxQueuedEvents;
  final int flushMaxBatchSize;

  final List<DiagnosticEvent> _queue = <DiagnosticEvent>[];
  bool _flushScheduled = false;

  int droppedEventCount = 0;

  @override
  void handle(DiagnosticEvent event) {
    if (_queue.length >= maxQueuedEvents) {
      droppedEventCount++;
      return;
    }

    _queue.add(event);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;

    scheduleMicrotask(() {
      _flushScheduled = false;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_queue.isEmpty) return;

    final batchSize =
        _queue.length < flushMaxBatchSize ? _queue.length : flushMaxBatchSize;

    final batch = _queue.sublist(0, batchSize);
    _queue.removeRange(0, batchSize);

    final body = <String, Object?>{
      'events': batch.map(_toJson).toList(growable: false),
      if (droppedEventCount > 0) 'droppedEventCount': droppedEventCount,
    };

    try {
      await transport.send(
        endpoint: endpoint,
        body: body,
        headers: headersProvider?.call(),
      );
    } catch (_) {
      // Best effort: swallow.
      // We intentionally do not re-queue to avoid unbounded retries.
    }

    if (_queue.isNotEmpty) {
      _scheduleFlush();
    }
  }

  Map<String, Object?> _toJson(DiagnosticEvent event) {
    return <String, Object?>{
      'eventSchemaVersion': event.eventSchemaVersion,
      'kind': event.kind.name,
      'eventName': event.eventName,
      'severity': event.severity.name,
      'timestamp': event.timestamp.toIso8601String(),
      'fingerprint': event.fingerprint,
      'context': event.context,
      'payload': event.payload,
    };
  }
}

class DebugHttpBodyFormatter {
  const DebugHttpBodyFormatter();

  String format(Map<String, Object?> body) => jsonEncode(body);
}
