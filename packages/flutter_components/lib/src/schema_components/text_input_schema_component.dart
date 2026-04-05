import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';

void registerTextInputSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('TextInput', (node, componentRegistry) {
    final label = node.props['label'] as String?;
    final hint = node.props['hint'] as String?;
    final obscureText = node.props['obscureText'] == true;
    final testId = node.props['testId'] as String?;
    final debounceMsRaw = node.props['debounceMs'];
    final validationRules = SchemaFieldValidationRules.tryParse(
      node.props['validation'],
    );

    final rawBind = node.bind?.trim();
    if (rawBind == null || rawBind.isEmpty) {
      return const UnknownSchemaWidget(
          componentName: 'TextInput(missing-bind)');
    }

    const statePrefixDot = r'$state.';
    const statePrefixColon = r'$state:';

    final isStateBinding = rawBind.startsWith(statePrefixDot) ||
        rawBind.startsWith(statePrefixColon);
    final stateKey = isStateBinding
        ? (rawBind.startsWith(statePrefixDot)
            ? rawBind.substring(statePrefixDot.length)
            : rawBind.substring(statePrefixColon.length))
        : null;

    final binding =
        isStateBinding ? null : SchemaFieldBinding.tryParse(rawBind);

    if (!isStateBinding && binding == null) {
      return const UnknownSchemaWidget(
          componentName: 'TextInput(invalid-bind)');
    }

    return Builder(
      builder: (context) {
        int? parseDebounceMs(Object? raw) {
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        }

        final debounceMs = parseDebounceMs(debounceMsRaw);
        final boundedDebounceMs =
            debounceMs == null ? 250 : debounceMs.clamp(0, 2000);

        if (isStateBinding) {
          final key = (stateKey ?? '').trim();
          if (key.isEmpty) {
            return const UnknownSchemaWidget(
              componentName: 'TextInput(invalid-state-bind)',
            );
          }

          final store = SchemaStateScope.maybeOf(context);
          if (store == null) {
            return const UnknownSchemaWidget(
              componentName: 'TextInput(missing-state-scope)',
            );
          }

          return _BoundStateTextInput(
            store: store,
            stateKey: key,
            label: label,
            hint: hint,
            obscureText: obscureText,
            testId: testId,
            debounce: Duration(milliseconds: boundedDebounceMs),
          );
        }

        final store = SchemaFormScope.maybeOf(context);
        if (store == null) {
          return const UnknownSchemaWidget(
            componentName: 'TextInput(missing-form-scope)',
          );
        }

        return _BoundTextInput(
          store: store,
          binding: binding!,
          label: label,
          hint: hint,
          obscureText: obscureText,
          testId: testId,
          validationRules: validationRules,
        );
      },
    );
  });
}

class _BoundStateTextInput extends StatefulWidget {
  const _BoundStateTextInput({
    required this.store,
    required this.stateKey,
    required this.label,
    required this.hint,
    required this.obscureText,
    required this.testId,
    required this.debounce,
  });

  final SchemaStateStore store;
  final String stateKey;
  final String? label;
  final String? hint;
  final bool obscureText;
  final String? testId;
  final Duration debounce;

  @override
  State<_BoundStateTextInput> createState() => _BoundStateTextInputState();
}

class _BoundStateTextInputState extends State<_BoundStateTextInput> {
  late final TextEditingController _controller;
  late final ValueListenable<Object?> _valueListenable;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    final initial = widget.store.getValue(widget.stateKey);
    _controller = TextEditingController(text: initial is String ? initial : '');

    _valueListenable = widget.store.watchValue(widget.stateKey);
    _valueListenable.addListener(_syncFromStore);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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

  void _setStateValueDebounced(String value) {
    _debounceTimer?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.store.setValue(widget.stateKey, value);
      return;
    }
    _debounceTimer = Timer(widget.debounce, () {
      widget.store.setValue(widget.stateKey, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.testId == null
          ? null
          : ValueKey('schema.textinput.${widget.testId}'),
      controller: _controller,
      obscureText: widget.obscureText,
      onChanged: _setStateValueDebounced,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
      ),
    );
  }
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
