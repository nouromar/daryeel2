import 'package:flutter/material.dart';

class SectionCardWidget extends StatelessWidget {
  const SectionCardWidget({
    super.key,
    required this.child,
    this.title = '',
    this.subtitle = '',
    this.surface = 'raised',
    this.density = 'comfortable',
    this.titleVariant,
    this.titleWeight,
    this.titleColor,
    this.subtitleVariant,
    this.subtitleWeight,
    this.subtitleColor,
    this.contentGap,
  });

  final Widget child;
  final String title;
  final String subtitle;
  final String surface;
  final String density;

  final String? titleVariant;
  final String? titleWeight;
  final String? titleColor;
  final String? subtitleVariant;
  final String? subtitleWeight;
  final String? subtitleColor;

  final double? contentGap;

  @override
  Widget build(BuildContext context) {
    final titleText = title.trim();
    final subtitleText = subtitle.trim();

    final showTitle = titleText.isNotEmpty;
    final showSubtitle = subtitleText.isNotEmpty;

    final theme = Theme.of(context);
    final isCompact = density.trim().toLowerCase() == 'compact';

    final padding = isCompact ? 16.0 : 20.0;
    final titleGap = isCompact ? 4.0 : 6.0;
    final resolvedContentGap = (contentGap ?? (isCompact ? 12.0 : 14.0)).clamp(
      0.0,
      10000.0,
    );

    final baseTitleStyle =
        _resolveVariant(theme, titleVariant) ?? theme.textTheme.titleMedium;
    final baseSubtitleStyle =
        _resolveVariant(theme, subtitleVariant) ?? theme.textTheme.bodyMedium;

    final resolvedTitleStyle = _applyOverrides(
      baseTitleStyle,
      theme: theme,
      colorRaw: titleColor,
      weightRaw: titleWeight,
      emphasizedDefault: false,
    )?.copyWith(height: isCompact ? 1.1 : null);

    final resolvedSubtitleStyle = _applyOverrides(
      baseSubtitleStyle,
      theme: theme,
      colorRaw: subtitleColor,
      weightRaw: subtitleWeight,
      emphasizedDefault: false,
    );

    return Card(
      elevation: switch (surface.trim().toLowerCase()) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) Text(titleText, style: resolvedTitleStyle),
            if (showTitle && showSubtitle) SizedBox(height: titleGap),
            if (showSubtitle) Text(subtitleText, style: resolvedSubtitleStyle),
            if (showTitle || showSubtitle) SizedBox(height: resolvedContentGap),
            child,
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
