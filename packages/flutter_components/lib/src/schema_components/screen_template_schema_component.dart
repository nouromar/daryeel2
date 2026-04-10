import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/screen_template_widget.dart';
import 'schema_component_context.dart';
import 'schema_component_utils.dart';
import 'schema_node_wrapper.dart';

void registerScreenTemplateSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('ScreenTemplate', (node, componentRegistry) {
    final defaultsRaw = node.props['stateDefaults'];
    final stateDefaults = defaultsRaw is Map
        ? Map<String, Object?>.fromEntries(
            defaultsRaw.entries
                .where((e) => e.key is String)
                .map((e) => MapEntry(e.key as String, e.value)),
          )
        : null;

    final header = _buildSlot(
      node.slots['header'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
    );
    final body = _buildBodySlot(
      node.slots['body'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
    );
    final footer = _buildSlot(
      node.slots['footer'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
    );

    final headerGap = schemaAsDouble(node.props['headerGap']) ?? 8;
    final bodyScroll = _asBool(node.props['bodyScroll'], defaultValue: true);
    final bodyPadding = _parseEdgeInsets(
      node.props['bodyPadding'],
      fallback: const EdgeInsets.all(16),
    );
    final primaryScrollPadding = _parseEdgeInsets(
      node.props['primaryScrollPadding'],
      fallback: const EdgeInsets.symmetric(horizontal: 16),
    );
    final footerPadding = _parseEdgeInsets(
      node.props['footerPadding'],
      fallback: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );

    return SchemaStateScopeHost(
      defaults: stateDefaults,
      child: ScreenTemplateWidget(
        header: header,
        body: body,
        footer: footer,
        headerGap: headerGap,
        bodyScroll: bodyScroll,
        bodyPadding: bodyPadding,
        primaryScrollPadding: primaryScrollPadding,
        footerPadding: footerPadding,
      ),
    );
  });
}

bool _asBool(Object? raw, {required bool defaultValue}) {
  if (raw is bool) return raw;
  if (raw is String) {
    final v = raw.trim().toLowerCase();
    if (v == 'true') return true;
    if (v == 'false') return false;
  }
  return defaultValue;
}

EdgeInsets _parseEdgeInsets(Object? raw, {required EdgeInsets fallback}) {
  if (raw is! Map) return fallback;
  final props = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) continue;
    props[key] = entry.value;
  }

  double? read(String key) => schemaAsDouble(props[key]);

  const supportedKeys = <String>{
    'all',
    'horizontal',
    'vertical',
    'left',
    'top',
    'right',
    'bottom',
  };
  final sawSupportedKey = props.keys.any(supportedKeys.contains);
  if (!sawSupportedKey) return fallback;

  double left = 0;
  double top = 0;
  double right = 0;
  double bottom = 0;

  final all = read('all');
  if (all != null) {
    left = all;
    top = all;
    right = all;
    bottom = all;
  }

  final horizontal = read('horizontal');
  if (horizontal != null) {
    left = horizontal;
    right = horizontal;
  }

  final vertical = read('vertical');
  if (vertical != null) {
    top = vertical;
    bottom = vertical;
  }

  final l = read('left');
  if (l != null) left = l;
  final t = read('top');
  if (t != null) top = t;
  final r = read('right');
  if (r != null) right = r;
  final b = read('bottom');
  if (b != null) bottom = b;

  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

List<Widget> _buildSlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaComponentContext context,
  required bool applyVisibilityWhen,
}) {
  return buildSchemaSlotWidgets(
    children,
    registry,
    context: context,
    applyVisibilityWhen: applyVisibilityWhen,
  );
}

List<Widget> _buildBodySlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaComponentContext context,
  required bool applyVisibilityWhen,
}) {
  if (children == null || children.isEmpty) return const <Widget>[];

  final wrapperBuilder = buildVisibleWhenWrapper(
    visibility: context.visibility,
    diagnostics: context.diagnostics,
    diagnosticsContext: context.diagnosticsContext,
  );

  return children.where((child) {
    if (!applyVisibilityWhen) return true;
    if (child is ComponentNode) {
      return evaluateVisibleWhen(
        child.visibleWhen,
        context.visibility,
        diagnostics: context.diagnostics,
        diagnosticsContext: context.diagnosticsContext,
        nodeType: child.type,
      );
    }
    return true;
  }).map((child) {
    final rendered = SchemaRenderer(
      rootNode: child,
      registry: registry,
      wrapperBuilder: wrapperBuilder,
    ).render();

    return rendered;
  }).toList(growable: false);
}
