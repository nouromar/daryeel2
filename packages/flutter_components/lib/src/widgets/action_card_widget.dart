import 'package:flutter/material.dart';

class ActionCardWidget extends StatelessWidget {
  const ActionCardWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.surface = 'raised',
    this.density = 'comfortable',
    this.titleVariant,
    this.titleWeight,
    this.titleColor,
    this.subtitleVariant,
    this.subtitleWeight,
    this.subtitleColor,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final String surface;
  final String density;
  final String? titleVariant;
  final String? titleWeight;
  final String? titleColor;
  final String? subtitleVariant;
  final String? subtitleWeight;
  final String? subtitleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final titleText = title.trim();
    final subtitleText = subtitle.trim();

    final showTitle = titleText.isNotEmpty;
    final showSubtitle = subtitleText.isNotEmpty;
    if (!showTitle && !showSubtitle) {
      return const SizedBox.shrink();
    }

    final isCompact = density.trim().toLowerCase() == 'compact';
    final padding = isCompact ? 16.0 : 20.0;
    final titleGap = isCompact ? 4.0 : 6.0;

    final theme = Theme.of(context);

    final baseTitleStyle =
        _resolveVariant(theme, titleVariant) ?? theme.textTheme.titleMedium;
    final baseSubtitleStyle =
        _resolveVariant(theme, subtitleVariant) ?? theme.textTheme.bodyMedium;

    final resolvedTitleStyle = _applyOverrides(
      baseTitleStyle,
      theme: theme,
      colorRaw: titleColor,
      weightRaw: titleWeight,
    );

    final resolvedSubtitleStyle = _applyOverrides(
      baseSubtitleStyle,
      theme: theme,
      colorRaw: subtitleColor,
      weightRaw: subtitleWeight,
    );

    return Card(
      elevation: switch (surface) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: isCompact ? 22 : 24),
                SizedBox(width: isCompact ? 10 : 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showTitle)
                      Text(
                        titleText,
                        style: resolvedTitleStyle,
                      ),
                    if (showTitle && showSubtitle) SizedBox(height: titleGap),
                    if (showSubtitle)
                      Text(
                        subtitleText,
                        style: resolvedSubtitleStyle,
                      ),
                  ],
                ),
              ),
            ],
          ),
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
}) {
  final resolvedColor = _resolveColor(theme, colorRaw);
  final resolvedWeight = _resolveFontWeight(weightRaw);

  if (resolvedColor == null && resolvedWeight == null) return base;
  return (base ?? const TextStyle()).copyWith(
    color: resolvedColor,
    fontWeight: resolvedWeight,
  );
}

Color? _resolveColor(ThemeData theme, String? colorRaw) {
  final v = colorRaw?.trim().toLowerCase();
  final scheme = theme.colorScheme;

  return switch (v) {
    'muted' || 'subtle' || 'secondarytext' => scheme.onSurfaceVariant,
    'primary' => scheme.primary,
    'secondary' => scheme.secondary,
    'error' => scheme.error,
    'default' || null || '' => null,
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
