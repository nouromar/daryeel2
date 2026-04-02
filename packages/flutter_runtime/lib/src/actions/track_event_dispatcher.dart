import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import 'action_dispatcher.dart';
import 'action_policy.dart';

abstract class TrackEventHandler {
  const TrackEventHandler();

  Future<void> trackEvent(
    String eventName, {
    Map<String, Object?> properties = const <String, Object?>{},
  });
}

final class TrackEventSchemaActionDispatcher extends SchemaActionDispatcher {
  const TrackEventSchemaActionDispatcher({required this.trackEventHandler});

  final TrackEventHandler trackEventHandler;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    if (action.type != SchemaActionTypes.trackEvent) {
      throw UnsupportedError('Unsupported action type: ${action.type}');
    }

    final eventName = action.eventName;
    if (eventName == null || eventName.trim().isEmpty) {
      throw ArgumentError.value(
          action.eventName, 'action.eventName', 'Missing eventName');
    }

    final properties = _sanitizeProperties(action.eventProperties);
    await trackEventHandler.trackEvent(eventName, properties: properties);
  }

  Map<String, Object?> _sanitizeProperties(Map<String, Object?>? raw) {
    if (raw == null || raw.isEmpty) return const <String, Object?>{};

    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key.isEmpty) continue;
      final value = entry.value;

      if (value is String || value is num || value is bool) {
        out[key] = value;
      }
    }
    return out;
  }
}
