import 'package:flutter/material.dart';

@immutable
final class CartSummaryRowData {
  const CartSummaryRowData({
    required this.label,
    required this.amount,
    required this.amountText,
    this.kind = 'default',
    this.emphasis = 'normal',
  });

  final String label;
  final double amount;
  final String amountText;
  final String kind;
  final String emphasis;
}

class CartSummaryWidget extends StatelessWidget {
  const CartSummaryWidget({
    super.key,
    required this.lines,
    this.total,
    this.title = 'Order summary',
    this.surface = 'raised',
    this.density = 'comfortable',
    this.hideZeroLines = true,
  });

  final List<CartSummaryRowData> lines;
  final CartSummaryRowData? total;
  final String title;
  final String surface;
  final String density;
  final bool hideZeroLines;

  @override
  Widget build(BuildContext context) {
    final compact = density.trim().toLowerCase() == 'compact';
    final effectiveTitle = title.trim();
    final visibleLines = hideZeroLines
        ? lines
            .where((row) => row.amount.abs() > 0.000001)
            .toList(growable: false)
        : List<CartSummaryRowData>.of(lines, growable: false);

    if (visibleLines.isEmpty && total == null) {
      return const SizedBox.shrink();
    }

    final horizontalPadding = compact ? 12.0 : 14.0;
    final verticalPadding = compact ? 12.0 : 14.0;
    final sectionGap = compact ? 10.0 : 12.0;
    final theme = Theme.of(context);

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (effectiveTitle.isNotEmpty) ...[
              Text(
                effectiveTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: sectionGap),
            ],
            ...visibleLines.map(
              (row) => Padding(
                padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                child: _CartSummaryRow(row: row),
              ),
            ),
            if (total != null) ...[
              if (visibleLines.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
                  child: Divider(
                    height: 1,
                    color: theme.dividerColor,
                  ),
                ),
              _CartSummaryRow(row: total!, isTotal: true),
            ],
          ],
        ),
      ),
    );
  }
}

final class _CartSummaryRow extends StatelessWidget {
  const _CartSummaryRow({required this.row, this.isTotal = false});

  final CartSummaryRowData row;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            row.label,
            style: _resolveTextStyle(context, label: true),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          row.amountText,
          style: _resolveTextStyle(context, label: false),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  TextStyle? _resolveTextStyle(BuildContext context, {required bool label}) {
    final theme = Theme.of(context);
    final base =
        isTotal ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium;
    final normalizedKind = row.kind.trim().toLowerCase();
    final normalizedEmphasis = row.emphasis.trim().toLowerCase();

    Color? color;
    FontWeight? weight;

    if (isTotal) {
      weight = FontWeight.w700;
    } else {
      switch (normalizedKind) {
        case 'discount':
          color = theme.colorScheme.primary;
          weight = FontWeight.w600;
          break;
        case 'fee':
        case 'tax':
          color = theme.colorScheme.onSurfaceVariant;
          break;
      }

      switch (normalizedEmphasis) {
        case 'muted':
          color ??= theme.colorScheme.onSurfaceVariant;
          break;
        case 'strong':
          weight = FontWeight.w600;
          break;
      }
    }

    return base?.copyWith(color: color, fontWeight: weight);
  }
}
