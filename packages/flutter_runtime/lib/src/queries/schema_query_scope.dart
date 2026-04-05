import 'package:flutter/widgets.dart';

import 'schema_query_store.dart';

final class SchemaQueryScope extends InheritedWidget {
  const SchemaQueryScope({
    required this.store,
    required super.child,
    super.key,
  });

  final SchemaQueryStore store;

  static SchemaQueryStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SchemaQueryScope>()
        ?.store;
  }

  static SchemaQueryStore of(BuildContext context) {
    final store = maybeOf(context);
    if (store == null) {
      throw StateError('SchemaQueryScope not found in widget tree');
    }
    return store;
  }

  @override
  bool updateShouldNotify(SchemaQueryScope oldWidget) =>
      store != oldWidget.store;
}
