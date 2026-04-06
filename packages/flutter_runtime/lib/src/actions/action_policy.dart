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

  /// Mutates the current screen's `$state` store.
  ///
  /// This is only effective when a [SchemaStateScope] is present in the widget
  /// tree (installed by the app shell).
  static const String setState = 'set_state';

  /// Applies a list of safe mutation operations to `$state`.
  static const String patchState = 'patch_state';
}
