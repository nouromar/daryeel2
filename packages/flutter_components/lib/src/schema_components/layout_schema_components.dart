import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerRowSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Row', (node, componentRegistry) {
    final spacing = schemaAsDouble(node.props['spacing']) ?? 0.0;

    final mainAxisAlignment =
        _parseMainAxisAlignment(node.props['mainAxisAlignment']);
    final crossAxisAlignment =
        _parseCrossAxisAlignment(node.props['crossAxisAlignment']);
    final mainAxisSize = _parseMainAxisSize(node.props['mainAxisSize']);

    final children = buildSchemaSlotWidgets(
      node.slots['children'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
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
    final spacing = schemaAsDouble(node.props['spacing']) ?? 0.0;

    final mainAxisAlignment =
        _parseMainAxisAlignment(node.props['mainAxisAlignment']);
    final crossAxisAlignment =
        _parseCrossAxisAlignment(node.props['crossAxisAlignment']);
    final mainAxisSize = _parseMainAxisSize(node.props['mainAxisSize']);

    final children = buildSchemaSlotWidgets(
      node.slots['children'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
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

    final children = buildSchemaSlotWidgets(
      node.slots['children'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
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

    final spacing = schemaAsDouble(node.props['spacing']) ?? 0.0;
    final runSpacing = schemaAsDouble(node.props['runSpacing']) ?? 0.0;

    final children = buildSchemaSlotWidgets(
      node.slots['children'],
      componentRegistry,
      context: context,
      applyVisibilityWhen: true,
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
    final child = buildSingleChildSchemaSlotWidget(
      node.slots['child'],
      componentRegistry,
      componentName: 'Padding',
      context: context,
      applyVisibilityWhen: true,
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
    final widthFactor = schemaAsDouble(node.props['widthFactor']);
    final heightFactor = schemaAsDouble(node.props['heightFactor']);

    final child = buildSingleChildSchemaSlotWidget(
      node.slots['child'],
      componentRegistry,
      componentName: 'Align',
      context: context,
      applyVisibilityWhen: true,
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
    final width = schemaAsDouble(node.props['width']);
    final height = schemaAsDouble(node.props['height']);

    final child = buildSingleChildSchemaSlotWidget(
      node.slots['child'],
      componentRegistry,
      componentName: 'SizedBox',
      context: context,
      applyVisibilityWhen: true,
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
    final rawFlex = schemaAsInt(node.props['flex']);
    final flex = rawFlex == null ? 1 : rawFlex.clamp(1, 100);

    final child = buildSingleChildSchemaSlotWidget(
      node.slots['child'],
      componentRegistry,
      componentName: 'Expanded',
      context: context,
      applyVisibilityWhen: true,
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
  return schemaAsDouble(v);
}

int? _asInt(Object? v) {
  return schemaAsInt(v);
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
