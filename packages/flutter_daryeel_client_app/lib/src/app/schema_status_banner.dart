import 'package:flutter/material.dart';

import '../runtime/daryeel_runtime_view_model.dart';

class SchemaStatusBanner extends StatelessWidget {
  const SchemaStatusBanner({required this.screen, super.key});

  final LoadedScreen screen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = switch (screen.source) {
      ScreenLoadSource.remote => colorScheme.secondaryContainer,
      ScreenLoadSource.bundled => colorScheme.surfaceContainerHighest,
      ScreenLoadSource.fallback => colorScheme.tertiaryContainer,
    };
    final textColor = switch (screen.source) {
      ScreenLoadSource.remote => colorScheme.onSecondaryContainer,
      ScreenLoadSource.bundled => colorScheme.onSurfaceVariant,
      ScreenLoadSource.fallback => colorScheme.onTertiaryContainer,
    };
    final message = switch (screen.source) {
      ScreenLoadSource.remote =>
        'Schema source: remote service (${screen.bundle.schemaId})',
      ScreenLoadSource.bundled =>
        'Schema source: bundled baseline (${screen.bundle.schemaId})',
      ScreenLoadSource.fallback =>
        'Schema source: bundled fallback (${screen.bundle.schemaId})',
    };

    return Container(
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        screen.errorMessage == null
            ? message
            : '$message. Remote load failed: ${screen.errorMessage}',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
