import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

SchemaWidgetRegistry buildProviderComponentRegistry({
  required ScreenSchema screen,
  required SchemaActionDispatcher actionDispatcher,
  required SchemaVisibilityContext visibility,
  RuntimeDiagnostics? diagnostics,
  Map<String, Object?> diagnosticsContext = const <String, Object?>{},
}) {
  final registry = SchemaWidgetRegistry();

  registry.register('TextInput', (node, componentRegistry) {
    final label = node.props['label'] as String?;
    final hint = node.props['hint'] as String?;
    final obscureText = node.props['obscureText'] == true;
    final testId = node.props['testId'] as String?;
    final validationRules = SchemaFieldValidationRules.tryParse(
      node.props['validation'],
    );

    final binding = SchemaFieldBinding.tryParse(node.bind);
    if (binding == null) {
      return const UnknownSchemaWidget(
        componentName: 'TextInput(missing-bind)',
      );
    }

    return Builder(
      builder: (context) {
        final store = SchemaFormScope.maybeOf(context);
        if (store == null) {
          return const UnknownSchemaWidget(
            componentName: 'TextInput(missing-form-scope)',
          );
        }

        return _BoundTextInput(
          store: store,
          binding: binding,
          label: label,
          hint: hint,
          obscureText: obscureText,
          testId: testId,
          validationRules: validationRules,
        );
      },
    );
  });

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

class _BoundTextInput extends StatefulWidget {
  const _BoundTextInput({
    required this.store,
    required this.binding,
    required this.label,
    required this.hint,
    required this.obscureText,
    required this.testId,
    required this.validationRules,
  });

  final SchemaFormStore store;
  final SchemaFieldBinding binding;
  final String? label;
  final String? hint;
  final bool obscureText;
  final String? testId;
  final SchemaFieldValidationRules? validationRules;

  @override
  State<_BoundTextInput> createState() => _BoundTextInputState();
}

class _BoundTextInputState extends State<_BoundTextInput> {
  late final TextEditingController _controller;
  late final ValueListenable<Object?> _valueListenable;

  @override
  void initState() {
    super.initState();

    final initial = widget.store.getFieldValue(
      widget.binding.formId,
      widget.binding.fieldKey,
    );

    _controller = TextEditingController(text: initial is String ? initial : '');

    widget.store.registerFieldValidation(
      widget.binding.formId,
      widget.binding.fieldKey,
      widget.validationRules,
    );

    _valueListenable = widget.store.watchFieldValue(
      widget.binding.formId,
      widget.binding.fieldKey,
    );
    _valueListenable.addListener(_syncFromStore);
  }

  @override
  void dispose() {
    _valueListenable.removeListener(_syncFromStore);
    _controller.dispose();
    super.dispose();
  }

  void _syncFromStore() {
    final v = _valueListenable.value;
    final next = v is String ? v : '';
    if (_controller.text == next) return;
    _controller.value = _controller.value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final hint = widget.hint;

    return ValueListenableBuilder<String?>(
      valueListenable: widget.store.watchFieldError(
        widget.binding.formId,
        widget.binding.fieldKey,
      ),
      builder: (context, error, _) {
        return TextField(
          key: widget.testId == null
              ? null
              : ValueKey('schema.textinput.${widget.testId}'),
          controller: _controller,
          obscureText: widget.obscureText,
          onChanged: (value) {
            widget.store.setFieldValue(
              widget.binding.formId,
              widget.binding.fieldKey,
              value,
            );
          },
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: (error == null || error.isEmpty) ? null : error,
          ),
        );
      },
    );
  }
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
