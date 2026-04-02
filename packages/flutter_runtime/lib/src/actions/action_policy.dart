import '../security/uri_policy.dart';

/// Security policy for schema-driven actions.
///
/// - `allowedActionTypes == null` means allow all (legacy/default).
/// - Prefer a restrictive allowlist in apps.
class SchemaActionPolicy {
  const SchemaActionPolicy({
    this.allowedActionTypes,
    this.openUrlPolicy = const UriPolicy.allowAll(),
  });

  const SchemaActionPolicy.allowAll()
      : allowedActionTypes = null,
        openUrlPolicy = const UriPolicy.allowAll();

  final Set<String>? allowedActionTypes;
  final UriPolicy openUrlPolicy;

  bool isAllowedActionType(String actionType) {
    final allow = allowedActionTypes;
    if (allow == null) return true;
    return allow.contains(actionType);
  }
}

final class SchemaActionTypes {
  SchemaActionTypes._();

  static const String navigate = 'navigate';
  static const String openUrl = 'open_url';
  static const String submitForm = 'submit_form';
  static const String trackEvent = 'track_event';
}
