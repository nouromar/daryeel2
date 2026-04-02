/// Stable event names and reason codes for schema-driven action security.
///
/// Keep payload values low-cardinality and avoid logging user data.

enum ActionPolicyReason {
  disallowedActionType,
  invalidParams,
  blockedUrl,
  dispatcherUnsupported,
  dispatcherException,
}

extension ActionPolicyReasonWire on ActionPolicyReason {
  String get wireValue => switch (this) {
        ActionPolicyReason.disallowedActionType => 'disallowed_action_type',
        ActionPolicyReason.invalidParams => 'invalid_params',
        ActionPolicyReason.blockedUrl => 'blocked_url',
        ActionPolicyReason.dispatcherUnsupported => 'dispatcher_unsupported',
        ActionPolicyReason.dispatcherException => 'dispatcher_exception',
      };
}

final class ActionEventNames {
  ActionEventNames._();

  static const String executed = 'runtime.action.executed';
  static const String policyBlocked = 'runtime.action.policy_blocked';
  static const String validationFailed = 'runtime.action.validation_failed';
  static const String noopUnsupported = 'runtime.action.noop_unsupported';
  static const String dispatchFailed = 'runtime.action.dispatch_failed';
}

final class ActionPayloadKeys {
  ActionPayloadKeys._();

  static const String actionType = 'actionType';
  static const String reasonCode = 'reasonCode';
  static const String message = 'message';

  static const String routeName = 'routeName';
  static const String urlHost = 'urlHost';
  static const String urlScheme = 'urlScheme';
  static const String formId = 'formId';
  static const String eventName = 'eventName';

  static const String errorType = 'errorType';
}
