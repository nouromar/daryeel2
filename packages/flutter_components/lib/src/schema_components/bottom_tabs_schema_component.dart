import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_node_wrapper.dart';

void registerBottomTabsSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('BottomTabs', (node, componentRegistry) {
    final tabs = _parseTabs(node.props['tabs']);

    // Default to the common 3-tab layout if not provided.
    final effectiveTabs = tabs.isEmpty
        ? const <_BottomTabSpec>[
            _BottomTabSpec(id: 'home', label: 'Home'),
            _BottomTabSpec(id: 'activities', label: 'Activities'),
            _BottomTabSpec(id: 'account', label: 'Account'),
          ]
        : tabs;

    final childrenByTab = <String, List<SchemaNode>>{
      for (final tab in effectiveTabs)
        tab.id: node.slots[tab.id] ?? const <SchemaNode>[],
    };

    return _BottomTabsWidget(
      tabs: effectiveTabs,
      childrenByTab: childrenByTab,
      registry: componentRegistry,
      visibility: context.visibility,
      diagnostics: context.diagnostics,
      diagnosticsContext: context.diagnosticsContext,
    );
  });
}

class _BottomTabsWidget extends StatefulWidget {
  const _BottomTabsWidget({
    required this.tabs,
    required this.childrenByTab,
    required this.registry,
    required this.visibility,
    required this.diagnostics,
    required this.diagnosticsContext,
  });

  final List<_BottomTabSpec> tabs;
  final Map<String, List<SchemaNode>> childrenByTab;
  final SchemaWidgetRegistry registry;
  final SchemaVisibilityContext visibility;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;

  @override
  State<_BottomTabsWidget> createState() => _BottomTabsWidgetState();
}

class _BottomTabsWidgetState extends State<_BottomTabsWidget> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final clampedIndex = _index.clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);

    final tabBodies = <Widget>[
      for (final tab in tabs)
        _buildTabBody(widget.childrenByTab[tab.id] ?? const <SchemaNode>[]),
    ];

    return Column(
      children: [
        Expanded(
          child: tabs.isEmpty
              ? const SizedBox.shrink()
              : IndexedStack(index: clampedIndex, children: tabBodies),
        ),
        if (tabs.isNotEmpty)
          BottomNavigationBar(
            currentIndex: clampedIndex,
            onTap: (next) => setState(() => _index = next),
            items: [
              for (final tab in tabs)
                BottomNavigationBarItem(
                  icon: Icon(tab.icon ?? _defaultTabIcon(tab.id)),
                  activeIcon: Icon(tab.icon ?? _defaultTabIcon(tab.id)),
                  label: tab.label,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildTabBody(List<SchemaNode> nodes) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    final wrapperBuilder = buildVisibleWhenWrapper(
      visibility: widget.visibility,
      diagnostics: widget.diagnostics,
      diagnosticsContext: widget.diagnosticsContext,
    );

    if (nodes.length == 1) {
      return SchemaRenderer(
        rootNode: nodes.single,
        registry: widget.registry,
        wrapperBuilder: wrapperBuilder,
      ).render();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in nodes)
          SchemaRenderer(
            rootNode: child,
            registry: widget.registry,
            wrapperBuilder: wrapperBuilder,
          ).render(),
      ],
    );
  }
}

List<_BottomTabSpec> _parseTabs(Object? raw) {
  if (raw is! List) return const <_BottomTabSpec>[];

  final out = <_BottomTabSpec>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, Object?>.from(item.cast<String, Object?>());
    final id = map['id'] as String?;
    final label = map['label'] as String?;
    final icon = _resolveMaterialIcon(map['icon'] as String?);
    if (id == null || id.isEmpty) continue;
    out.add(_BottomTabSpec(
      id: id,
      label: (label == null || label.isEmpty) ? id : label,
      icon: icon,
    ));
  }

  return out;
}

class _BottomTabSpec {
  const _BottomTabSpec({required this.id, required this.label, this.icon});

  final String id;
  final String label;
  final IconData? icon;
}

IconData _defaultTabIcon(String id) {
  switch (id.trim().toLowerCase()) {
    case 'home':
      return Icons.home_outlined;
    case 'activities':
      return Icons.history;
    case 'account':
      return Icons.person_outline;
    default:
      return Icons.circle_outlined;
  }
}

IconData? _resolveMaterialIcon(String? name) {
  if (name == null) return null;
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;

  return switch (key) {
    'home' || 'home_visit' => Icons.home_outlined,
    'activities' || 'activity' || 'history' => Icons.history,
    'account' || 'person' || 'profile' => Icons.person_outline,
    'ambulance' ||
    'local_hospital' ||
    'hospital' =>
      Icons.local_hospital_outlined,
    'pharmacy' || 'local_pharmacy' => Icons.local_pharmacy_outlined,
    _ => null,
  };
}
