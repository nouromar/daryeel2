import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

SchemaWidgetRegistry buildCustomerComponentRegistry({
  required ScreenSchema screen,
  required SchemaActionDispatcher actionDispatcher,
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  final registry = SchemaWidgetRegistry();

  registry.register('ScreenTemplate', (node, componentRegistry) {
    final header = _buildSlot(
      node.slots['header'],
      componentRegistry,
      visibility: visibility,
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
    );
    final body = _buildSlot(
      node.slots['body'],
      componentRegistry,
      visibility: visibility,
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
    );
    final footer = _buildSlot(
      node.slots['footer'],
      componentRegistry,
      visibility: visibility,
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
    );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header.isNotEmpty) ...[...header, const SizedBox(height: 8)],
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
          if (footer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: footer,
              ),
            ),
        ],
      ),
    );
  });

  registry.register('InfoCard', (node, componentRegistry) {
    final title = node.props['title'] as String? ?? 'Untitled';
    final subtitle = node.props['subtitle'] as String? ?? '';
    final surface = node.props['surface'] as String? ?? 'raised';

    return Builder(
      builder: (context) {
        return Card(
          elevation: switch (surface) {
            'flat' => 0,
            'subtle' => 0.5,
            _ => 1.5,
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        );
      },
    );
  });

  registry.register('PrimaryActionBar', (node, componentRegistry) {
    final label = node.props['primaryLabel'] as String? ?? 'Continue';
    final primaryAction = resolveComponentAction(
      screen: screen,
      node: node,
      actionKey: 'primary',
    );

    return Builder(
      builder: (context) {
        return FilledButton(
          onPressed: primaryAction == null
              ? null
              : () async {
                  final result = await tryDispatchComponentAction(
                    context: context,
                    screen: screen,
                    node: node,
                    actionKey: 'primary',
                    dispatcher: actionDispatcher,
                    diagnostics: diagnostics,
                    diagnosticsContext: diagnosticsContext,
                  );

                  final failure = result.failure;
                  if (failure == null) return;
                  if (!context.mounted) return;

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(failure.message)));
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(label),
          ),
        );
      },
    );
  });

  return registry;
}

List<Widget> _buildSlot(
  List<SchemaNode>? children,
  SchemaWidgetRegistry registry, {
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  if (children == null || children.isEmpty) {
    return const [];
  }

  return children
      .where((child) {
        if (child is ComponentNode) {
          return evaluateVisibleWhen(
            child.visibleWhen,
            visibility,
            diagnostics: diagnostics,
            diagnosticsContext: diagnosticsContext,
            nodeType: child.type,
          );
        }
        return true;
      })
      .map(
        (child) => SchemaRenderer(rootNode: child, registry: registry).render(),
      )
      .toList(growable: false);
}
