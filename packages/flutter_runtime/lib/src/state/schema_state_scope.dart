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
  SchemaStateStore? _localStore;

  @override
  void didUpdateWidget(covariant SchemaStateScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!mapEquals(oldWidget.defaults, widget.defaults)) {
      final store = SchemaStateScope.maybeOf(context) ?? _localStore;
      store?.applyDefaults(widget.defaults);
    }
  }

  @override
  void dispose() {
    _localStore?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = SchemaStateScope.maybeOf(context);
    if (existing != null) {
      existing.applyDefaults(widget.defaults);
      return widget.child;
    }

    final store = _localStore ??= SchemaStateStore(initial: widget.defaults);
    return SchemaStateScope(store: store, child: widget.child);
  }
}
