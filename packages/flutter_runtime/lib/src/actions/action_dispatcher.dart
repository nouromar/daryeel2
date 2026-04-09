import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../bindings/schema_expression_engine.dart';
import '../bindings/schema_interpolation.dart';
import '../security/security_budgets.dart';
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
        if (raw is! Map) return;

        // Canonical shape: {"path": "...", "value": ...}
        final pathRaw = raw['path'];
        if (pathRaw is! String || pathRaw.trim().isEmpty) return;

        final resolvedPath = interpolateSchemaString(pathRaw, context);
        final path = resolvedPath.trim();
        if (path.isEmpty) return;

        final value = evaluateSchemaValue(raw['value'], context);
        store.setValue(path, value);
        return;

      case 'patch_state':
        final store = SchemaStateScope.maybeOf(context);
        if (store == null) return;

        final raw = action.value;
        if (raw is! Map) return;
        final opsRaw = raw['ops'];
        if (opsRaw is! List) return;

        final maxOps = SecurityBudgets.maxStatePatchOpsPerAction;
        final opCount = opsRaw.length;
        final limit = opCount < maxOps ? opCount : maxOps;

        for (var i = 0; i < limit; i++) {
          final opRaw = opsRaw[i];
          if (opRaw is! Map) continue;

          final op = opRaw['op'];
          final pathRaw = opRaw['path'];
          if (op is! String || pathRaw is! String) continue;

          final resolvedPath = interpolateSchemaString(pathRaw, context);
          final path = resolvedPath.trim();
          if (path.isEmpty) continue;

          switch (op.trim().toLowerCase()) {
            case 'set':
              store.setValue(
                  path, evaluateSchemaValue(opRaw['value'], context));
              break;
            case 'remove':
              store.removeValue(path);
              break;
            case 'increment':
              final byValue = evaluateSchemaValue(opRaw['by'], context);
              final by = (byValue is num)
                  ? byValue
                  : (byValue is String ? num.tryParse(byValue.trim()) : null);
              if (by == null) break;
              store.incrementValue(path, by);
              break;
            case 'append':
              store.appendValue(
                  path, evaluateSchemaValue(opRaw['value'], context));
              break;
            default:
              // Unknown op: ignore.
              break;
          }
        }

        return;
      default:
        throw UnsupportedError('Unsupported action type: ${action.type}');
    }
  }
}
