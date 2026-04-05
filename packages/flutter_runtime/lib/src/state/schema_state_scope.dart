import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'schema_state_store.dart';

final class SchemaStateScope extends InheritedWidget {
  const SchemaStateScope({
    required this.store,
    required super.child,
    super.key,
  });

  final SchemaStateStore store;

  static SchemaStateStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SchemaStateScope>()
        ?.store;
  }

  static SchemaStateStore of(BuildContext context) {
    final store = maybeOf(context);
    if (store == null) {
      throw StateError('SchemaStateScope not found in widget tree');
    }
    return store;
  }

  @override
  bool updateShouldNotify(SchemaStateScope oldWidget) =>
      store != oldWidget.store;
}

/// Holds a [SchemaStateStore] for a screen subtree.
///
/// This ensures the store is created once and survives rebuilds.
class SchemaStateScopeHost extends StatefulWidget {
  const SchemaStateScopeHost({
    required this.child,
    this.defaults,
    super.key,
  });

  final Widget child;
  final Map<String, Object?>? defaults;

  @override
  State<SchemaStateScopeHost> createState() => _SchemaStateScopeHostState();
}

class _SchemaStateScopeHostState extends State<SchemaStateScopeHost> {
  late final SchemaStateStore _store =
      SchemaStateStore(initial: widget.defaults);

  @override
  void didUpdateWidget(covariant SchemaStateScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!mapEquals(oldWidget.defaults, widget.defaults)) {
      _store.applyDefaults(widget.defaults);
    }
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SchemaStateScope(store: _store, child: widget.child);
  }
}
