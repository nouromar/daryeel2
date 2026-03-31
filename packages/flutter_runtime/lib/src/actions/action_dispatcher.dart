import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

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
        Navigator.of(context).pushNamed(route);
        return;
      default:
        throw UnsupportedError('Unsupported action type: ${action.type}');
    }
  }
}
