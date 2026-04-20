import 'package:flutter/material.dart';

class InfoCardWidget extends StatelessWidget {
  const InfoCardWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.variant = 'default',
    this.surface = 'raised',
    this.density = 'comfortable',
    this.titleVariant,
    this.titleWeight,
    this.titleColor,
    this.subtitleVariant,
    this.subtitleWeight,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final String variant;
  final String surface;
  final String density;
  final String? titleVariant;
  final String? titleWeight;
  final String? titleColor;
  final String? subtitleVariant;
  final String? subtitleWeight;
  final String? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final titleText = title.trim();
    final subtitleText = subtitle.trim();

    final showTitle = titleText.isNotEmpty;
    final showSubtitle = subtitleText.isNotEmpty;
    if (!showTitle && !showSubtitle) {
      return const SizedBox.shrink();
    }

    final normalizedVariant = variant.trim().toLowerCase();
    final isCompactVariant = normalizedVariant == 'compact';
    final isEmphasizedVariant = normalizedVariant == 'emphasized';

    final isCompactDensity = density.trim().toLowerCase() == 'compact';
    final isCompact = isCompactVariant || isCompactDensity;

    final padding = isCompact ? 16.0 : 20.0;
    final titleGap = isCompact ? 4.0 : 6.0;

    final theme = Theme.of(context);

    final defaultTitleStyle = switch (normalizedVariant) {
      'compact' => theme.textTheme.titleMedium,
      'emphasized' => theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      _ => theme.textTheme.headlineSmall,
    };

    final baseTitleStyle =
        _resolveVariant(theme, titleVariant) ?? defaultTitleStyle;
    final baseSubtitleStyle =
        _resolveVariant(theme, subtitleVariant) ?? theme.textTheme.bodyMedium;

    final resolvedTitleStyle = _applyOverrides(
      baseTitleStyle,
      theme: theme,
      colorRaw: titleColor,
      weightRaw: titleWeight,
      emphasizedDefault: isEmphasizedVariant,
    )?.copyWith(
      height: isCompact ? 1.1 : null,
    );
    final resolvedSubtitleStyle = _applyOverrides(
      baseSubtitleStyle,
      theme: theme,
      colorRaw: subtitleColor,
      weightRaw: subtitleWeight,
      emphasizedDefault: false,
    );

    return Card(
      elevation: switch (surface) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) Text(titleText, style: resolvedTitleStyle),
            if (showTitle && showSubtitle) SizedBox(height: titleGap),
            if (showSubtitle) Text(subtitleText, style: resolvedSubtitleStyle),
          ],
        ),
      ),
    );
  }
}

TextStyle? _resolveVariant(ThemeData theme, String? variantRaw) {
  final v = variantRaw?.trim().toLowerCase();
  return switch (v) {
    'title' => theme.textTheme.titleLarge,
    'subtitle' => theme.textTheme.titleMedium,
    'label' => theme.textTheme.labelMedium,
    'caption' => theme.textTheme.bodySmall,
    'body' || null || '' => theme.textTheme.bodyMedium,
    _ => theme.textTheme.bodyMedium,
  };
}

TextStyle? _applyOverrides(
  TextStyle? base, {
  required ThemeData theme,
  required String? colorRaw,
  required String? weightRaw,
  required bool emphasizedDefault,
}) {
  final resolvedColor = _resolveColor(theme, colorRaw, emphasizedDefault);
  final resolvedWeight = _resolveFontWeight(weightRaw);

  if (resolvedColor == null && resolvedWeight == null) return base;
  return (base ?? const TextStyle()).copyWith(
    color: resolvedColor,
    fontWeight: resolvedWeight,
  );
}

Color? _resolveColor(
  ThemeData theme,
  String? colorRaw,
  bool emphasizedDefault,
) {
  final v = colorRaw?.trim().toLowerCase();
  final scheme = theme.colorScheme;

  if (v == null || v.isEmpty) {
    return emphasizedDefault ? scheme.primary : null;
  }

  return switch (v) {
    'muted' || 'subtle' || 'secondarytext' => scheme.onSurfaceVariant,
    'primary' => scheme.primary,
    'secondary' => scheme.secondary,
    'error' => scheme.error,
    'default' => null,
    _ => null,
  };
}

FontWeight? _resolveFontWeight(String? weightRaw) {
  final v = weightRaw?.trim().toLowerCase();
  return switch (v) {
    'regular' || 'normal' => FontWeight.w400,
    'medium' => FontWeight.w500,
    'semibold' || 'semi' => FontWeight.w600,
    'bold' => FontWeight.w700,
    null || '' => null,
    _ => null,
  };
}
