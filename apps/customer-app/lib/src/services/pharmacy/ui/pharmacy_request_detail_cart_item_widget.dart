import 'package:flutter/material.dart';

final class PharmacyRequestDetailCartItemWidget extends StatelessWidget {
  const PharmacyRequestDetailCartItemWidget({
    super.key,
    required this.title,
    required this.quantity,
    required this.unitPriceText,
    required this.rxRequired,
    this.surface = 'flat',
    this.density = 'compact',
  });

  final String title;
  final int quantity;
  final String unitPriceText;
  final bool rxRequired;
  final String surface;
  final String density;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = density.trim().toLowerCase() == 'compact';
    final horizontalPadding = compact ? 12.0 : 14.0;
    final verticalPadding = compact ? 10.0 : 12.0;
    final spacing = compact ? 8.0 : 10.0;

    final safeTitle = title.trim().isEmpty ? 'Item' : title.trim();
    final safeQty = quantity < 0 ? 0 : quantity;
    final price = unitPriceText.trim();

    return Card(
      elevation: switch (surface.trim().toLowerCase()) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              safeTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (price.isNotEmpty)
                  Text(
                    price,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (rxRequired) _RxTag(compact: compact),
                Text(
                  'Qty $safeQty',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _RxTag extends StatelessWidget {
  const _RxTag({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3 : 4,
        ),
        child: Text(
          'Rx',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
