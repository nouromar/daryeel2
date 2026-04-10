import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerIfSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('If', (node, componentRegistry) {
    final exprRaw = (node.props['expr'] as String?)?.trim();
    final expr = (exprRaw == null || exprRaw.isEmpty) ? null : exprRaw;
    final valuePath = (node.props['valuePath'] as String?)?.trim();
    final opRaw = (node.props['op'] as String?)?.trim().toLowerCase();

    String? normalizeExpr(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith(r'${') && trimmed.endsWith('}')) {
        final inner = trimmed.substring(2, trimmed.length - 1).trim();
        return inner.isEmpty ? null : inner;
      }
      return trimmed;
    }

    final normalizedExpr = (expr == null) ? null : normalizeExpr(expr);

    const statePrefixDot = r'$state.';
    const statePrefixColon = r'$state:';
    final isStatePath = valuePath != null &&
        (valuePath.startsWith(statePrefixDot) ||
            valuePath.startsWith(statePrefixColon));
    final stateKey = isStatePath
        ? (valuePath.startsWith(statePrefixDot)
            ? valuePath.substring(statePrefixDot.length)
            : valuePath.substring(statePrefixColon.length))
        : null;

    final thenNodes = node.slots['then'];
    if (thenNodes == null || thenNodes.isEmpty) {
      return const UnknownSchemaWidget(componentName: 'If(missing-then-slot)');
    }

    final elseNodes = node.slots['else'];

    bool evaluate(Object? value) {
      final op = (opRaw == null || opRaw.isEmpty) ? 'isnotempty' : opRaw;

      return switch (op) {
        'isnull' => value == null,
        'isnotnull' => value != null,
        'isempty' => _isEmpty(value),
        'isnotempty' => !_isEmpty(value),
        'istrue' => value == true,
        'isfalse' => value == false,
        _ => throw ArgumentError('unknown op: $op'),
      };
    }

    Widget buildSlot(List<SchemaNode>? nodes) {
      final children = buildSchemaSlotWidgets(
        nodes,
        componentRegistry,
        context: context,
        applyVisibilityWhen: true,
      );

      if (children.isEmpty) return const SizedBox.shrink();
      if (children.length == 1) return children.single;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    Widget buildIf(BuildContext buildContext) {
      if (normalizedExpr != null) {
        try {
          final result = evaluateSchemaExpression(normalizedExpr, buildContext);
          final showThen = result == true;
          return showThen ? buildSlot(thenNodes) : buildSlot(elseNodes);
        } catch (_) {
          return const UnknownSchemaWidget(componentName: 'If(expr-error)');
        }
      }

      Object? value;
      if (isStatePath) {
        final key = (stateKey ?? '').trim();
        if (key.isNotEmpty) {
          value = SchemaStateScope.maybeOf(buildContext)?.getValue(key);
        }
      } else {
        final data = SchemaDataScope.maybeOf(buildContext)?.data;
        if (valuePath == null || valuePath.isEmpty) {
          value = data;
        } else {
          value = readJsonPath(data, valuePath);
        }
      }

      bool showThen;
      try {
        showThen = evaluate(value);
      } catch (_) {
        return const UnknownSchemaWidget(componentName: 'If(unknown-op)');
      }

      return showThen ? buildSlot(thenNodes) : buildSlot(elseNodes);
    }

    return Builder(
      builder: (buildContext) {
        final store = SchemaStateScope.maybeOf(buildContext);

        if (store == null) {
          if (isStatePath) {
            return const UnknownSchemaWidget(
                componentName: 'If(missing-state)');
          }
          return buildIf(buildContext);
        }

        final shouldListenToState = isStatePath || normalizedExpr != null;
        if (!shouldListenToState) {
          return buildIf(buildContext);
        }

        return AnimatedBuilder(
          animation: store,
          builder: (context, _) => buildIf(context),
        );
      },
    );
  });
}

bool _isEmpty(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is List) return value.isEmpty;
  if (value is Map) return value.isEmpty;
  return false;
}
