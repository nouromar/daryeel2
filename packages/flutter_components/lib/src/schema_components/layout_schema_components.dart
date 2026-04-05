import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';

void registerRowSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Row', (node, componentRegistry) {
    final spacing = _asDouble(node.props['spacing']) ?? 0.0;

    final mainAxisAlignment =
        _parseMainAxisAlignment(node.props['mainAxisAlignment']);
    final crossAxisAlignment =
        _parseCrossAxisAlignment(node.props['crossAxisAlignment']);
    final mainAxisSize = _parseMainAxisSize(node.props['mainAxisSize']);

    final children = _buildSlot(
      node.slots['children'],
      componentRegistry,
      context: context,
    );

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: _withSpacing(children, Axis.horizontal, spacing),
    );
  });
}

void registerColumnSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Column', (node, componentRegistry) {
    final spacing = _asDouble(node.props['spacing']) ?? 0.0;

    final mainAxisAlignment =
        _parseMainAxisAlignment(node.props['mainAxisAlignment']);
    final crossAxisAlignment =
        _parseCrossAxisAlignment(node.props['crossAxisAlignment']);
    final mainAxisSize = _parseMainAxisSize(node.props['mainAxisSize']);

    final children = _buildSlot(
      node.slots['children'],
      componentRegistry,
      context: context,
    );

    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: _withSpacing(children, Axis.vertical, spacing),
    );
  });
}

void registerStackSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Stack', (node, componentRegistry) {
    final alignment = _parseAlignment(node.props['alignment']);
    final fit = _parseStackFit(node.props['fit']);
    final clipBehavior = _parseClip(node.props['clipBehavior']);

    final children = _buildSlot(
      node.slots['children'],
      componentRegistry,
      context: context,
    );

    return Stack(
      alignment: alignment,
      fit: fit,
      clipBehavior: clipBehavior,
      children: children,
    );
  });
}

void registerWrapSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Wrap', (node, componentRegistry) {
    final direction = _parseAxis(node.props['direction']);
    final alignment = _parseWrapAlignment(node.props['alignment']);
    final runAlignment = _parseWrapAlignment(node.props['runAlignment']);
    final crossAxisAlignment =
        _parseWrapCrossAlignment(node.props['crossAxisAlignment']);

    final spacing = _asDouble(node.props['spacing']) ?? 0.0;
    final runSpacing = _asDouble(node.props['runSpacing']) ?? 0.0;

    final children = _buildSlot(
      node.slots['children'],
      componentRegistry,
      context: context,
    );

    return Wrap(
      direction: direction,
      alignment: alignment,
      runAlignment: runAlignment,
      crossAxisAlignment: crossAxisAlignment,
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  });
}

void registerPaddingSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Padding', (node, componentRegistry) {
    final padding = _parseEdgeInsets(node.props);
    final child = _buildSingleChildSlot(
      node.slots['child'],
      componentRegistry,
      context: context,
      componentName: 'Padding',
    );

    if (child == null) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: child,
    );
  });
}

void registerAlignSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Align', (node, componentRegistry) {
    final alignment = _parseAlignment(node.props['alignment']);
    final widthFactor = _asDouble(node.props['widthFactor']);
    final heightFactor = _asDouble(node.props['heightFactor']);

    final child = _buildSingleChildSlot(
      node.slots['child'],
      componentRegistry,
      context: context,
      componentName: 'Align',
    );

    if (child == null) return const SizedBox.shrink();

    return Align(
      alignment: alignment,
      widthFactor: widthFactor,
      heightFactor: heightFactor,
      child: child,
    );
  });
}

void registerSizedBoxSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('SizedBox', (node, componentRegistry) {
    final width = _asDouble(node.props['width']);
    final height = _asDouble(node.props['height']);

    final child = _buildSingleChildSlot(
      node.slots['child'],
      componentRegistry,
      context: context,
      componentName: 'SizedBox',
    );

    return SizedBox(
      width: width,
      height: height,
      child: child,
    );
  });
}

void registerExpandedSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Expanded', (node, componentRegistry) {
    final rawFlex = _asInt(node.props['flex']);
    final flex = rawFlex == null ? 1 : rawFlex.clamp(1, 100);

    final child = _buildSingleChildSlot(
      node.slots['child'],
      componentRegistry,
      context: context,
      componentName: 'Expanded',
    );

    if (child == null) {
      return const UnknownSchemaWidget(
          componentName: 'Expanded(missing-child)');
    }

    return Expanded(
      flex: flex,
      child: child,
    );
  });
}

List<Widget> _buildSlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaComponentContext context,
}) {
  if (children == null || children.isEmpty) return const <Widget>[];

  return children
      .where((child) {
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
      })
      .map((child) =>
          SchemaRenderer(rootNode: child, registry: registry).render())
      .toList(growable: false);
}

Widget? _buildSingleChildSlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaComponentContext context,
  required String componentName,
}) {
  if (children == null || children.isEmpty) return null;
  if (children.length != 1) {
    return UnknownSchemaWidget(
      componentName: '$componentName(multiple-children)',
    );
  }

  final child = children.single;
  if (child is ComponentNode) {
    final visible = evaluateVisibleWhen(
      child.visibleWhen,
      context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
      nodeType: child.type,
    );
    if (!visible) return null;
  }

  return SchemaRenderer(rootNode: child, registry: registry).render();
}

List<Widget> _withSpacing(List<Widget> children, Axis axis, double spacing) {
  if (children.length <= 1) return children;
  if (spacing <= 0) return children;

  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) {
      out.add(
        axis == Axis.horizontal
            ? SizedBox(width: spacing)
            : SizedBox(height: spacing),
      );
    }
    out.add(children[i]);
  }
  return out;
}

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

MainAxisAlignment _parseMainAxisAlignment(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'end' => MainAxisAlignment.end,
    'center' => MainAxisAlignment.center,
    'spacebetween' || 'space_between' => MainAxisAlignment.spaceBetween,
    'spacearound' || 'space_around' => MainAxisAlignment.spaceAround,
    'spaceevenly' || 'space_evenly' => MainAxisAlignment.spaceEvenly,
    _ => MainAxisAlignment.start,
  };
}

CrossAxisAlignment _parseCrossAxisAlignment(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'end' => CrossAxisAlignment.end,
    'center' => CrossAxisAlignment.center,
    'stretch' => CrossAxisAlignment.stretch,
    _ => CrossAxisAlignment.start,
  };
}

MainAxisSize _parseMainAxisSize(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'min' => MainAxisSize.min,
    _ => MainAxisSize.max,
  };
}

Alignment _parseAlignment(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'topleft' || 'top_left' => Alignment.topLeft,
    'topcenter' || 'top_center' => Alignment.topCenter,
    'topright' || 'top_right' => Alignment.topRight,
    'centerleft' || 'center_left' => Alignment.centerLeft,
    'center' => Alignment.center,
    'centerright' || 'center_right' => Alignment.centerRight,
    'bottomleft' || 'bottom_left' => Alignment.bottomLeft,
    'bottomcenter' || 'bottom_center' => Alignment.bottomCenter,
    'bottomright' || 'bottom_right' => Alignment.bottomRight,
    _ => Alignment.center,
  };
}

StackFit _parseStackFit(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'expand' => StackFit.expand,
    'passthrough' || 'pass_through' => StackFit.passthrough,
    _ => StackFit.loose,
  };
}

Clip _parseClip(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'none' => Clip.none,
    'hardedge' || 'hard_edge' => Clip.hardEdge,
    'antialias' || 'anti_alias' => Clip.antiAlias,
    'antialiaswithsavelayer' ||
    'anti_alias_with_save_layer' ||
    'antialias_with_savelayer' =>
      Clip.antiAliasWithSaveLayer,
    _ => Clip.hardEdge,
  };
}

Axis _parseAxis(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'vertical' => Axis.vertical,
    _ => Axis.horizontal,
  };
}

WrapAlignment _parseWrapAlignment(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'end' => WrapAlignment.end,
    'center' => WrapAlignment.center,
    'spacebetween' || 'space_between' => WrapAlignment.spaceBetween,
    'spacearound' || 'space_around' => WrapAlignment.spaceAround,
    'spaceevenly' || 'space_evenly' => WrapAlignment.spaceEvenly,
    _ => WrapAlignment.start,
  };
}

WrapCrossAlignment _parseWrapCrossAlignment(Object? raw) {
  final v = (raw is String) ? raw.trim().toLowerCase() : null;
  return switch (v) {
    'end' => WrapCrossAlignment.end,
    'center' => WrapCrossAlignment.center,
    _ => WrapCrossAlignment.start,
  };
}

EdgeInsets _parseEdgeInsets(Map<String, Object?> props) {
  double? read(String key) => _asDouble(props[key]);

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
