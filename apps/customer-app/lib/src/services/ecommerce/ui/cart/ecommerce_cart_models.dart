import 'package:flutter/foundation.dart';

@immutable
final class EcommerceCartLine {
  const EcommerceCartLine({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.rxRequired,
    required this.unitPrice,
    required this.currencySymbol,
  });

  final String id;
  final String title;
  final String subtitle;
  final int quantity;
  final bool rxRequired;

  /// Unit price in display currency, if known.
  ///
  /// May be null for legacy carts (in which case the UI should degrade
  /// gracefully).
  final double? unitPrice;

  /// Currency symbol to show (e.g. `$`).
  ///
  /// Prefer passing this explicitly for theme/app consistency.
  final String currencySymbol;

  double? get lineTotal {
    final p = unitPrice;
    if (p == null) return null;
    return p * quantity;
  }
}

@immutable
final class EcommerceCartTotals {
  const EcommerceCartTotals({
    required this.subtotal,
    required this.tax,
    required this.discount,
  });

  final double subtotal;
  final double tax;
  final double discount;

  double get total => subtotal + tax - discount;
}
