import 'package:flutter/widgets.dart';

/// Exposes route arguments to schema-driven UI.
///
/// This is intentionally bounded: it carries a single JSON-like map passed via
/// `Navigator.pushNamed(..., arguments: ...)`.
final class SchemaRouteScope extends InheritedWidget {
  const SchemaRouteScope({
    required this.params,
    required super.child,
    super.key,
  });

  /// Route params/arguments passed in from navigation.
  final Map<String, Object?> params;

  static Map<String, Object?>? maybeParamsOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SchemaRouteScope>()
        ?.params;
  }

  static Map<String, Object?> paramsOf(BuildContext context) {
    final params = maybeParamsOf(context);
    if (params == null) {
      throw StateError('SchemaRouteScope not found in widget tree');
    }
    return params;
  }

  @override
  bool updateShouldNotify(SchemaRouteScope oldWidget) =>
      params != oldWidget.params;
}
