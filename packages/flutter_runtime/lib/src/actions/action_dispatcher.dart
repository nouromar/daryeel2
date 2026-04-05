import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../state/schema_state_scope.dart';

abstract class SchemaActionDispatcher {
  const SchemaActionDispatcher();

  Future<void> dispatch(BuildContext context, ActionDefinition action);
}

class NavigatorSchemaActionDispatcher extends SchemaActionDispatcher {
  const NavigatorSchemaActionDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    switch (action.type) {
      case 'navigate':
        final route = action.route;
        if (route == null || route.isEmpty) {
          throw ArgumentError.value(
              action.route, 'action.route', 'Missing route');
        }
        Navigator.of(context).pushNamed(route, arguments: action.value);
        return;
      case 'set_state':
        final store = SchemaStateScope.maybeOf(context);
        if (store == null) {
          throw StateError('SchemaStateScope not found in widget tree');
        }

        final raw = action.value;
        if (raw is Map) {
          final patch = <String, Object?>{};
          for (final entry in raw.entries) {
            final k = entry.key;
            if (k is! String) continue;
            final key = k.trim();
            if (key.isEmpty) continue;
            patch[key] = entry.value;
          }
          store.setValues(patch);
          return;
        }

        if (raw is List && raw.length == 2 && raw.first is String) {
          final key = (raw.first as String).trim();
          if (key.isEmpty) return;
          store.setValue(key, raw[1]);
          return;
        }

        // Unknown payload shape: fail closed (no-op) rather than crashing.
        return;
      default:
        throw UnsupportedError('Unsupported action type: ${action.type}');
    }
  }
}
