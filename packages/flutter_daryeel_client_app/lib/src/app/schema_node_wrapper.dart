import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

SchemaNodeWrapperBuilder buildVisibleWhenWrapperBuilder({
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  return (node, buildChild) {
    final visibleWhen = node.visibleWhen;
    if (visibleWhen == null || visibleWhen.isEmpty) return buildChild();

    return _VisibleWhenWrapper(
      visibleWhen: visibleWhen,
      visibility: visibility,
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
      nodeType: node.type,
      buildChild: buildChild,
    );
  };
}

final class _VisibleWhenWrapper extends StatelessWidget {
  const _VisibleWhenWrapper({
    required this.visibleWhen,
    required this.visibility,
    required this.buildChild,
    required this.nodeType,
    this.diagnostics,
    this.diagnosticsContext = const <String, Object?>{},
  });

  final Map<String, Object?> visibleWhen;
  final SchemaVisibilityContext visibility;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;
  final String? nodeType;
  final Widget Function() buildChild;

  bool _isVisible(BuildContext context) {
    return evaluateVisibleWhen(
      visibleWhen,
      visibility,
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
      nodeType: nodeType,
      buildContext: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final listensToExpr = visibleWhen.containsKey('expr');
    final store = listensToExpr ? SchemaStateScope.maybeOf(context) : null;

    Widget evaluate(BuildContext context) {
      return _isVisible(context) ? buildChild() : const SizedBox.shrink();
    }

    if (store == null) return evaluate(context);

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => evaluate(context),
    );
  }
}
