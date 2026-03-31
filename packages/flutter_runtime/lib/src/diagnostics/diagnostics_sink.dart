import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'diagnostic_event.dart';

abstract class DiagnosticsSink {
  const DiagnosticsSink();

  void handle(DiagnosticEvent event);
}

class MultiDiagnosticsSink extends DiagnosticsSink {
  const MultiDiagnosticsSink(this.sinks);

  final List<DiagnosticsSink> sinks;

  @override
  void handle(DiagnosticEvent event) {
    for (final sink in sinks) {
      sink.handle(event);
    }
  }
}

class NoopDiagnosticsSink extends DiagnosticsSink {
  const NoopDiagnosticsSink();

  @override
  void handle(DiagnosticEvent event) {}
}

class DebugPrintDiagnosticsSink extends DiagnosticsSink {
  const DebugPrintDiagnosticsSink({this.includePayload = false});

  final bool includePayload;

  @override
  void handle(DiagnosticEvent event) {
    final base = <String, Object?>{
      'eventSchemaVersion': event.eventSchemaVersion,
      'eventName': event.eventName,
      'severity': event.severity.name,
      'kind': event.kind.name,
      'timestamp': event.timestamp.toIso8601String(),
      'fingerprint': event.fingerprint,
      'context': event.context,
      if (includePayload) 'payload': event.payload,
    };
    debugPrint(jsonEncode(base));
  }
}

class InMemoryDiagnosticsSink extends DiagnosticsSink {
  InMemoryDiagnosticsSink({int maxEvents = 200})
      : assert(maxEvents > 0),
        _maxEvents = maxEvents;

  final int _maxEvents;
  final List<DiagnosticEvent> _events = <DiagnosticEvent>[];

  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  @override
  void handle(DiagnosticEvent event) {
    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
  }

  void clear() => _events.clear();
}
