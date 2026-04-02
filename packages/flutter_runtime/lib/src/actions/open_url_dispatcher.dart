import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../security/uri_policy.dart';
import 'action_dispatcher.dart';
import 'action_policy.dart';

abstract class OpenUrlHandler {
  const OpenUrlHandler();

  Future<void> openUrl(Uri uri);
}

/// Dispatcher for `open_url` actions.
///
/// Uses `action.route` as the raw URL string.
final class UrlSchemaActionDispatcher extends SchemaActionDispatcher {
  const UrlSchemaActionDispatcher({
    required this.openUrlHandler,
    this.uriPolicy = const UriPolicy.allowAll(),
  });

  final OpenUrlHandler openUrlHandler;
  final UriPolicy uriPolicy;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    if (action.type != SchemaActionTypes.openUrl) {
      throw UnsupportedError('Unsupported action type: ${action.type}');
    }

    final raw = action.route;
    if (raw == null || raw.trim().isEmpty) {
      throw ArgumentError.value(raw, 'action.route', 'Missing url');
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      throw ArgumentError.value(raw, 'action.route', 'Invalid url');
    }

    if (!uriPolicy.isAllowed(uri)) {
      throw UnsupportedError('URL not allowed by policy');
    }

    await openUrlHandler.openUrl(uri);
  }
}
