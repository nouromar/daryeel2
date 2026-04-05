import 'package:flutter/widgets.dart';

import '../runtime/daryeel_runtime_session.dart';

class RuntimeSessionScope extends InheritedWidget {
  const RuntimeSessionScope({
    required this.session,
    required super.child,
    super.key,
  });

  final DaryeelRuntimeSession session;

  static DaryeelRuntimeSession of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RuntimeSessionScope>();
    if (scope == null) {
      throw StateError('RuntimeSessionScope not found in widget tree');
    }
    return scope.session;
  }

  @override
  bool updateShouldNotify(RuntimeSessionScope oldWidget) {
    return oldWidget.session != session;
  }
}
