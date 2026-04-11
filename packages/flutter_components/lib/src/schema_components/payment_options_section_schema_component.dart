import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';

void registerPaymentOptionsSectionSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('PaymentOptionsSection', (node, _) {
    final title = (node.props['title'] as String?)?.trim() ?? 'Payment';
    final methodTitle =
        (node.props['methodTitle'] as String?)?.trim() ?? 'Payment method';
    final timingTitle =
        (node.props['timingTitle'] as String?)?.trim() ?? 'Payment timing';
    final methodsPath = (node.props['methodsPath'] as String?)?.trim() ??
        'payment_options.methods';
    final timingsPath = (node.props['timingsPath'] as String?)?.trim() ??
        'payment_options.timings';
    final showTiming = node.props['showTiming'] != false;
    final methodBind = (node.props['methodBind'] as String?)?.trim();
    final timingBind = (node.props['timingBind'] as String?)?.trim();
    final surface = (node.props['surface'] as String?)?.trim() ?? 'raised';

    final methodStateKey = _stateKeyFromBind(methodBind);
    final timingStateKey = _stateKeyFromBind(timingBind);
    if (methodStateKey == null || timingStateKey == null) {
      return const UnknownSchemaWidget(
        componentName: 'PaymentOptionsSection(invalid-bind)',
      );
    }

    return _PaymentOptionsSectionWidget(
      title: title,
      methodTitle: methodTitle,
      timingTitle: timingTitle,
      methodsPath: methodsPath,
      timingsPath: timingsPath,
      showTiming: showTiming,
      methodStateKey: methodStateKey,
      timingStateKey: timingStateKey,
      surface: surface,
    );
  });
}

String? _stateKeyFromBind(String? rawBind) {
  if (rawBind == null) return null;
  const statePrefixDot = r'$state.';
  const statePrefixColon = r'$state:';

  final trimmed = rawBind.trim();
  if (trimmed.startsWith(statePrefixDot)) {
    final key = trimmed.substring(statePrefixDot.length).trim();
    return key.isEmpty ? null : key;
  }
  if (trimmed.startsWith(statePrefixColon)) {
    final key = trimmed.substring(statePrefixColon.length).trim();
    return key.isEmpty ? null : key;
  }
  return null;
}

final class _PaymentOptionsSectionWidget extends StatelessWidget {
  const _PaymentOptionsSectionWidget({
    required this.title,
    required this.methodTitle,
    required this.timingTitle,
    required this.methodsPath,
    required this.timingsPath,
    required this.showTiming,
    required this.methodStateKey,
    required this.timingStateKey,
    required this.surface,
  });

  final String title;
  final String methodTitle;
  final String timingTitle;
  final String methodsPath;
  final String timingsPath;
  final bool showTiming;
  final String methodStateKey;
  final String timingStateKey;
  final String surface;

  @override
  Widget build(BuildContext context) {
    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      return const UnknownSchemaWidget(
        componentName: 'PaymentOptionsSection(missing-state-scope)',
      );
    }

    final dataScope = SchemaDataScope.maybeOf(context);
    if (dataScope == null) {
      return const UnknownSchemaWidget(
        componentName: 'PaymentOptionsSection(missing-data-scope)',
      );
    }

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final methods = _readOptions(dataScope.data, methodsPath);
        final timings = showTiming
            ? _readOptions(dataScope.data, timingsPath)
            : const <_PaymentOption>[];

        final selectedMethod = store.getValue(methodStateKey)?.toString();
        final selectedTiming = store.getValue(timingStateKey)?.toString();

        if (methods.isEmpty && timings.isEmpty) {
          return _PaymentCard(
            title: title,
            surface: surface,
            child: Text(
              'Payment options are not available right now.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        return _PaymentCard(
          title: title,
          surface: surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (methods.isNotEmpty) ...[
                _SectionLabel(text: methodTitle),
                const SizedBox(height: 8),
                _OptionWrap(
                  options: methods,
                  selectedId: selectedMethod,
                  onSelected: (value) => store.setValue(methodStateKey, value),
                ),
              ],
              if (showTiming && methods.isNotEmpty && timings.isNotEmpty) ...[
                const SizedBox(height: 16),
              ],
              if (showTiming && timings.isNotEmpty) ...[
                _SectionLabel(text: timingTitle),
                const SizedBox(height: 8),
                _OptionWrap(
                  options: timings,
                  selectedId: selectedTiming,
                  onSelected: (value) => store.setValue(timingStateKey, value),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

final class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.title,
    required this.child,
    required this.surface,
  });

  final String title;
  final Widget child;
  final String surface;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

List<_PaymentOption> _readOptions(Object? root, String path) {
  final raw = readJsonPath(root, path);
  if (raw is! List) return const <_PaymentOption>[];

  final out = <_PaymentOption>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = item['id']?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    final labelRaw = item['label'];
    final label = (labelRaw is String && labelRaw.trim().isNotEmpty)
        ? labelRaw.trim()
        : id;
    final descriptionRaw = item['description'];
    final description =
        (descriptionRaw is String && descriptionRaw.trim().isNotEmpty)
            ? descriptionRaw.trim()
            : null;
    out.add(_PaymentOption(id: id, label: label, description: description));
  }

  return out;
}

final class _PaymentOption {
  const _PaymentOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String? description;
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

final class _OptionWrap extends StatelessWidget {
  const _OptionWrap({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<_PaymentOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.label),
            tooltip: option.description,
            selected: option.id == selectedId,
            onSelected: (_) => onSelected(option.id),
          ),
      ],
    );
  }
}
