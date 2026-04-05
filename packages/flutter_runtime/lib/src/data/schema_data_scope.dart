import 'package:flutter/widgets.dart';

/// Provides query results and item context to schema components.
///
/// This is intentionally simple and bounded: it carries plain decoded JSON
/// structures (`Map`, `List`, primitives) and offers no expression language.
final class SchemaDataScope extends InheritedWidget {
  const SchemaDataScope({
    required super.child,
    this.data,
    this.item,
    this.index,
    super.key,
  });

  final Object? data;
  final Object? item;
  final int? index;

  static SchemaDataScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SchemaDataScope>();
  }

  static SchemaDataScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw StateError('SchemaDataScope not found in widget tree');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(SchemaDataScope oldWidget) {
    return data != oldWidget.data ||
        item != oldWidget.item ||
        index != oldWidget.index;
  }
}

/// Reads a dotted path from decoded JSON-like values.
///
/// Supported:
/// - `a.b.c` for maps
/// - numeric segments like `0` to index lists
Object? readJsonPath(Object? root, String? path) {
  if (path == null) return null;
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;

  Object? current = root;
  for (final rawSegment in trimmed.split('.')) {
    final segment = rawSegment.trim();
    if (segment.isEmpty) return null;

    if (current is Map) {
      final map = current;
      current = map[segment];
      continue;
    }

    if (current is List) {
      final index = int.tryParse(segment);
      if (index == null) return null;
      if (index < 0 || index >= current.length) return null;
      current = current[index];
      continue;
    }

    return null;
  }

  return current;
}
