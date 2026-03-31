import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import 'action_dispatcher.dart';
import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/runtime_diagnostics.dart';

sealed class ComponentActionDispatchFailure {
  const ComponentActionDispatchFailure();

  String get message;
}

final class MissingComponentActionKeyFailure
    extends ComponentActionDispatchFailure {
  const MissingComponentActionKeyFailure({required this.actionKey});

  final String actionKey;

  @override
  String get message => 'Missing component action for actionKey: $actionKey';
}

final class UnknownScreenActionIdFailure
    extends ComponentActionDispatchFailure {
  const UnknownScreenActionIdFailure({required this.actionId});

  final String actionId;

  @override
  String get message => 'Unknown action id: $actionId';
}

final class ActionDispatcherFailure extends ComponentActionDispatchFailure {
  const ActionDispatcherFailure({required this.error});

  final Object error;

  @override
  String get message => 'Action dispatch failed: $error';
}

class ComponentActionDispatchResult {
  const ComponentActionDispatchResult._({this.failure});

  const ComponentActionDispatchResult.ok() : this._();

  const ComponentActionDispatchResult.failed(
      ComponentActionDispatchFailure failure)
      : this._(failure: failure);

  final ComponentActionDispatchFailure? failure;

  bool get isOk => failure == null;
}

ActionDefinition? resolveComponentAction({
  required ScreenSchema screen,
  required ComponentNode node,
  required String actionKey,
}) {
  final actionId = node.actions[actionKey];
  if (actionId == null || actionId.isEmpty) return null;
  return screen.actions[actionId];
}

Future<void> dispatchComponentAction({
  required BuildContext context,
  required ScreenSchema screen,
  required ComponentNode node,
  required String actionKey,
  required SchemaActionDispatcher dispatcher,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) async {
  final result = await tryDispatchComponentAction(
    context: context,
    screen: screen,
    node: node,
    actionKey: actionKey,
    dispatcher: dispatcher,
    diagnostics: diagnostics,
    diagnosticsContext: diagnosticsContext,
  );

  final failure = result.failure;
  if (failure != null) {
    throw StateError(failure.message);
  }
}

Future<ComponentActionDispatchResult> tryDispatchComponentAction({
  required BuildContext context,
  required ScreenSchema screen,
  required ComponentNode node,
  required String actionKey,
  required SchemaActionDispatcher dispatcher,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) async {
  final actionId = node.actions[actionKey];
  if (actionId == null || actionId.isEmpty) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.action.missing_action_key',
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.action.missing_action_key:${node.type}:$actionKey',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'nodeType': node.type,
          'actionKey': actionKey,
        },
      ),
    );
    return ComponentActionDispatchResult.failed(
      MissingComponentActionKeyFailure(actionKey: actionKey),
    );
  }

  final action = screen.actions[actionId];
  if (action == null) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.action.unknown_action_id',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint: 'runtime.action.unknown_action_id:${node.type}:$actionId',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'nodeType': node.type,
          'actionKey': actionKey,
          'actionId': actionId,
        },
      ),
    );
    return ComponentActionDispatchResult.failed(
      UnknownScreenActionIdFailure(actionId: actionId),
    );
  }

  try {
    await dispatcher.dispatch(context, action);
    return const ComponentActionDispatchResult.ok();
  } catch (error) {
    diagnostics?.emit(
      DiagnosticEvent(
        eventName: 'runtime.action.dispatch_failed',
        severity: DiagnosticSeverity.error,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            'runtime.action.dispatch_failed:${action.type}:${node.type}:$actionId',
        context: diagnosticsContext,
        payload: <String, Object?>{
          'nodeType': node.type,
          'actionKey': actionKey,
          'actionId': actionId,
          'actionType': action.type,
          if (action.route != null) 'routeName': action.route,
          'errorType': error.runtimeType.toString(),
        },
      ),
    );
    return ComponentActionDispatchResult.failed(
      ActionDispatcherFailure(error: error),
    );
  }
}
