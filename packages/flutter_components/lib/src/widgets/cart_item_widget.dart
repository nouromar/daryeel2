import 'package:flutter/material.dart';

class CartItemWidget extends StatelessWidget {
  const CartItemWidget({
    super.key,
    required this.title,
    required this.quantity,
    this.subtitle = '',
    this.unitPriceText,
    this.lineTotalText,
    this.badgeLabel,
    this.surface = 'raised',
    this.density = 'comfortable',
    this.onIncrement,
    this.onDecrement,
  });

  final String title;
  final String subtitle;
  final int quantity;
  final String? unitPriceText;
  final String? lineTotalText;
  final String? badgeLabel;
  final String surface;
  final String density;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = density.trim().toLowerCase() == 'compact';
    final horizontalPadding = compact ? 12.0 : 14.0;
    final verticalPadding = compact ? 10.0 : 12.0;
    final spacing = compact ? 8.0 : 10.0;
    final safeQuantity = quantity < 0 ? 0 : quantity;
    final badge = badgeLabel?.trim() ?? '';
    final normalizedSubtitle = subtitle.trim();
    final normalizedUnitPrice = unitPriceText?.trim() ?? '';
    final normalizedLineTotal = lineTotalText?.trim() ?? '';
    final showSubtitle = normalizedSubtitle.isNotEmpty &&
        normalizedSubtitle != normalizedUnitPrice &&
        normalizedSubtitle != normalizedLineTotal;
    final hasUnitPrice = normalizedUnitPrice.isNotEmpty;
    final hasLineTotal = normalizedLineTotal.isNotEmpty;
    final showLineTotal =
        hasLineTotal && normalizedLineTotal != normalizedUnitPrice;
    final hasMetaRow = hasUnitPrice || showLineTotal || badge.isNotEmpty;

    return Card(
      elevation: switch (surface) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.trim().isEmpty ? 'Item' : title.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showSubtitle) ...[
                    SizedBox(height: spacing * 0.6),
                    Text(
                      normalizedSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (hasMetaRow) ...[
                    SizedBox(height: spacing),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (hasUnitPrice)
                          Text(
                            'Price: $normalizedUnitPrice',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (showLineTotal)
                          Text(
                            'Line: $normalizedLineTotal',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (badge.isNotEmpty)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              child: Text(
                                badge,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: spacing),
            _CartQuantityStepper(
              quantity: safeQuantity,
              compact: compact,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
            ),
          ],
        ),
      ),
    );
  }
}

final class _CartQuantityStepper extends StatelessWidget {
  const _CartQuantityStepper({
    required this.quantity,
    required this.compact,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final bool compact;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = compact ? 18.0 : 20.0;
    final minHeight = compact ? 34.0 : 38.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surface,
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints:
                  BoxConstraints(minWidth: minHeight, minHeight: minHeight),
              tooltip: quantity <= 1 ? 'Remove item' : 'Decrease quantity',
              onPressed: onDecrement,
              icon: Icon(
                quantity <= 1 ? Icons.delete_outline : Icons.remove,
                size: iconSize,
              ),
            ),
            Container(
              constraints: BoxConstraints(minWidth: compact ? 26 : 30),
              alignment: Alignment.center,
              child: Text(
                '$quantity',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints:
                  BoxConstraints(minWidth: minHeight, minHeight: minHeight),
              tooltip: 'Increase quantity',
              onPressed: onIncrement,
              icon: Icon(Icons.add, size: iconSize),
            ),
          ],
        ),
      ),
    );
  }
}
