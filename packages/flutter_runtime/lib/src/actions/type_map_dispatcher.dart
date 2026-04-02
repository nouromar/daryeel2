import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import 'action_dispatcher.dart';

/// Dispatches actions based on `action.type`.
final class TypeMapSchemaActionDispatcher extends SchemaActionDispatcher {
  const TypeMapSchemaActionDispatcher({
    required this.dispatchersByType,
    this.fallback = const UnsupportedSchemaActionDispatcher(),
  });

  final Map<String, SchemaActionDispatcher> dispatchersByType;
  final SchemaActionDispatcher fallback;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    final dispatcher = dispatchersByType[action.type];
    return (dispatcher ?? fallback).dispatch(context, action);
  }
}

/// Fallback dispatcher that always fails for unknown/unimplemented action types.
final class UnsupportedSchemaActionDispatcher extends SchemaActionDispatcher {
  const UnsupportedSchemaActionDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    throw UnsupportedError('Unsupported action type: ${action.type}');
  }
}
