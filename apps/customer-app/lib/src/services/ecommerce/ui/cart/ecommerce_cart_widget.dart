import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';

import 'ecommerce_cart_models.dart';

final class EcommerceCartWidget extends StatelessWidget {
  const EcommerceCartWidget({
    super.key,
    required this.lines,
    required this.totals,
    required this.hasPrescription,
    required this.showPrescriptionCta,
    required this.surface,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onIncrement,
    required this.onDecrement,
    required this.onClear,
    required this.onCheckout,
    this.onAttachPrescription,
    this.prescriptionSection,
  });

  final List<EcommerceCartLine> lines;
  final EcommerceCartTotals totals;

  final bool hasPrescription;
  final bool showPrescriptionCta;

  final String surface;

  final String emptyTitle;
  final String emptySubtitle;

  final void Function(String lineId) onIncrement;
  final void Function(String lineId) onDecrement;
  final VoidCallback onClear;
  final VoidCallback onCheckout;
  final VoidCallback? onAttachPrescription;

  /// Optional product-specific widget shown between cart lines and summary.
  final Widget? prescriptionSection;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty && !hasPrescription) {
      return InfoCardWidget(
        title: emptyTitle,
        subtitle: emptySubtitle,
        surface: 'subtle',
      );
    }

    final currencySymbol = lines.isNotEmpty ? lines.first.currencySymbol : r'$';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.isNotEmpty) ...[
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CartLineCard(
                line: line,
                surface: surface,
                onIncrement: () => onIncrement(line.id),
                onDecrement: () => onDecrement(line.id),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (prescriptionSection != null) ...[
          prescriptionSection!,
          const SizedBox(height: 12),
        ] else if (showPrescriptionCta && !hasPrescription) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onAttachPrescription,
              child: const Text('Attach Prescription'),
            ),
          ),
          const SizedBox(height: 12),
        ],

        _SummaryCard(
          surface: surface,
          currencySymbol: currencySymbol,
          totals: totals,
        ),

        const SizedBox(height: 12),

        FilledButton(onPressed: onCheckout, child: const Text('Checkout')),

        const SizedBox(height: 12),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onClear,
            child: const Text('Clear cart'),
          ),
        ),
      ],
    );
  }
}

final class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.line,
    required this.surface,
    required this.onIncrement,
    required this.onDecrement,
  });

  final EcommerceCartLine line;
  final String surface;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final priceText = _formatMoney(line.unitPrice, line.currencySymbol);

    final totalText = _formatMoney(line.lineTotal, line.currencySymbol);

    return Card(
      elevation: switch (surface) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.title.isEmpty ? 'Item' : line.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (line.subtitle.trim().isNotEmpty)
                        Text(
                          line.subtitle.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (line.rxRequired)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Text(
                              'Rx',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  if (priceText != null || totalText != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (priceText != null)
                          Text(
                            'Unit: $priceText',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (totalText != null)
                          Text(
                            'Line: $totalText',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _CompactStepper(
              quantity: line.quantity,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
            ),
          ],
        ),
      ),
    );
  }
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.surface,
    required this.currencySymbol,
    required this.totals,
  });

  final String surface;
  final String currencySymbol;
  final EcommerceCartTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(String label, String value, {TextStyle? valueStyle}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(value, style: valueStyle ?? theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    return Card(
      elevation: switch (surface) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Summary',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            row('Subtotal', _formatMoneyValue(totals.subtotal, currencySymbol)),
            row('Tax', _formatMoneyValue(totals.tax, currencySymbol)),
            row('Discount', _formatMoneyValue(totals.discount, currencySymbol)),
            const Divider(height: 18),
            row(
              'Total',
              _formatMoneyValue(totals.total, currencySymbol),
              valueStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CompactStepper extends StatelessWidget {
  const _CompactStepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    const buttonConstraints = BoxConstraints.tightFor(width: 36, height: 36);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decrease quantity',
          constraints: buttonConstraints,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: 'Increase quantity',
          constraints: buttonConstraints,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onIncrement,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

String _formatMoneyValue(double amount, String currencySymbol) {
  final fixed = amount.toStringAsFixed(2);
  return '$currencySymbol$fixed';
}

String? _formatMoney(double? amount, String currencySymbol) {
  if (amount == null) return null;
  return _formatMoneyValue(amount, currencySymbol);
}
